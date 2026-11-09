"""Persistence for wallets, the token ledger, purchases and AI-output flags.

`PostgresStore` is used in production (Supabase Postgres). `MemoryStore` backs the
test-suite and local runs without a database. Career data (CVs, tailored
documents, prep dossiers) is never stored server-side: it lives on the device.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional, Protocol

ACTIVE_STATES = ("ACTIVE", "GRACE_PERIOD")


class AccountDeleted(Exception):
    """The user deleted their account. Their id never gets a wallet again, even with a still-valid token."""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class Wallet:
    user_id: str
    credit_balance_usd: Decimal
    subscription_status: str = "INACTIVE"
    subscription_plan_id: Optional[str] = None
    subscription_expires_at: Optional[datetime] = None
    lifetime_spent_usd: Decimal = Decimal("0")

    @property
    def has_active_subscription(self) -> bool:
        if self.subscription_status not in ACTIVE_STATES:
            return False
        return self.subscription_expires_at is None or self.subscription_expires_at > utcnow()

    def to_json(self) -> dict:
        return {
            "credit_balance_usd": float(self.credit_balance_usd),
            "subscription_status": self.subscription_status,
            "subscription_plan_id": self.subscription_plan_id,
            "subscription_expires_at": self.subscription_expires_at.isoformat() if self.subscription_expires_at else None,
            "has_active_subscription": self.has_active_subscription,
            "lifetime_spent_usd": float(self.lifetime_spent_usd),
        }


@dataclass
class LedgerEntry:
    user_id: str
    upstream_model_slug: str
    prompt_tokens: int
    completion_tokens: int
    upstream_cost_usd: Decimal
    platform_markup_usd: Decimal
    total_deducted_usd: Decimal
    purpose: str = "chat"
    execution_mode: str = "MANAGED_PROXY"


class Store(Protocol):
    async def get_or_create_wallet(self, user_id: str, email: Optional[str], welcome_credit: Decimal) -> Wallet: ...
    async def get_wallet(self, user_id: str) -> Optional[Wallet]: ...
    # Managed AI calls hold their worst-case cost before calling upstream, so parallel requests can't spend
    # more than the balance (#5). reserve() returns a hold id, or None when balance minus live holds is too low.
    # Then settle() charges the real cost and drops the hold, or release() drops it if the call failed.
    # Holds never change the balance itself, and one older than ttl_seconds stops counting, so a request
    # killed mid-call (deploy, crash) can't lock up credits for good.
    async def reserve(self, user_id: str, amount: Decimal, ttl_seconds: int) -> Optional[str]: ...
    async def release(self, hold_id: str) -> None: ...
    async def settle(self, entry: LedgerEntry, hold_id: Optional[str]) -> Decimal: ...
    async def charge(self, entry: LedgerEntry) -> Decimal: ...
    async def credit_purchase(self, idempotency_key: str, user_id: str, product_id: str, credit_usd: Decimal,
                              event_type: str, environment: str) -> bool: ...
    async def set_subscription(self, user_id: str, status: str, plan_id: Optional[str],
                               expires_at: Optional[datetime], idempotency_key: Optional[str] = None,
                               event_type: str = "", environment: str = "") -> bool: ...
    async def add_flag(self, user_id: str, artifact_kind: str, reason: str, notes: str, excerpt: str) -> str: ...
    async def delete_user(self, user_id: str) -> None: ...
    async def is_deleted(self, user_id: str) -> bool: ...
    async def close(self) -> None: ...


# --------------------------------------------------------------------------- memory


@dataclass
class MemoryStore:
    """Mirrors PostgresStore's rules, including deletion tombstones and kept purchase keys."""

    wallets: dict[str, Wallet] = field(default_factory=dict)
    ledger: list[LedgerEntry] = field(default_factory=list)
    purchase_keys: set[str] = field(default_factory=set)
    flags: list[dict] = field(default_factory=list)
    deleted: set[str] = field(default_factory=set)
    holds: dict[str, tuple[str, Decimal, float]] = field(default_factory=dict)  # id -> (user, amount, monotonic)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def get_or_create_wallet(self, user_id, email, welcome_credit):
        async with self._lock:
            if user_id in self.deleted:
                raise AccountDeleted(user_id)
            if user_id not in self.wallets:
                self.wallets[user_id] = Wallet(user_id=user_id, credit_balance_usd=Decimal(welcome_credit))
            return self.wallets[user_id]

    async def get_wallet(self, user_id):
        return self.wallets.get(user_id)

    async def reserve(self, user_id, amount, ttl_seconds):
        async with self._lock:
            w = self.wallets.get(user_id)
            if w is None:
                return None
            now = time.monotonic()
            for hid in [h for h, (u, _, t) in self.holds.items() if u == user_id and now - t >= ttl_seconds]:
                del self.holds[hid]  # expired: its request died without settling or releasing
            held = sum((a for u, a, _ in self.holds.values() if u == user_id), Decimal("0"))
            if w.credit_balance_usd - held < amount:
                return None
            hold_id = str(uuid.uuid4())
            self.holds[hold_id] = (user_id, amount, now)
            return hold_id

    async def release(self, hold_id):
        async with self._lock:
            self.holds.pop(hold_id, None)

    async def settle(self, entry, hold_id):
        async with self._lock:
            if hold_id:
                self.holds.pop(hold_id, None)
            w = self.wallets.get(entry.user_id)
            if w is None:  # deleted while the AI call was running
                raise AccountDeleted(entry.user_id)
            w.credit_balance_usd -= entry.total_deducted_usd
            w.lifetime_spent_usd += entry.total_deducted_usd
            self.ledger.append(entry)
            return w.credit_balance_usd

    async def charge(self, entry):
        return await self.settle(entry, None)

    async def credit_purchase(self, idempotency_key, user_id, product_id, credit_usd, event_type, environment):
        async with self._lock:
            if idempotency_key in self.purchase_keys:
                return False
            self.purchase_keys.add(idempotency_key)
            if user_id in self.deleted:  # key kept, account not re-created
                return False
            w = self.wallets.setdefault(user_id, Wallet(user_id=user_id, credit_balance_usd=Decimal("0")))
            w.credit_balance_usd += credit_usd
            return True

    async def set_subscription(self, user_id, status, plan_id, expires_at, idempotency_key=None, event_type="", environment=""):
        async with self._lock:
            if idempotency_key:
                if idempotency_key in self.purchase_keys:
                    return False
                self.purchase_keys.add(idempotency_key)
            if user_id in self.deleted:
                return False
            w = self.wallets.setdefault(user_id, Wallet(user_id=user_id, credit_balance_usd=Decimal("0")))
            w.subscription_status = status
            w.subscription_plan_id = plan_id
            w.subscription_expires_at = expires_at
            return True

    async def add_flag(self, user_id, artifact_kind, reason, notes, excerpt):
        fid = str(uuid.uuid4())
        self.flags.append({"id": fid, "user_id": user_id, "artifact_kind": artifact_kind, "reason": reason,
                           "notes": notes, "excerpt": excerpt})
        return fid

    async def delete_user(self, user_id):
        async with self._lock:
            self.deleted.add(user_id)
            self.wallets.pop(user_id, None)
            self.holds = {h: v for h, v in self.holds.items() if v[0] != user_id}
            self.ledger = [e for e in self.ledger if e.user_id != user_id]
            self.flags = [f for f in self.flags if f["user_id"] != user_id]
            # purchase_keys stay on purpose: a purchase must never be credited twice.

    async def is_deleted(self, user_id):
        return user_id in self.deleted

    async def close(self):
        return None


# --------------------------------------------------------------------------- postgres

_WALLET_COLS = ("user_id, credit_balance_usd, subscription_status, subscription_plan_id, "
                "subscription_expires_at, lifetime_spent_usd")


def _wallet_from_row(row) -> Wallet:
    return Wallet(
        user_id=str(row["user_id"]),
        credit_balance_usd=Decimal(row["credit_balance_usd"]),
        subscription_status=row["subscription_status"],
        subscription_plan_id=row["subscription_plan_id"],
        subscription_expires_at=row["subscription_expires_at"],
        lifetime_spent_usd=Decimal(row["lifetime_spent_usd"]),
    )


class PostgresStore:
    def __init__(self, pool):
        self.pool = pool

    @classmethod
    async def connect(cls, dsn: str) -> "PostgresStore":
        import asyncpg

        # statement_cache_size=0 keeps asyncpg compatible with Supabase's pgbouncer pooler.
        pool = await asyncpg.create_pool(dsn, min_size=1, max_size=10, statement_cache_size=0,
                                         server_settings={"search_path": "apexhunt,public"})
        return cls(pool)

    @staticmethod
    async def _is_deleted(con, uid: uuid.UUID) -> bool:
        return await con.fetchval("SELECT 1 FROM apexhunt.deleted_users WHERE id = $1", uid) is not None

    async def get_or_create_wallet(self, user_id, email, welcome_credit):
        uid = uuid.UUID(user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
                if await self._is_deleted(con, uid):
                    raise AccountDeleted(user_id)
                await con.execute(
                    "INSERT INTO apexhunt.app_users (id, email) VALUES ($1, $2) "
                    "ON CONFLICT (id) DO UPDATE SET email = COALESCE(EXCLUDED.email, apexhunt.app_users.email), "
                    "last_seen_at = now()",
                    uid, email)
                await con.execute(
                    "INSERT INTO apexhunt.user_wallets (user_id, credit_balance_usd) VALUES ($1, $2) "
                    "ON CONFLICT (user_id) DO NOTHING",
                    uid, welcome_credit)
                # Check again: a deletion that committed while this transaction waited on the row lock must win
                # (raising rolls back the wallet that was just created).
                if await self._is_deleted(con, uid):
                    raise AccountDeleted(user_id)
                row = await con.fetchrow(f"SELECT {_WALLET_COLS} FROM apexhunt.user_wallets WHERE user_id = $1", uid)
                return _wallet_from_row(row)

    async def get_wallet(self, user_id):
        row = await self.pool.fetchrow(f"SELECT {_WALLET_COLS} FROM apexhunt.user_wallets WHERE user_id = $1",
                                       uuid.UUID(user_id))
        return _wallet_from_row(row) if row else None

    async def reserve(self, user_id, amount, ttl_seconds):
        uid = uuid.UUID(user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
                # The wallet row lock queues this user's reservations, so each one sees the holds before it.
                balance = await con.fetchval(
                    "SELECT credit_balance_usd FROM apexhunt.user_wallets WHERE user_id = $1 FOR UPDATE", uid)
                if balance is None:
                    return None
                await con.execute("DELETE FROM apexhunt.wallet_holds WHERE user_id = $1 "
                                  "AND created_at <= now() - $2::int * interval '1 second'", uid, ttl_seconds)
                held = await con.fetchval(
                    "SELECT coalesce(sum(amount_usd), 0) FROM apexhunt.wallet_holds WHERE user_id = $1", uid)
                if Decimal(balance) - Decimal(held) < amount:
                    return None
                hold_id = await con.fetchval(
                    "INSERT INTO apexhunt.wallet_holds (user_id, amount_usd) VALUES ($1, $2) RETURNING id", uid, amount)
                return str(hold_id)

    async def release(self, hold_id):
        await self.pool.execute("DELETE FROM apexhunt.wallet_holds WHERE id = $1", uuid.UUID(hold_id))

    async def charge(self, entry):
        return await self.settle(entry, None)

    async def settle(self, entry, hold_id):
        uid = uuid.UUID(entry.user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
                if hold_id:
                    await con.execute("DELETE FROM apexhunt.wallet_holds WHERE id = $1", uuid.UUID(hold_id))
                balance = await con.fetchval(
                    "UPDATE apexhunt.user_wallets SET credit_balance_usd = credit_balance_usd - $2, "
                    "lifetime_spent_usd = lifetime_spent_usd + $2, updated_at = now() "
                    "WHERE user_id = $1 RETURNING credit_balance_usd",
                    uid, entry.total_deducted_usd)
                if balance is None:  # deleted while the AI call was running
                    raise AccountDeleted(entry.user_id)
                await con.execute(
                    "INSERT INTO apexhunt.llm_usage_ledger (user_id, execution_mode, purpose, upstream_model_slug, "
                    "prompt_tokens, completion_tokens, upstream_cost_usd, platform_markup_usd, total_deducted_usd, "
                    "net_profit_usd) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)",
                    uid, entry.execution_mode, entry.purpose, entry.upstream_model_slug, entry.prompt_tokens,
                    entry.completion_tokens, entry.upstream_cost_usd, entry.platform_markup_usd,
                    entry.total_deducted_usd, entry.total_deducted_usd - entry.upstream_cost_usd)
                return Decimal(balance)

    async def _record_event(self, con, key, user_id, product_id, credit_usd, event_type, environment) -> bool:
        inserted = await con.fetchval(
            "INSERT INTO apexhunt.purchase_events (idempotency_key, user_id, product_id, credit_usd, event_type, "
            "environment) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (idempotency_key) DO NOTHING RETURNING 1",
            key, uuid.UUID(user_id) if user_id else None, product_id, credit_usd, event_type, environment)
        return bool(inserted)

    async def credit_purchase(self, idempotency_key, user_id, product_id, credit_usd, event_type, environment):
        uid = uuid.UUID(user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
                if await self._is_deleted(con, uid):
                    # Late webhook for a deleted account: keep the key (unlinked) so this purchase can never be
                    # credited later, e.g. after RevenueCat transfers it to a new account. Don't re-create the user.
                    await self._record_event(con, idempotency_key, None, product_id, credit_usd, event_type,
                                             environment)
                    return False
                await con.execute("INSERT INTO apexhunt.app_users (id) VALUES ($1) ON CONFLICT DO NOTHING", uid)
                await con.execute("INSERT INTO apexhunt.user_wallets (user_id, credit_balance_usd) VALUES ($1, 0) "
                                  "ON CONFLICT DO NOTHING", uid)
                if not await self._record_event(con, idempotency_key, user_id, product_id, credit_usd, event_type,
                                                environment):
                    return False
                await con.execute("UPDATE apexhunt.user_wallets SET credit_balance_usd = credit_balance_usd + $2, "
                                  "updated_at = now() WHERE user_id = $1", uid, credit_usd)
                return True

    async def set_subscription(self, user_id, status, plan_id, expires_at, idempotency_key=None, event_type="",
                               environment=""):
        uid = uuid.UUID(user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
                if await self._is_deleted(con, uid):
                    if idempotency_key:
                        await self._record_event(con, idempotency_key, None, plan_id, Decimal("0"), event_type,
                                                 environment)
                    return False
                await con.execute("INSERT INTO apexhunt.app_users (id) VALUES ($1) ON CONFLICT DO NOTHING", uid)
                await con.execute("INSERT INTO apexhunt.user_wallets (user_id, credit_balance_usd) VALUES ($1, 0) "
                                  "ON CONFLICT DO NOTHING", uid)
                if idempotency_key and not await self._record_event(con, idempotency_key, user_id, plan_id,
                                                                    Decimal("0"), event_type, environment):
                    return False
                await con.execute(
                    "UPDATE apexhunt.user_wallets SET subscription_status = $2, subscription_plan_id = $3, "
                    "subscription_expires_at = $4, updated_at = now() WHERE user_id = $1",
                    uid, status, plan_id, expires_at)
                return True

    async def add_flag(self, user_id, artifact_kind, reason, notes, excerpt):
        fid = await self.pool.fetchval(
            "INSERT INTO apexhunt.ai_content_flags (user_id, artifact_kind, reason, notes, excerpt) "
            "VALUES ($1,$2,$3,$4,$5) RETURNING id",
            uuid.UUID(user_id), artifact_kind, reason, notes, excerpt)
        return str(fid)

    async def delete_user(self, user_id):
        uid = uuid.UUID(user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
                # Tombstone: this id never gets a new wallet or welcome credit, even with a still-valid token.
                await con.execute("INSERT INTO apexhunt.deleted_users (id) VALUES ($1) ON CONFLICT DO NOTHING", uid)
                # ON DELETE CASCADE removes the wallet, ledger and flags. purchase_events keep their idempotency
                # keys with user_id set to NULL, so a purchase can never be credited twice.
                await con.execute("DELETE FROM apexhunt.app_users WHERE id = $1", uid)

    async def is_deleted(self, user_id):
        return bool(await self.pool.fetchval(
            "SELECT EXISTS (SELECT 1 FROM apexhunt.deleted_users WHERE id = $1)", uuid.UUID(user_id)))

    async def close(self):
        await self.pool.close()
