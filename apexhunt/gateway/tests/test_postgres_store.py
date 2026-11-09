"""Integration test for PostgresStore. Runs only when TEST_DATABASE_URL points at a
database where schema.sql has been applied, e.g.

    TEST_DATABASE_URL=postgresql://postgres:pg@127.0.0.1/apex_test pytest tests/test_postgres_store.py
"""

import asyncio
import os
import time
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

os.environ.setdefault("SUPABASE_JWT_SECRET", "test-secret-test-secret-test-secret-32")

import httpx  # noqa: E402
import jwt  # noqa: E402
import pytest  # noqa: E402

from app import main as gateway  # noqa: E402
from app.config import Settings  # noqa: E402
from app.store import AccountDeleted, LedgerEntry, PostgresStore  # noqa: E402

DSN = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="TEST_DATABASE_URL not set")


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_wallet_lifecycle():
    store = await PostgresStore.connect(DSN)
    uid = str(uuid.uuid4())
    run = uuid.uuid4().hex[:8]  # purchase keys outlive deletion (#4), so keep them unique per run
    try:
        w = await store.get_or_create_wallet(uid, "a@b.co", Decimal("0.50"))
        assert w.credit_balance_usd == Decimal("0.5") and not w.has_active_subscription
        again = await store.get_or_create_wallet(uid, "a@b.co", Decimal("0.50"))
        assert again.credit_balance_usd == Decimal("0.5"), "welcome credit granted once"

        bal = await store.charge(LedgerEntry(uid, "anthropic/claude-haiku-5.5", 8000, 4000, Decimal("0.0036"),
                                             Decimal("0.012"), Decimal("0.01794")))
        assert bal == Decimal("0.48206")

        assert await store.credit_purchase(f"txn:GPA.1.{run}", uid, "apex_credits_5", Decimal("5"), "NON_RENEWING_PURCHASE", "PRODUCTION")
        assert not await store.credit_purchase(f"txn:GPA.1.{run}", uid, "apex_credits_5", Decimal("5"), "NON_RENEWING_PURCHASE", "PRODUCTION")
        exp = datetime.now(timezone.utc) + timedelta(days=30)
        assert await store.set_subscription(uid, "ACTIVE", "apex_pro_monthly", exp, f"txn:GPA.2.{run}:INITIAL_PURCHASE", "INITIAL_PURCHASE", "PRODUCTION")
        w = await store.get_wallet(uid)
        assert w.credit_balance_usd == Decimal("5.48206") and w.has_active_subscription

        await store.add_flag(uid, "cv", "inaccurate", "", "excerpt")
        await store.delete_user(uid)
        assert await store.get_wallet(uid) is None
        assert await store.pool.fetchval("SELECT count(*) FROM apexhunt.llm_usage_ledger WHERE user_id=$1", uuid.UUID(uid)) == 0
    finally:
        await store.close()


@pytest.mark.anyio
async def test_parallel_holds_never_exceed_balance():
    """#5: reservations queue on the wallet row, so concurrent calls can't hold more than the balance."""
    store = await PostgresStore.connect(DSN)
    uid = str(uuid.uuid4())

    def entry(charge):
        return LedgerEntry(uid, "anthropic/claude-sonnet-5.5", 50, 2000, Decimal("0.02"), Decimal("0.00205"), charge)

    try:
        await store.get_or_create_wallet(uid, None, Decimal("0.50"))
        holds = await asyncio.gather(*[store.reserve(uid, Decimal("0.12"), 900) for _ in range(20)])
        granted = [h for h in holds if h]
        assert len(granted) == 4, "4 x $0.12 fits in $0.50, a 5th doesn't"
        # Charging a call drops its hold; releasing a failed call's hold frees it.
        assert await store.settle(entry(Decimal("0.025358")), granted[0]) == Decimal("0.474642")
        await store.release(granted[1])
        # Still held: 2 x $0.12, leaving $0.234642 free.
        assert await store.reserve(uid, Decimal("0.24"), 900) is None
        assert await store.reserve(uid, Decimal("0.23"), 900) is not None
        # Holds whose calls died mid-request (deploy, crash) stop counting after the TTL.
        await store.pool.execute("UPDATE apexhunt.wallet_holds SET created_at = now() - interval '16 minutes' "
                                 "WHERE user_id = $1", uuid.UUID(uid))
        last = await store.reserve(uid, Decimal("0.47"), 900)
        assert last is not None
        count = "SELECT count(*) FROM apexhunt.wallet_holds WHERE user_id = $1"
        assert await store.pool.fetchval(count, uuid.UUID(uid)) == 1
        assert (await store.get_wallet(uid)).credit_balance_usd == Decimal("0.474642"), "holds never move money"
        # Deleting the account removes its holds, and a call that finishes afterwards isn't recorded.
        await store.delete_user(uid)
        assert await store.pool.fetchval(count, uuid.UUID(uid)) == 0
        with pytest.raises(AccountDeleted):
            await store.settle(entry(Decimal("0.025358")), last)
    finally:
        await store.close()


@pytest.mark.anyio
async def test_deletion_keeps_tombstone_and_purchase_keys():
    """#4: a deleted id can't get a wallet again, and its purchases can't be credited a second time to anyone."""
    store = await PostgresStore.connect(DSN)
    uid, other = str(uuid.uuid4()), str(uuid.uuid4())
    key = f"txn:GPA.{uuid.uuid4().hex[:10]}"
    try:
        await store.get_or_create_wallet(uid, "gone@b.co", Decimal("0.50"))
        assert await store.credit_purchase(key, uid, "apex_credits_10", Decimal("10"), "NON_RENEWING_PURCHASE", "PRODUCTION")
        await store.delete_user(uid)
        await store.delete_user(uid)  # idempotent
        assert await store.is_deleted(uid) and not await store.is_deleted(other)
        with pytest.raises(AccountDeleted):
            await store.get_or_create_wallet(uid, "gone@b.co", Decimal("0.50"))
        assert await store.get_wallet(uid) is None
        # The kept purchase record has no link to the person, and the key still blocks a second credit,
        # for the deleted id or for another account (e.g. after RevenueCat transfers the purchase).
        assert await store.pool.fetchval("SELECT user_id FROM apexhunt.purchase_events WHERE idempotency_key=$1", key) is None
        assert not await store.credit_purchase(key, uid, "apex_credits_10", Decimal("10"), "SYNC", "PRODUCTION")
        await store.get_or_create_wallet(other, None, Decimal("0"))
        assert not await store.credit_purchase(key, other, "apex_credits_10", Decimal("10"), "SYNC", "PRODUCTION")
        assert (await store.get_wallet(other)).credit_balance_usd == Decimal("0")
        # A late webhook for the deleted id records its key but doesn't re-create the account.
        late = f"txn:late.{uuid.uuid4().hex[:10]}"
        assert not await store.credit_purchase(late, uid, "apex_credits_5", Decimal("5"), "NON_RENEWING_PURCHASE", "PRODUCTION")
        assert not await store.set_subscription(uid, "ACTIVE", "apex_pro_monthly", None, f"{late}:RENEWAL", "RENEWAL", "PRODUCTION")
        assert await store.pool.fetchval("SELECT count(*) FROM apexhunt.app_users WHERE id=$1", uuid.UUID(uid)) == 0
        assert await store.pool.fetchval("SELECT count(*) FROM apexhunt.purchase_events WHERE idempotency_key = ANY($1)",
                                         [late, f"{late}:RENEWAL"]) == 2
    finally:
        await store.pool.execute("DELETE FROM apexhunt.app_users WHERE id=$1", uuid.UUID(other))
        await store.close()


@pytest.mark.anyio
async def test_delete_then_sync_cannot_mint_credits():
    """#4 end to end: /me → /billing/sync → DELETE, repeated with the same token, credits the pack exactly once."""
    store = await PostgresStore.connect(DSN)
    user = str(uuid.uuid4())
    txn = f"GPA.{uuid.uuid4().hex[:10]}"
    auth = {"Authorization": "Bearer " + jwt.encode(
        {"sub": user, "email": "loop@example.com", "aud": "authenticated", "exp": int(time.time()) + 600},
        os.environ["SUPABASE_JWT_SECRET"], algorithm="HS256")}

    def revenuecat(request: httpx.Request) -> httpx.Response:  # the user bought one $10 pack
        return httpx.Response(200, json={"subscriber": {"entitlements": {}, "non_subscriptions": {
            "apex_credits_10": [{"id": "rc1", "store_transaction_id": txn, "is_sandbox": False}]}}})

    cfg = Settings()
    cfg.revenuecat_secret_key = "sk_test"
    app = gateway.create_app(store=store, cfg=cfg, sync_catalog=False)
    statuses = []
    async with app.router.lifespan_context(app):  # closes the store on exit
        await gateway.state.http.aclose()
        gateway.state.http = httpx.AsyncClient(transport=httpx.MockTransport(revenuecat))
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t") as c:
            for _ in range(3):
                me = await c.get("/api/v1/me", headers=auth)
                sync = await c.post("/api/v1/billing/sync", headers=auth)
                statuses.append((me.status_code, sync.status_code,
                                 sync.json().get("credited") if sync.status_code == 200 else None))
                assert (await c.delete("/api/v1/users/me", headers=auth)).status_code == 200
        kept = await store.pool.fetchval("SELECT count(*) FROM apexhunt.purchase_events WHERE idempotency_key=$1",
                                         f"txn:{txn}")
    assert statuses == [(200, 200, 10.0), (401, 401, None), (401, 401, None)]
    assert kept == 1
