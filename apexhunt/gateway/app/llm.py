"""Upstream LLM client (OpenRouter) and the white-labelled model catalog.

The provider name never leaves this module: catalog entries, errors and responses
sent to the app use ApexHunt tier names and vendor model labels only.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Optional

import httpx

from . import pricing
from .config import Settings

log = logging.getLogger("apexhunt.llm")

TIERS = {
    "apex-flash": ("Apex Flash", "Fast and economical. Great for bulk job scoring and first drafts."),
    "apex-pro": ("Apex Pro", "Balanced quality and cost. Recommended for tailored CVs and proposals."),
    "apex-elite": ("Apex Elite", "Highest writing quality for senior roles and high-value bids."),
}


class UpstreamError(Exception):
    def __init__(self, message: str, status: int = 502):
        super().__init__(message)
        self.status = status


@dataclass
class ModelInfo:
    slug: str
    label: str
    prompt_rate: Decimal  # USD per token
    completion_rate: Decimal
    context_length: int
    supports_json: bool


@dataclass
class ChatResult:
    content: str
    model_slug: str
    prompt_tokens: int
    completion_tokens: int
    upstream_cost_usd: Decimal


def _label(slug: str, name: Optional[str]) -> str:
    if name:
        # Upstream names look like "Anthropic: Claude Sonnet 5.5" — keep the model part.
        return name.split(": ", 1)[-1]
    return slug.split("/", 1)[-1].replace("-", " ").title()


class LLMClient:
    def __init__(self, settings: Settings, http: Optional[httpx.AsyncClient] = None):
        self.s = settings
        self.http = http or httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=10.0))
        self.models: dict[str, ModelInfo] = {}
        self.catalog_synced_at: float = 0.0
        self._lock = asyncio.Lock()

    # ------------------------------------------------------------------ catalog

    async def sync_catalog(self) -> None:
        async with self._lock:
            try:
                r = await self.http.get(f"{self.s.openrouter_base_url}/models", timeout=30)
                r.raise_for_status()
                data = r.json().get("data", [])
            except Exception as exc:  # keep the previous catalog on failure
                log.warning("catalog sync failed: %s", exc)
                return
            models: dict[str, ModelInfo] = {}
            for m in data:
                p = m.get("pricing") or {}
                try:
                    pr, cr = Decimal(str(p.get("prompt", "0"))), Decimal(str(p.get("completion", "0")))
                except Exception:
                    continue
                if pr < 0 or cr < 0:
                    continue  # routers with dynamic pricing
                models[m["id"]] = ModelInfo(
                    slug=m["id"], label=_label(m["id"], m.get("name")), prompt_rate=pr, completion_rate=cr,
                    context_length=int(m.get("context_length") or 0),
                    supports_json="response_format" in (m.get("supported_parameters") or []),
                )
            if models:
                self.models = models
                self.catalog_synced_at = time.time()
                log.info("catalog synced: %d models", len(models))

    async def catalog_loop(self, every_seconds: int = 6 * 3600) -> None:
        while True:
            await self.sync_catalog()
            await asyncio.sleep(every_seconds)

    def tier_slug(self, tier: str) -> Optional[str]:
        candidates = {"apex-flash": self.s.tier_flash, "apex-pro": self.s.tier_pro,
                      "apex-elite": self.s.tier_elite}.get(tier, [])
        for slug in candidates:
            if not self.models or slug in self.models:
                return slug
        return None

    def allowed_slugs(self) -> set[str]:
        allowed = {s for s in self.s.curated_models if not self.models or s in self.models}
        for t in TIERS:
            slug = self.tier_slug(t)
            if slug:
                allowed.add(slug)
        return allowed

    def resolve(self, model: str) -> str:
        if model in TIERS:
            slug = self.tier_slug(model)
            if not slug:
                raise UpstreamError("This AI engine is temporarily unavailable.", 503)
            return slug
        if model in self.allowed_slugs():
            return model
        raise UpstreamError("Unknown AI engine.", 400)

    def _entry(self, slug: str, extra: dict) -> dict:
        info = self.models.get(slug)
        entry = {"id": slug, "label": info.label if info else _label(slug, None), **extra}
        if info:
            entry.update({
                "input_per_1m_usd": float(pricing.display_rate_per_million(info.prompt_rate)),
                "output_per_1m_usd": float(pricing.display_rate_per_million(info.completion_rate)),
                "est_cost_per_application_usd": float(pricing.estimate_application_cost(info.prompt_rate,
                                                                                         info.completion_rate)),
                "context_length": info.context_length,
            })
        return entry

    def public_catalog(self) -> dict:
        tiers = []
        for tid, (name, desc) in TIERS.items():
            slug = self.tier_slug(tid)
            if slug:
                e = self._entry(slug, {"name": name, "description": desc})
                e["model_label"] = e.pop("label")
                e["id"] = tid
                tiers.append(e)
        models = [self._entry(s, {}) for s in sorted(self.allowed_slugs())]
        return {"tiers": tiers, "models": models, "markup_note": "Prices include platform fee.",
                "synced_at": self.catalog_synced_at}

    # ------------------------------------------------------------------ chat

    def estimate_max_charge(self, slug: str, prompt_chars: int, max_tokens: int) -> Decimal:
        info = self.models.get(slug)
        est_prompt_tokens = prompt_chars // 3 + 50
        if not info:
            return Decimal("0")
        upstream = pricing.upstream_cost_from_rates(info.prompt_rate, info.completion_rate, est_prompt_tokens,
                                                    max_tokens)
        return pricing.user_charge_usd(upstream, est_prompt_tokens, max_tokens)

    async def chat(self, slug: str, messages: list[dict[str, Any]], *, max_tokens: int, temperature: float,
                   json_mode: bool) -> ChatResult:
        body: dict[str, Any] = {
            "model": slug,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "usage": {"include": True},
        }
        info = self.models.get(slug)
        if json_mode and (info is None or info.supports_json):
            body["response_format"] = {"type": "json_object"}
        headers = {
            "Authorization": f"Bearer {self.s.openrouter_api_key}",
            "HTTP-Referer": self.s.public_base_url,
            "X-Title": self.s.app_name,
        }
        try:
            r = await self.http.post(f"{self.s.openrouter_base_url}/chat/completions", json=body, headers=headers)
        except httpx.HTTPError as exc:
            log.warning("upstream transport error: %s", exc)
            raise UpstreamError("The AI engine did not respond. Please try again.")
        if r.status_code >= 400:
            log.warning("upstream error %s: %s", r.status_code, r.text[:500])
            if r.status_code == 429:
                raise UpstreamError("The AI engine is busy. Please retry in a moment.", 503)
            raise UpstreamError("The AI engine returned an error. Please try again.")
        data = r.json()
        if "error" in data:
            log.warning("upstream error payload: %s", str(data["error"])[:500])
            raise UpstreamError("The AI engine returned an error. Please try again.")
        choice = (data.get("choices") or [{}])[0]
        content = (choice.get("message") or {}).get("content") or ""
        usage = data.get("usage") or {}
        pt, ct = int(usage.get("prompt_tokens") or 0), int(usage.get("completion_tokens") or 0)
        if usage.get("cost") is not None:
            cost = Decimal(str(usage["cost"]))
        elif info:
            cost = pricing.upstream_cost_from_rates(info.prompt_rate, info.completion_rate, pt, ct)
        else:
            cost = Decimal("0")
        return ChatResult(content=content, model_slug=data.get("model") or slug, prompt_tokens=pt,
                          completion_tokens=ct, upstream_cost_usd=cost)
