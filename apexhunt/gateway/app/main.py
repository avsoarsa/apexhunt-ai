"""ApexHunt AI gateway — managed AI credits, billing webhooks, job proxy, compliance pages."""

from __future__ import annotations

import asyncio
import hmac
import logging
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from decimal import Decimal
from typing import Literal, Optional

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, Field

from . import billing, jobs, pages, pricing
from .auth import CurrentUser, current_user
from .config import Settings, settings
from .llm import LLMClient, UpstreamError
from .store import AccountDeleted, LedgerEntry, MemoryStore, PostgresStore, Store

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("apexhunt")


class State:
    store: Store
    llm: LLMClient
    http: httpx.AsyncClient
    settings: Settings


state = State()


def create_app(store: Optional[Store] = None, llm: Optional[LLMClient] = None,
               cfg: Optional[Settings] = None, sync_catalog: bool = True) -> FastAPI:
    cfg = cfg or settings

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        state.settings = cfg
        state.http = httpx.AsyncClient(timeout=30, headers={"User-Agent": f"{cfg.app_name} gateway"})
        if store is not None:
            state.store = store
        elif cfg.database_url:
            state.store = await PostgresStore.connect(cfg.database_url)
        else:
            log.warning("DATABASE_URL not set — using in-memory store (data is lost on restart)")
            state.store = MemoryStore()
        state.llm = llm or LLMClient(cfg)
        task = asyncio.create_task(state.llm.catalog_loop()) if sync_catalog else None
        yield
        if task:
            task.cancel()
        await state.store.close()
        await state.http.aclose()

    app = FastAPI(title=f"{cfg.app_name} Gateway", version="1.0.0", lifespan=lifespan,
                  docs_url=None, redoc_url=None)
    _routes(app)
    return app


# --------------------------------------------------------------------------- rate limiting

_hits: dict[str, deque] = defaultdict(deque)


def _rate_limit(user_id: str) -> None:
    now = time.monotonic()
    q = _hits[user_id]
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= state.settings.rate_limit_per_minute:
        raise HTTPException(status_code=429, detail="Too many requests. Please slow down.")
    q.append(now)


# --------------------------------------------------------------------------- deleted accounts

ACCOUNT_DELETED = "This account was deleted."


async def active_user(user: CurrentUser = Depends(current_user)) -> CurrentUser:
    """Refuses tokens of deleted accounts. Supabase access tokens stay valid for up to an hour after deletion."""
    if await state.store.is_deleted(user.id):
        raise HTTPException(status_code=401, detail=ACCOUNT_DELETED)
    return user


# --------------------------------------------------------------------------- schemas


class ChatMessage(BaseModel):
    role: Literal["system", "user", "assistant"]
    content: str


class ChatRequest(BaseModel):
    model: str = "apex-pro"
    messages: list[ChatMessage] = Field(min_length=1, max_length=40)
    max_tokens: int = Field(default=3000, ge=16, le=16000)
    temperature: float = Field(default=0.4, ge=0, le=1.5)
    json_mode: bool = False
    purpose: str = Field(default="chat", max_length=40)


class JobSearchRequest(BaseModel):
    query: str = Field(min_length=2, max_length=120)
    countries: list[str] = Field(default_factory=lambda: ["US"], max_length=12)
    page: int = Field(default=1, ge=1, le=10)


class FlagRequest(BaseModel):
    artifact_kind: str = Field(max_length=40)
    reason: str = Field(max_length=200)
    notes: str = Field(default="", max_length=2000)
    excerpt: str = Field(default="", max_length=4000)


# --------------------------------------------------------------------------- routes


def _routes(app: FastAPI) -> None:
    @app.exception_handler(UpstreamError)
    async def _upstream(_: Request, exc: UpstreamError):
        return JSONResponse(status_code=exc.status, content={"detail": str(exc)})

    @app.exception_handler(AccountDeleted)
    async def _deleted(_: Request, __: AccountDeleted):
        # Raised by the store when a deletion lands mid-request.
        return JSONResponse(status_code=401, content={"detail": ACCOUNT_DELETED})

    @app.get("/", response_class=HTMLResponse)
    async def home():
        return pages.landing(state.settings)

    @app.get("/privacy", response_class=HTMLResponse)
    async def privacy():
        return pages.privacy(state.settings)

    @app.get("/terms", response_class=HTMLResponse)
    async def terms():
        return pages.terms(state.settings)

    @app.get("/delete-account", response_class=HTMLResponse)
    async def delete_page():
        return pages.delete_account(state.settings)

    @app.get("/health")
    async def health():
        return {"ok": True, "models": len(state.llm.models), "catalog_synced_at": state.llm.catalog_synced_at}

    @app.get("/api/v1/me")
    async def me(user: CurrentUser = Depends(active_user)):
        wallet = await state.store.get_or_create_wallet(user.id, user.email, state.settings.welcome_credit_usd)
        return {"user_id": user.id, "email": user.email, "wallet": wallet.to_json(),
                "require_subscription_for_managed": state.settings.require_subscription_for_managed}

    @app.get("/api/v1/llm/catalog")
    async def catalog():
        if not state.llm.models:
            await state.llm.sync_catalog()
        return state.llm.public_catalog()

    @app.post("/api/v1/llm/chat")
    async def chat(req: ChatRequest, user: CurrentUser = Depends(active_user)):
        s = state.settings
        _rate_limit(user.id)
        if not s.openrouter_api_key:
            raise HTTPException(status_code=503, detail="Managed AI is not configured on this server.")
        prompt_chars = sum(len(m.content) for m in req.messages)
        if prompt_chars > s.max_prompt_chars:
            raise HTTPException(status_code=413, detail="Input is too long. Shorten the CV or job description.")
        wallet = await state.store.get_or_create_wallet(user.id, user.email, s.welcome_credit_usd)
        if s.require_subscription_for_managed and not wallet.has_active_subscription:
            raise HTTPException(status_code=402, detail="An active Pro subscription is required.")
        if wallet.credit_balance_usd <= s.min_balance_usd:
            raise HTTPException(status_code=402, detail="Not enough AI credits. Top up to continue.")
        slug = state.llm.resolve(req.model)
        max_tokens = min(req.max_tokens, s.max_completion_tokens)
        worst_case = state.llm.estimate_max_charge(slug, prompt_chars, max_tokens)
        if worst_case > wallet.credit_balance_usd:
            raise HTTPException(status_code=402,
                                detail=f"This request may cost up to ${worst_case:.3f}. Top up or pick a cheaper engine.")

        result = await state.llm.chat(slug, [m.model_dump() for m in req.messages], max_tokens=max_tokens,
                                      temperature=req.temperature, json_mode=req.json_mode)
        markup = pricing.markup_usd(result.prompt_tokens, result.completion_tokens)
        charge = pricing.user_charge_usd(result.upstream_cost_usd, result.prompt_tokens, result.completion_tokens)
        balance = await state.store.charge(LedgerEntry(
            user_id=user.id, upstream_model_slug=result.model_slug, prompt_tokens=result.prompt_tokens,
            completion_tokens=result.completion_tokens, upstream_cost_usd=result.upstream_cost_usd,
            platform_markup_usd=markup, total_deducted_usd=charge, purpose=req.purpose))
        return {"content": result.content,
                "usage": {"prompt_tokens": result.prompt_tokens, "completion_tokens": result.completion_tokens},
                "charged_usd": float(charge), "balance_usd": float(balance)}

    @app.post("/api/v1/jobs/search")
    async def job_search(req: JobSearchRequest, user: CurrentUser = Depends(active_user)):
        _rate_limit(user.id)
        results = await jobs.search(state.http, state.settings, req.query, req.countries, req.page)
        return {"jobs": results}

    @app.post("/api/v1/billing/revenuecat")
    async def revenuecat_webhook(request: Request, authorization: Optional[str] = Header(default=None)):
        expected = state.settings.revenuecat_webhook_auth
        if not expected or not authorization or not hmac.compare_digest(authorization, expected):
            raise HTTPException(status_code=401, detail="unauthorized")
        payload = await request.json()
        return await billing.handle_event(state.store, state.settings, payload.get("event") or {})

    @app.post("/api/v1/billing/sync")
    async def billing_sync(user: CurrentUser = Depends(active_user)):
        _rate_limit(user.id)
        await state.store.get_or_create_wallet(user.id, user.email, state.settings.welcome_credit_usd)
        result = await billing.sync_from_revenuecat(state.http, state.store, state.settings, user.id)
        wallet = await state.store.get_wallet(user.id)
        return {**result, "wallet": wallet.to_json() if wallet else None}

    @app.post("/api/v1/flags")
    async def flag(req: FlagRequest, user: CurrentUser = Depends(active_user)):
        await state.store.get_or_create_wallet(user.id, user.email, state.settings.welcome_credit_usd)
        fid = await state.store.add_flag(user.id, req.artifact_kind, req.reason, req.notes, req.excerpt)
        log.info("AI output flagged: %s (%s)", fid, req.reason)
        return {"id": fid, "status": "received"}

    @app.delete("/api/v1/users/me")
    async def delete_me(user: CurrentUser = Depends(current_user)):
        # Idempotent, and open to already-deleted ids, so a failed sign-in removal below can be retried.
        await state.store.delete_user(user.id)
        s = state.settings
        if s.supabase_url and s.supabase_service_role_key:
            r = await state.http.delete(
                f"{s.supabase_url}/auth/v1/admin/users/{user.id}",
                headers={"apikey": s.supabase_service_role_key,
                         "Authorization": f"Bearer {s.supabase_service_role_key}"})
            if r.status_code not in (200, 204, 404):
                log.error("supabase auth delete failed: %s %s", r.status_code, r.text[:200])
                raise HTTPException(status_code=502, detail="Account data deleted, but sign-in removal failed. "
                                                            "Please contact support.")
        return {"deleted": True}


app = create_app()
