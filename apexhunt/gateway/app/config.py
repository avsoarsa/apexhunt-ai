import os
from dataclasses import dataclass, field
from decimal import Decimal


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _list(name: str, default: str) -> list[str]:
    return [x.strip() for x in _env(name, default).split(",") if x.strip()]


def _packs(raw: str) -> dict[str, Decimal]:
    packs: dict[str, Decimal] = {}
    for item in raw.split(","):
        if ":" in item:
            pid, usd = item.split(":", 1)
            packs[pid.strip()] = Decimal(usd.strip())
    return packs


@dataclass
class Settings:
    app_name: str = field(default_factory=lambda: _env("APP_NAME", "ApexHunt AI"))
    public_base_url: str = field(default_factory=lambda: _env("PUBLIC_BASE_URL", "http://localhost:8000"))
    support_email: str = field(default_factory=lambda: _env("SUPPORT_EMAIL", "support@example.com"))
    company_name: str = field(default_factory=lambda: _env("COMPANY_NAME", "ApexHunt AI"))

    database_url: str = field(default_factory=lambda: _env("DATABASE_URL"))

    supabase_url: str = field(default_factory=lambda: _env("SUPABASE_URL").rstrip("/"))
    supabase_jwt_secret: str = field(default_factory=lambda: _env("SUPABASE_JWT_SECRET"))
    supabase_service_role_key: str = field(default_factory=lambda: _env("SUPABASE_SERVICE_ROLE_KEY"))

    openrouter_api_key: str = field(default_factory=lambda: _env("OPENROUTER_API_KEY"))
    openrouter_base_url: str = field(default_factory=lambda: _env("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1"))

    # White-label tiers: first slug that exists in the live catalog wins.
    tier_flash: list[str] = field(default_factory=lambda: _list(
        "TIER_FLASH_MODELS", "deepseek/deepseek-v4-flash,deepseek/deepseek-v3.2,google/gemini-2.5-flash-lite"))
    tier_pro: list[str] = field(default_factory=lambda: _list(
        "TIER_PRO_MODELS", "anthropic/claude-haiku-5.5,openai/gpt-6-luna,google/gemini-3.1-flash-lite,deepseek/deepseek-v3.2"))
    tier_elite: list[str] = field(default_factory=lambda: _list(
        "TIER_ELITE_MODELS", "anthropic/claude-sonnet-5.5,anthropic/claude-sonnet-4.5,google/gemini-3.1-pro-preview"))
    curated_models: list[str] = field(default_factory=lambda: _list(
        "CURATED_MODELS",
        "deepseek/deepseek-v4-flash,deepseek/deepseek-v3.2,anthropic/claude-haiku-5.5,openai/gpt-6-luna,"
        "google/gemini-3.1-flash-lite,qwen/qwen3-235b-a22b-2507,meta-llama/llama-4-maverick,"
        "anthropic/claude-sonnet-5.5,google/gemini-3.1-pro-preview,openai/gpt-6.1-terra",
    ))

    welcome_credit_usd: Decimal = field(default_factory=lambda: Decimal(_env("WELCOME_CREDIT_USD", "0.50")))
    min_balance_usd: Decimal = field(default_factory=lambda: Decimal(_env("MIN_BALANCE_USD", "0.02")))
    # Managed AI calls hold their worst-case cost while they run (#5). When the price is unknown (model catalog
    # not synced yet) they hold this much instead, capped at the balance.
    unpriced_hold_usd: Decimal = field(default_factory=lambda: Decimal(_env("UNPRICED_HOLD_USD", "0.25")))
    # A hold whose call never finished (server killed mid-call) stops counting after this long.
    credit_hold_ttl_seconds: int = field(default_factory=lambda: int(_env("CREDIT_HOLD_TTL_SECONDS", "900")))
    max_completion_tokens: int = field(default_factory=lambda: int(_env("MAX_COMPLETION_TOKENS", "6000")))
    max_prompt_chars: int = field(default_factory=lambda: int(_env("MAX_PROMPT_CHARS", "120000")))
    require_subscription_for_managed: bool = field(
        default_factory=lambda: _env("REQUIRE_SUBSCRIPTION_FOR_MANAGED", "false").lower() == "true")
    rate_limit_per_minute: int = field(default_factory=lambda: int(_env("RATE_LIMIT_PER_MINUTE", "30")))

    revenuecat_webhook_auth: str = field(default_factory=lambda: _env("REVENUECAT_WEBHOOK_AUTH"))
    revenuecat_secret_key: str = field(default_factory=lambda: _env("REVENUECAT_SECRET_KEY"))
    revenuecat_entitlement: str = field(default_factory=lambda: _env("REVENUECAT_ENTITLEMENT", "pro"))
    credit_packs: dict[str, Decimal] = field(default_factory=lambda: _packs(
        _env("CREDIT_PACKS", "apex_credits_5:5,apex_credits_10:10,apex_credits_25:25")))
    pro_monthly_bonus_usd: Decimal = field(default_factory=lambda: Decimal(_env("PRO_MONTHLY_BONUS_USD", "1.00")))
    allow_sandbox_purchases: bool = field(
        default_factory=lambda: _env("ALLOW_SANDBOX_PURCHASES", "true").lower() == "true")

    adzuna_app_id: str = field(default_factory=lambda: _env("ADZUNA_APP_ID"))
    adzuna_app_key: str = field(default_factory=lambda: _env("ADZUNA_APP_KEY"))
    jooble_api_key: str = field(default_factory=lambda: _env("JOOBLE_API_KEY"))


settings = Settings()
