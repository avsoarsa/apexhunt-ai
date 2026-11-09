import asyncio
import os
import time
from decimal import Decimal

os.environ.setdefault("SUPABASE_JWT_SECRET", "test-secret-test-secret-test-secret-32")
os.environ.setdefault("OPENROUTER_API_KEY", "sk-test")
os.environ.setdefault("REVENUECAT_WEBHOOK_AUTH", "Bearer rc-hook")

import anyio  # noqa: E402
import httpx  # noqa: E402
import jwt  # noqa: E402
import pytest  # noqa: E402

from app import pricing  # noqa: E402
from app.config import Settings  # noqa: E402
from app.llm import ChatResult, LLMClient, ModelInfo, UpstreamError  # noqa: E402
from app.main import _hits, create_app  # noqa: E402
from app.store import MemoryStore  # noqa: E402

USER = "5b1d8f9e-1c2a-4d3e-9f00-0123456789ab"


def token(sub=USER, email="sk@example.com"):
    return jwt.encode({"sub": sub, "email": email, "aud": "authenticated", "exp": int(time.time()) + 600},
                      os.environ["SUPABASE_JWT_SECRET"], algorithm="HS256")


AUTH = {"Authorization": f"Bearer {token()}"}


class FakeLLM(LLMClient):
    def __init__(self, cfg):
        super().__init__(cfg, http=httpx.AsyncClient())
        self.models = {
            "deepseek/deepseek-v4-flash": ModelInfo("deepseek/deepseek-v4-flash", "DeepSeek V4 Flash",
                                                    Decimal("0.0000003"), Decimal("0.0000003"), 100000, True),
            "anthropic/claude-haiku-5.5": ModelInfo("anthropic/claude-haiku-5.5", "Claude Haiku 5.5",
                                                    Decimal("0.0000001"), Decimal("0.0000005"), 100000, True),
            "anthropic/claude-sonnet-5.5": ModelInfo("anthropic/claude-sonnet-5.5", "Claude Sonnet 5.5",
                                                     Decimal("0.000002"), Decimal("0.00001"), 100000, True),
        }
        self.calls = []

    async def sync_catalog(self):
        return None

    async def chat(self, slug, messages, *, max_tokens, temperature, json_mode):
        self.calls.append(slug)
        return ChatResult(content='{"ok": true}', model_slug=slug, prompt_tokens=8000, completion_tokens=4000,
                          upstream_cost_usd=Decimal("0.0036"))


class GatedLLM(FakeLLM):
    """Keeps every call open until the test opens the gate, so requests overlap like a burst of real taps."""

    def __init__(self, cfg):
        super().__init__(cfg)
        self.gate = asyncio.Event()
        self.fail = False

    async def chat(self, slug, messages, *, max_tokens, temperature, json_mode):
        self.calls.append(slug)
        await self.gate.wait()
        if self.fail:
            raise UpstreamError("The AI engine is busy. Please retry in a moment.", 503)
        return ChatResult(content="{}", model_slug=slug, prompt_tokens=50, completion_tokens=2000,
                          upstream_cost_usd=Decimal("0.02"))


@pytest.fixture(autouse=True)
def _fresh_rate_limit():
    _hits.clear()  # the limiter is per process; don't let one test's requests count against the next


@pytest.fixture
def env():
    cfg = Settings()
    store = MemoryStore()
    llm = FakeLLM(cfg)
    app = create_app(store=store, llm=llm, cfg=cfg, sync_catalog=False)
    return app, store, llm, cfg


@pytest.fixture
def gated():
    cfg = Settings()
    store = MemoryStore()
    llm = GatedLLM(cfg)
    return create_app(store=store, llm=llm, cfg=cfg, sync_catalog=False), store, llm


async def _client(app):
    return httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t")


async def _burst(c, store, llm, n, body):
    """Sends n chat requests at once and opens the gate once each one holds credits or has been refused."""
    tasks = [asyncio.create_task(c.post("/api/v1/llm/chat", headers=AUTH, json=body)) for _ in range(n)]
    with anyio.fail_after(5):
        while len(store.holds) + sum(t.done() for t in tasks) < n:
            await asyncio.sleep(0.01)
    llm.gate.set()
    return await asyncio.gather(*tasks)


# ---------------------------------------------------------------- pricing


def test_markup_formula_matches_spec():
    # Spec example: 12k tokens, $0.0036 upstream -> (0.0036 + 0.012) * 1.15 = 0.01794
    assert pricing.user_charge_usd(Decimal("0.0036"), 8000, 4000) == Decimal("0.017940")
    assert pricing.markup_usd(500_000, 500_000) == Decimal("1.000000")
    assert pricing.display_rate_per_million(Decimal("0.0000003")) == Decimal("1.4950")


# ---------------------------------------------------------------- api


@pytest.mark.anyio
async def test_me_creates_wallet_with_welcome_credit(env):
    app, store, *_ = env
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            r = await c.get("/api/v1/me", headers=AUTH)
    assert r.status_code == 200
    assert r.json()["wallet"]["credit_balance_usd"] == 0.5


@pytest.mark.anyio
async def test_chat_charges_wallet_and_hides_provider(env):
    app, store, llm, _ = env
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            r = await c.post("/api/v1/llm/chat", headers=AUTH, json={
                "model": "apex-pro", "messages": [{"role": "user", "content": "hi"}], "json_mode": True})
            cat = await c.get("/api/v1/llm/catalog")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["charged_usd"] == pytest.approx(0.01794)
    assert body["balance_usd"] == pytest.approx(0.5 - 0.01794)
    assert llm.calls == ["anthropic/claude-haiku-5.5"]
    assert len(store.ledger) == 1 and store.ledger[0].platform_markup_usd == Decimal("0.012000")
    assert "openrouter" not in cat.text.lower()
    assert {t["id"] for t in cat.json()["tiers"]} == {"apex-flash", "apex-pro", "apex-elite"}


@pytest.mark.anyio
async def test_chat_blocks_empty_wallet_and_unknown_models(env):
    app, store, *_ = env
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            await c.get("/api/v1/me", headers=AUTH)
            store.wallets[USER].credit_balance_usd = Decimal("0.01")
            r = await c.post("/api/v1/llm/chat", headers=AUTH,
                             json={"messages": [{"role": "user", "content": "hi"}]})
            assert r.status_code == 402
            store.wallets[USER].credit_balance_usd = Decimal("5")
            r = await c.post("/api/v1/llm/chat", headers=AUTH,
                             json={"model": "openai/o9-ultra", "messages": [{"role": "user", "content": "hi"}]})
            assert r.status_code == 400
            r = await c.post("/api/v1/llm/chat", json={"messages": [{"role": "user", "content": "hi"}]})
            assert r.status_code == 401


ELITE_HI = {"model": "apex-elite", "messages": [{"role": "user", "content": "hi"}]}  # worst case ~$0.038


@pytest.mark.anyio
async def test_parallel_chats_cannot_overspend(gated):
    """#5: five taps at once with room for one worst-case call: one runs, four get 402, balance stays >= 0."""
    app, store, llm = gated
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            await c.get("/api/v1/me", headers=AUTH)
            store.wallets[USER].credit_balance_usd = Decimal("0.05")
            rs = await _burst(c, store, llm, 5, ELITE_HI)
    assert sorted(r.status_code for r in rs) == [200, 402, 402, 402, 402]
    assert len(llm.calls) == 1, "refused requests never reach the AI provider"
    assert "available credits" in next(r for r in rs if r.status_code == 402).json()["detail"]
    balance = store.wallets[USER].credit_balance_usd
    assert balance == Decimal("0.05") - store.ledger[0].total_deducted_usd and balance >= 0
    assert not store.holds


@pytest.mark.anyio
async def test_failed_or_cancelled_chat_drops_its_hold(gated):
    app, store, llm = gated
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            await c.get("/api/v1/me", headers=AUTH)
            store.wallets[USER].credit_balance_usd = Decimal("0.05")
            llm.gate.set()
            llm.fail = True
            r = await c.post("/api/v1/llm/chat", headers=AUTH, json=ELITE_HI)
            assert r.status_code == 503 and not store.holds
            # A request cancelled mid-call (client gone, server stopping) drops its hold too.
            llm.fail = False
            llm.gate.clear()
            task = asyncio.create_task(c.post("/api/v1/llm/chat", headers=AUTH, json=ELITE_HI))
            with anyio.fail_after(5):
                while not store.holds:
                    await asyncio.sleep(0.01)
            task.cancel()
            with pytest.raises(asyncio.CancelledError):
                await task
            assert not store.holds
            # Nothing was charged and nothing is still held, so the next call has the whole balance.
            llm.gate.set()
            assert (await c.post("/api/v1/llm/chat", headers=AUTH, json=ELITE_HI)).status_code == 200
    assert len(store.ledger) == 1


@pytest.mark.anyio
async def test_unpriced_models_hold_a_flat_amount(gated):
    """#5 before the price catalog syncs: each call holds $0.25, capped at the balance, instead of nothing."""
    app, store, llm = gated
    llm.models = {}
    body = {"messages": [{"role": "user", "content": "hi"}]}
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            await c.get("/api/v1/me", headers=AUTH)  # $0.50 welcome credit: room for two $0.25 holds
            rs = await _burst(c, store, llm, 5, body)
            assert sorted(r.status_code for r in rs) == [200, 200, 402, 402, 402]
            store.wallets[USER].credit_balance_usd = Decimal("0.10")  # a small balance still works
            assert (await c.post("/api/v1/llm/chat", headers=AUTH, json=body)).status_code == 200
    assert len(llm.calls) == 3 and not store.holds


@pytest.mark.anyio
async def test_memory_store_holds_expire():
    store = MemoryStore()
    await store.get_or_create_wallet(USER, None, Decimal("0.50"))
    first = await store.reserve(USER, Decimal("0.40"), 900)
    assert first and await store.reserve(USER, Decimal("0.20"), 900) is None
    # A hold whose call died mid-request stops counting once it's older than the TTL.
    assert await store.reserve(USER, Decimal("0.20"), 0) and first not in store.holds
    assert store.wallets[USER].credit_balance_usd == Decimal("0.50"), "holds never change the balance"


@pytest.mark.anyio
async def test_revenuecat_webhook_is_idempotent(env):
    app, store, *_ = env
    event = {"event": {"type": "NON_RENEWING_PURCHASE", "id": "evt1", "app_user_id": USER,
                       "product_id": "apex_credits_10", "transaction_id": "GPA.1234", "environment": "PRODUCTION"}}
    sub = {"event": {"type": "INITIAL_PURCHASE", "id": "evt2", "app_user_id": USER,
                     "product_id": "apex_pro_monthly", "transaction_id": "GPA.9",
                     "expiration_at_ms": int((time.time() + 86400 * 30) * 1000), "environment": "PRODUCTION"}}
    hook = {"Authorization": "Bearer rc-hook"}
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            assert (await c.post("/api/v1/billing/revenuecat", json=event)).status_code == 401
            r1 = await c.post("/api/v1/billing/revenuecat", json=event, headers=hook)
            r2 = await c.post("/api/v1/billing/revenuecat", json=event, headers=hook)
            await c.post("/api/v1/billing/revenuecat", json=sub, headers=hook)
            me = (await c.get("/api/v1/me", headers=AUTH)).json()
    assert r1.json()["credited"] == 10.0 and r2.json()["duplicate"] is True
    assert me["wallet"]["credit_balance_usd"] == 11.0  # $10 pack + $1 Pro monthly bonus
    assert me["wallet"]["has_active_subscription"] is True


@pytest.mark.anyio
async def test_flag_delete_and_pages(env):
    app, store, *_ = env
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            r = await c.post("/api/v1/flags", headers=AUTH, json={"artifact_kind": "cv", "reason": "inaccurate"})
            assert r.status_code == 200 and len(store.flags) == 1
            assert (await c.delete("/api/v1/users/me", headers=AUTH)).json() == {"deleted": True}
            assert USER not in store.wallets and not store.flags
            for path in ("/privacy", "/terms", "/delete-account", "/"):
                p = await c.get(path)
                assert p.status_code == 200 and "<h1>" in p.text


@pytest.mark.anyio
async def test_deleted_account_is_refused_and_purchases_stay_credited_once(env):
    """#4: after deletion the same token gets no new wallet, no welcome credit and no second copy of a purchase."""
    app, store, *_ = env
    hook = {"Authorization": "Bearer rc-hook"}
    pack = {"event": {"type": "NON_RENEWING_PURCHASE", "id": "evt-p1", "app_user_id": USER,
                      "product_id": "apex_credits_10", "transaction_id": "GPA.5555", "environment": "PRODUCTION"}}
    renewal = {"event": {"type": "RENEWAL", "id": "evt-r1", "app_user_id": USER, "product_id": "apex_pro_monthly",
                         "transaction_id": "GPA.6666", "expiration_at_ms": int((time.time() + 86400 * 30) * 1000),
                         "environment": "PRODUCTION"}}
    calls = [("GET", "/api/v1/me", None), ("POST", "/api/v1/billing/sync", None),
             ("POST", "/api/v1/llm/chat", {"messages": [{"role": "user", "content": "hi"}]}),
             ("POST", "/api/v1/flags", {"artifact_kind": "cv", "reason": "inaccurate"}),
             ("POST", "/api/v1/jobs/search", {"query": "python developer"})]
    async with app.router.lifespan_context(app):
        async with await _client(app) as c:
            assert (await c.get("/api/v1/me", headers=AUTH)).status_code == 200
            assert (await c.post("/api/v1/billing/revenuecat", json=pack, headers=hook)).json()["credited"] == 10.0
            assert (await c.delete("/api/v1/users/me", headers=AUTH)).json() == {"deleted": True}
            for method, path, body in calls:
                r = await c.request(method, path, headers=AUTH, json=body)
                assert r.status_code == 401 and r.json()["detail"] == "This account was deleted.", (path, r.text)
            # Deleting again succeeds, so a failed sign-in removal can be retried.
            assert (await c.delete("/api/v1/users/me", headers=AUTH)).json() == {"deleted": True}
            # Replayed or late webhooks neither credit the old purchase again nor re-create the account.
            assert (await c.post("/api/v1/billing/revenuecat", json=pack, headers=hook)).json()["credited"] == 0.0
            assert (await c.post("/api/v1/billing/revenuecat", json=renewal, headers=hook)).status_code == 200
    assert USER not in store.wallets
    assert {"txn:GPA.5555", "bonus:GPA.6666"} <= store.purchase_keys


@pytest.fixture
def anyio_backend():
    return "asyncio"
