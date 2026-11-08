-- ApexHunt AI gateway schema (run once in the Supabase SQL editor).
-- Lives in its own schema so Supabase's auto-generated REST API never exposes it.
-- Career data (CVs, tailored documents, prep dossiers) stays on the user's device.

CREATE SCHEMA IF NOT EXISTS apexhunt;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS apexhunt.app_users (
    id            UUID PRIMARY KEY,               -- = Supabase auth.users.id
    email         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS apexhunt.user_wallets (
    user_id                  UUID PRIMARY KEY REFERENCES apexhunt.app_users(id) ON DELETE CASCADE,
    credit_balance_usd       NUMERIC(12, 6) NOT NULL DEFAULT 0,
    lifetime_spent_usd       NUMERIC(12, 6) NOT NULL DEFAULT 0,
    subscription_status      TEXT NOT NULL DEFAULT 'INACTIVE',   -- ACTIVE | GRACE_PERIOD | EXPIRED | INACTIVE
    subscription_plan_id     TEXT,
    subscription_expires_at  TIMESTAMPTZ,
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Immutable token ledger: upstream cost + $1/1M markup, x1.15 buffer.
CREATE TABLE IF NOT EXISTS apexhunt.llm_usage_ledger (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID NOT NULL REFERENCES apexhunt.app_users(id) ON DELETE CASCADE,
    execution_mode       TEXT NOT NULL DEFAULT 'MANAGED_PROXY',
    purpose              TEXT NOT NULL DEFAULT 'chat',
    upstream_model_slug  TEXT NOT NULL,
    prompt_tokens        INT NOT NULL,
    completion_tokens    INT NOT NULL,
    upstream_cost_usd    NUMERIC(12, 6) NOT NULL DEFAULT 0,
    platform_markup_usd  NUMERIC(12, 6) NOT NULL DEFAULT 0,
    total_deducted_usd   NUMERIC(12, 6) NOT NULL DEFAULT 0,
    net_profit_usd       NUMERIC(12, 6) NOT NULL DEFAULT 0,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledger_user_created ON apexhunt.llm_usage_ledger (user_id, created_at DESC);

-- Idempotency for RevenueCat webhooks / sync (store transaction ids, event ids).
CREATE TABLE IF NOT EXISTS apexhunt.purchase_events (
    idempotency_key  TEXT PRIMARY KEY,
    user_id          UUID NOT NULL REFERENCES apexhunt.app_users(id) ON DELETE CASCADE,
    product_id       TEXT,
    credit_usd       NUMERIC(12, 6) NOT NULL DEFAULT 0,
    event_type       TEXT NOT NULL,
    environment      TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Google Play generative-AI policy: in-app reporting of AI output.
CREATE TABLE IF NOT EXISTS apexhunt.ai_content_flags (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID NOT NULL REFERENCES apexhunt.app_users(id) ON DELETE CASCADE,
    artifact_kind  TEXT NOT NULL,     -- cv | proposal | prep | cover_letter
    reason         TEXT NOT NULL,
    notes          TEXT,
    excerpt        TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Defence in depth: even if someone exposes the schema, RLS denies all client access.
ALTER TABLE apexhunt.app_users        ENABLE ROW LEVEL SECURITY;
ALTER TABLE apexhunt.user_wallets     ENABLE ROW LEVEL SECURITY;
ALTER TABLE apexhunt.llm_usage_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE apexhunt.purchase_events  ENABLE ROW LEVEL SECURITY;
ALTER TABLE apexhunt.ai_content_flags ENABLE ROW LEVEL SECURITY;

-- Handy margin view for the founder dashboard.
CREATE OR REPLACE VIEW apexhunt.daily_margin AS
SELECT date_trunc('day', created_at) AS day,
       count(*)                        AS calls,
       sum(prompt_tokens + completion_tokens) AS tokens,
       sum(upstream_cost_usd)          AS upstream_cost_usd,
       sum(total_deducted_usd)         AS charged_usd,
       sum(net_profit_usd)             AS gross_margin_usd
FROM apexhunt.llm_usage_ledger
GROUP BY 1 ORDER BY 1 DESC;
