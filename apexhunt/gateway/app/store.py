"""Persistence for wallets, the token ledger, purchases and AI-output flags.

`PostgresStore` is used in production (Supabase Postgres). `MemoryStore` backs the
test-suite and local runs without a database. Career data (CVs, tailored
documents, prep dossiers) is never stored server-side: it lives on the device.
"""

from __future__ import annotations

import asyncio
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional, Protocol

ACTIVE_STATES = ("ACTIVE", "GRACE_PERIOD")


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
    async def charge(self, entry: LedgerEntry) -> Decimal: ...
    async def credit_purchase(self, idempotency_key: str, user_id: str, product_id: str, credit_usd: Decimal,
                              event_type: str, environment: str) -> bool: ...
    async def set_subscription(self, user_id: str, status: str, plan_id: Optional[str],
                               expires_at: Optional[datetime], idempotency_key: Optional[str] = None,
                               event_type: str = "", environment: str = "") -> bool: ...
    async def add_flag(self, user_id: str, artifact_kind: str, reason: str, notes: str, excerpt: str) -> str: ...
    async def delete_user(self, user_id: str) -> None: ...
    async def close(self) -> None: ...


# --------------------------------------------------------------------------- memory


@dataclass
class MemoryStore:
    wallets: dict[str, Wallet] = field(default_factory=dict)
    ledger: list[LedgerEntry] = field(default_factory=list)
    purchase_keys: set[str] = field(default_factory=set)
    flags: list[dict] = field(default_factory=list)
    _lock: asyncio.Lock = field(default_factory=asyncio.Lock)

    async def get_or_create_wallet(self, user_id, email, welcome_credit):
        async with self._lock:
            if user_id not in self.wallets:
                self.wallets[user_id] = Wallet(user_id=user_id, credit_balance_usd=Decimal(welcome_credit))
            return self.wallets[user_id]

    async def get_wallet(self, user_id):
        return self.wallets.get(user_id)

    async def charge(self, entry):
        async with self._lock:
            w = self.wallets[entry.user_id]
            w.credit_balance_usd -= entry.total_deducted_usd
            w.lifetime_spent_usd += entry.total_deducted_usd
            self.ledger.append(entry)
            return w.credit_balance_usd

    async def credit_purchase(self, idempotency_key, user_id, product_id, credit_usd, event_type, environment):
        async with self._lock:
            if idempotency_key in self.purchase_keys:
                return False
            self.purchase_keys.add(idempotency_key)
            w = self.wallets.setdefault(user_id, Wallet(user_id=user_id, credit_balance_usd=Decimal("0")))
            w.credit_balance_usd += credit_usd
            return True

    async def set_subscription(self, user_id, status, plan_id, expires_at, idempotency_key=None, event_type="", environment=""):
        async with self._lock:
            if idempotency_key:
                if idempotency_key in self.purchase_keys:
                    return False
                self.purchase_keys.add(idempotency_key)
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
        self.wallets.pop(user_id, None)
        self.ledger = [e for e in self.ledger if e.user_id != user_id]
        self.flags = [f for f in self.flags if f["user_id"] != user_id]

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

    async def get_or_create_wallet(self, user_id, email, welcome_credit):
        async with self.pool.acquire() as con:
            async with con.transaction():
                await con.execute(
                    "INSERT INTO apexhunt.app_users (id, email) VALUES ($1, $2) "
                    "ON CONFLICT (id) DO UPDATE SET email = COALESCE(EXCLUDED.email, apexhunt.app_users.email), "
                    "last_seen_at = now()",
                    uuid.UUID(user_id), email)
                await con.execute(
                    "INSERT INTO apexhunt.user_wallets (user_id, credit_balance_usd) VALUES ($1, $2) "
                    "ON CONFLICT (user_id) DO NOTHING",
                    uuid.UUID(user_id), welcome_credit)
                row = await con.fetchrow(f"SELECT {_WALLET_COLS} FROM apexhunt.user_wallets WHERE user_id = $1",
                                         uuid.UUID(user_id))
                return _wallet_from_row(row)

    async def get_wallet(self, user_id):
        row = await self.pool.fetchrow(f"SELECT {_WALLET_COLS} FROM apexhunt.user_wallets WHERE user_id = $1",
                                       uuid.UUID(user_id))
        return _wallet_from_row(row) if row else None

    async def charge(self, entry):
        uid = uuid.UUID(entry.user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
                balance = await con.fetchval(
                    "UPDATE apexhunt.user_wallets SET credit_balance_usd = credit_balance_usd - $2, "
                    "lifetime_spent_usd = lifetime_spent_usd + $2, updated_at = now() "
                    "WHERE user_id = $1 RETURNING credit_balance_usd",
                    uid, entry.total_deducted_usd)
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
            key, uuid.UUID(user_id), product_id, credit_usd, event_type, environment)
        return bool(inserted)

    async def credit_purchase(self, idempotency_key, user_id, product_id, credit_usd, event_type, environment):
        uid = uuid.UUID(user_id)
        async with self.pool.acquire() as con:
            async with con.transaction():
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
        # ON DELETE CASCADE removes wallet, ledger, purchase events and flags.
        await self.pool.execute("DELETE FROM apexhunt.app_users WHERE id = $1", uuid.UUID(user_id))

    async def close(self):
        await self.pool.close()
