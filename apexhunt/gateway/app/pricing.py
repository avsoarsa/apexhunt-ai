"""Token pricing for the managed AI gateway.

Charge formula (from the ApexHunt spec):

    user_charge = (upstream_cost + total_tokens * $0.000001) * 1.15

The +$1.00 per 1M tokens markup is the platform margin; the 1.15 buffer absorbs
Google Play's 15% service fee on credit-pack purchases.
"""

from decimal import ROUND_HALF_UP, Decimal

MARKUP_PER_TOKEN = Decimal("0.000001")  # +$1.00 per 1,000,000 tokens
GATEWAY_BUFFER = Decimal("1.15")
SIX_DP = Decimal("0.000001")


def _d(value) -> Decimal:
    return value if isinstance(value, Decimal) else Decimal(str(value))


def markup_usd(prompt_tokens: int, completion_tokens: int) -> Decimal:
    return (Decimal(int(prompt_tokens) + int(completion_tokens)) * MARKUP_PER_TOKEN).quantize(SIX_DP, ROUND_HALF_UP)


def user_charge_usd(upstream_cost_usd, prompt_tokens: int, completion_tokens: int) -> Decimal:
    upstream = _d(upstream_cost_usd)
    raw = (upstream + Decimal(int(prompt_tokens) + int(completion_tokens)) * MARKUP_PER_TOKEN) * GATEWAY_BUFFER
    return raw.quantize(SIX_DP, ROUND_HALF_UP)


def upstream_cost_from_rates(prompt_rate_per_token, completion_rate_per_token, prompt_tokens: int, completion_tokens: int) -> Decimal:
    """Fallback when the upstream response does not report cost."""
    return (_d(prompt_rate_per_token) * prompt_tokens + _d(completion_rate_per_token) * completion_tokens).quantize(
        SIX_DP, ROUND_HALF_UP
    )


def display_rate_per_million(upstream_rate_per_token) -> Decimal:
    """Rate shown to users: (upstream per 1M + $1) * 1.15."""
    per_million = _d(upstream_rate_per_token) * Decimal(1_000_000)
    return ((per_million + Decimal(1)) * GATEWAY_BUFFER).quantize(Decimal("0.0001"), ROUND_HALF_UP)


def estimate_application_cost(prompt_rate_per_token, completion_rate_per_token, prompt_tokens: int = 8000, completion_tokens: int = 4000) -> Decimal:
    """Typical tailored application ≈ 12k tokens (8k in / 4k out)."""
    upstream = upstream_cost_from_rates(prompt_rate_per_token, completion_rate_per_token, prompt_tokens, completion_tokens)
    return user_charge_usd(upstream, prompt_tokens, completion_tokens).quantize(Decimal("0.0001"), ROUND_HALF_UP)
