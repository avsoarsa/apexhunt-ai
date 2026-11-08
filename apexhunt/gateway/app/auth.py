"""Supabase JWT verification.

Supports both legacy HS256 project secrets and the newer asymmetric signing keys
(ES256/RS256) published at {SUPABASE_URL}/auth/v1/.well-known/jwks.json.
"""

from dataclasses import dataclass
from typing import Optional

import jwt
from fastapi import Header, HTTPException

from .config import settings

_jwks_client: Optional[jwt.PyJWKClient] = None


@dataclass
class CurrentUser:
    id: str
    email: Optional[str]


def _jwks() -> jwt.PyJWKClient:
    global _jwks_client
    if _jwks_client is None:
        if not settings.supabase_url:
            raise HTTPException(status_code=500, detail="Auth is not configured.")
        _jwks_client = jwt.PyJWKClient(f"{settings.supabase_url}/auth/v1/.well-known/jwks.json", cache_keys=True)
    return _jwks_client


def verify_token(token: str) -> CurrentUser:
    try:
        header = jwt.get_unverified_header(token)
        alg = header.get("alg", "")
        if alg == "HS256":
            if not settings.supabase_jwt_secret:
                raise HTTPException(status_code=401, detail="Unsupported token.")
            claims = jwt.decode(token, settings.supabase_jwt_secret, algorithms=["HS256"], audience="authenticated")
        else:
            key = _jwks().get_signing_key_from_jwt(token).key
            claims = jwt.decode(token, key, algorithms=["ES256", "RS256", "EdDSA"], audience="authenticated")
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired session. Please sign in again.")
    sub = claims.get("sub")
    if not sub:
        raise HTTPException(status_code=401, detail="Invalid session.")
    return CurrentUser(id=sub, email=claims.get("email"))


async def current_user(authorization: Optional[str] = Header(default=None)) -> CurrentUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Sign in required.")
    return verify_token(authorization.split(" ", 1)[1].strip())
