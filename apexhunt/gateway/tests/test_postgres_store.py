"""Integration test for PostgresStore. Runs only when TEST_DATABASE_URL points at a
database where schema.sql has been applied, e.g.

    TEST_DATABASE_URL=postgresql://postgres:pg@127.0.0.1/apex_test pytest tests/test_postgres_store.py
"""

import os
import uuid
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest

from app.store import LedgerEntry, PostgresStore

DSN = os.environ.get("TEST_DATABASE_URL")
pytestmark = pytest.mark.skipif(not DSN, reason="TEST_DATABASE_URL not set")


@pytest.fixture
def anyio_backend():
    return "asyncio"


@pytest.mark.anyio
async def test_wallet_lifecycle():
    store = await PostgresStore.connect(DSN)
    uid = str(uuid.uuid4())
    try:
        w = await store.get_or_create_wallet(uid, "a@b.co", Decimal("0.50"))
        assert w.credit_balance_usd == Decimal("0.5") and not w.has_active_subscription
        again = await store.get_or_create_wallet(uid, "a@b.co", Decimal("0.50"))
        assert again.credit_balance_usd == Decimal("0.5"), "welcome credit granted once"

        bal = await store.charge(LedgerEntry(uid, "anthropic/claude-haiku-5.5", 8000, 4000, Decimal("0.0036"),
                                             Decimal("0.012"), Decimal("0.01794")))
        assert bal == Decimal("0.48206")

        assert await store.credit_purchase("txn:GPA.1", uid, "apex_credits_5", Decimal("5"), "NON_RENEWING_PURCHASE", "PRODUCTION")
        assert not await store.credit_purchase("txn:GPA.1", uid, "apex_credits_5", Decimal("5"), "NON_RENEWING_PURCHASE", "PRODUCTION")
        exp = datetime.now(timezone.utc) + timedelta(days=30)
        assert await store.set_subscription(uid, "ACTIVE", "apex_pro_monthly", exp, "txn:GPA.2:INITIAL_PURCHASE", "INITIAL_PURCHASE", "PRODUCTION")
        w = await store.get_wallet(uid)
        assert w.credit_balance_usd == Decimal("5.48206") and w.has_active_subscription

        await store.add_flag(uid, "cv", "inaccurate", "", "excerpt")
        await store.delete_user(uid)
        assert await store.get_wallet(uid) is None
        assert await store.pool.fetchval("SELECT count(*) FROM apexhunt.llm_usage_ledger WHERE user_id=$1", uuid.UUID(uid)) == 0
    finally:
        await store.close()
