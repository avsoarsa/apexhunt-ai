"""RevenueCat → wallet bridge.

The app calls `Purchases.logIn(<supabase user id>)`, so RevenueCat's app_user_id is
our user id. Subscriptions toggle `subscription_status`; consumable credit packs
add to `credit_balance_usd`. Every event is idempotent on the store transaction id.
"""

from __future__ import annotations

import logging
import re
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional

import httpx

from .config import Settings
from .store import Store

log = logging.getLogger("apexhunt.billing")

_UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.I)

ACTIVATE = {"INITIAL_PURCHASE", "RENEWAL", "PRODUCT_CHANGE", "UNCANCELLATION", "SUBSCRIPTION_EXTENDED"}


def _ms(value) -> Optional[datetime]:
    if not value:
        return None
    return datetime.fromtimestamp(int(value) / 1000, tz=timezone.utc)


def resolve_user_id(event: dict) -> Optional[str]:
    candidates = [event.get("app_user_id"), event.get("original_app_user_id"), *(event.get("aliases") or [])]
    for c in candidates:
        if c and _UUID.match(str(c)):
            return str(uuid.UUID(str(c)))
    return None


async def handle_event(store: Store, s: Settings, event: dict) -> dict:
    etype = event.get("type", "")
    env = event.get("environment", "PRODUCTION")
    if etype == "TEST":
        return {"status": "ok", "note": "test event"}
    if env == "SANDBOX" and not s.allow_sandbox_purchases:
        return {"status": "ignored", "note": "sandbox"}
    user_id = resolve_user_id(event)
    if not user_id:
        log.warning("event %s without app user id", event.get("id"))
        return {"status": "ignored", "note": "no user"}

    product = event.get("product_id") or ""
    txn = event.get("transaction_id") or event.get("id")
    key = f"txn:{txn}:{etype}"

    if etype == "NON_RENEWING_PURCHASE":
        credit = s.credit_packs.get(product)
        if credit is None:
            return {"status": "ignored", "note": f"unknown product {product}"}
        applied = await store.credit_purchase(f"txn:{txn}", user_id, product, credit, etype, env)
        return {"status": "ok", "credited": float(credit) if applied else 0.0, "duplicate": not applied}

    if etype in ACTIVATE:
        applied = await store.set_subscription(user_id, "ACTIVE", product, _ms(event.get("expiration_at_ms")),
                                               idempotency_key=key, event_type=etype, environment=env)
        if etype in ("INITIAL_PURCHASE", "RENEWAL") and s.pro_monthly_bonus_usd > 0:
            # Monthly Pro bonus credits, once per billing transaction.
            await store.credit_purchase(f"bonus:{txn}", user_id, product, s.pro_monthly_bonus_usd, "PRO_BONUS", env)
    elif etype == "BILLING_ISSUE":
        applied = await store.set_subscription(user_id, "GRACE_PERIOD", product,
                                               _ms(event.get("grace_period_expiration_at_ms") or
                                                   event.get("expiration_at_ms")),
                                               idempotency_key=key, event_type=etype, environment=env)
    elif etype in ("EXPIRATION", "SUBSCRIPTION_PAUSED"):
        applied = await store.set_subscription(user_id, "EXPIRED", product, _ms(event.get("expiration_at_ms")),
                                               idempotency_key=key, event_type=etype, environment=env)
    else:
        # CANCELLATION keeps access until EXPIRATION; TRANSFER etc. are handled by the next sync.
        return {"status": "ok", "note": f"no-op for {etype}"}
    return {"status": "ok", "duplicate": not applied}


async def sync_from_revenuecat(http: httpx.AsyncClient, store: Store, s: Settings, user_id: str) -> dict:
    """Pull the subscriber record right after a purchase so the app doesn't wait for the webhook."""
    if not s.revenuecat_secret_key:
        return {"synced": False}
    r = await http.get(f"https://api.revenuecat.com/v1/subscribers/{user_id}",
                       headers={"Authorization": f"Bearer {s.revenuecat_secret_key}"}, timeout=20)
    if r.status_code != 200:
        return {"synced": False}
    sub = r.json().get("subscriber", {})
    ent = (sub.get("entitlements") or {}).get(s.revenuecat_entitlement)
    if ent:
        expires = ent.get("expires_date")
        exp_dt = datetime.fromisoformat(expires.replace("Z", "+00:00")) if expires else None
        active = exp_dt is None or exp_dt > datetime.now(timezone.utc)
        await store.set_subscription(user_id, "ACTIVE" if active else "EXPIRED", ent.get("product_identifier"),
                                     exp_dt)
    credited = Decimal("0")
    for product, purchases in (sub.get("non_subscriptions") or {}).items():
        credit = s.credit_packs.get(product)
        if credit is None:
            continue
        for p in purchases:
            if p.get("is_sandbox") and not s.allow_sandbox_purchases:
                continue
            txn = p.get("store_transaction_id") or p.get("id")
            if await store.credit_purchase(f"txn:{txn}", user_id, product, credit, "SYNC",
                                           "SANDBOX" if p.get("is_sandbox") else "PRODUCTION"):
                credited += credit
    return {"synced": True, "credited": float(credited)}
