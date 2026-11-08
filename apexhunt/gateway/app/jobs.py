"""Keyed job-search sources proxied by the gateway so API keys never ship in the app.

Keyless sources (Remotive, Arbeitnow, Jobicy, RemoteOK, Greenhouse/Lever boards,
Freelancer.com) are queried directly from the device.
"""

from __future__ import annotations

import hashlib
import html
import re
import time
from typing import Any, Optional

import httpx

from .config import Settings

ADZUNA_COUNTRIES = {"gb", "us", "at", "au", "be", "br", "ca", "ch", "de", "es", "fr", "in", "it", "mx", "nl", "nz",
                    "pl", "sg", "za"}

COUNTRY_NAMES = {
    "US": "United States", "GB": "United Kingdom", "AE": "United Arab Emirates", "DE": "Germany", "IN": "India",
    "CA": "Canada", "AU": "Australia", "SG": "Singapore", "NL": "Netherlands", "FR": "France", "SA": "Saudi Arabia",
    "QA": "Qatar", "IE": "Ireland", "NZ": "New Zealand", "ZA": "South Africa", "ES": "Spain", "IT": "Italy",
    "PL": "Poland", "CH": "Switzerland", "AT": "Austria", "BE": "Belgium", "BR": "Brazil", "MX": "Mexico",
    "JP": "Japan", "MY": "Malaysia", "PH": "Philippines", "PK": "Pakistan", "BD": "Bangladesh", "NG": "Nigeria",
    "KE": "Kenya", "EG": "Egypt",
}

_TAG = re.compile(r"<[^>]+>")
_cache: dict[str, tuple[float, list[dict]]] = {}
CACHE_TTL = 15 * 60


def _clean(text: Optional[str]) -> str:
    return re.sub(r"\s+", " ", html.unescape(_TAG.sub(" ", text or ""))).strip()


def _job(source: str, ext_id: str, **kw: Any) -> dict:
    return {
        "id": f"{source}:{hashlib.sha1(str(ext_id).encode()).hexdigest()[:16]}",
        "source": source,
        "title": kw.get("title") or "",
        "company": kw.get("company") or "",
        "location": kw.get("location") or "",
        "country": kw.get("country") or "",
        "url": kw.get("url") or "",
        "description": kw.get("description") or "",
        "description_complete": kw.get("description_complete", False),
        "salary": kw.get("salary") or "",
        "posted_at": kw.get("posted_at") or "",
        "remote": bool(kw.get("remote")),
        "employment_type": kw.get("employment_type") or "",
        "kind": "JOB",
    }


async def search_adzuna(http: httpx.AsyncClient, s: Settings, query: str, country: str, page: int) -> list[dict]:
    cc = country.lower()
    if not (s.adzuna_app_id and s.adzuna_app_key) or cc not in ADZUNA_COUNTRIES:
        return []
    r = await http.get(
        f"https://api.adzuna.com/v1/api/jobs/{cc}/search/{max(page, 1)}",
        params={"app_id": s.adzuna_app_id, "app_key": s.adzuna_app_key, "results_per_page": 25, "what": query,
                "content-type": "application/json"}, timeout=20)
    if r.status_code != 200:
        return []
    out = []
    for j in r.json().get("results", []):
        sal = ""
        if j.get("salary_min"):
            sal = f"{int(j['salary_min']):,}" + (f" – {int(j['salary_max']):,}" if j.get("salary_max") else "")
        ctype = {"full_time": "FULL_TIME", "part_time": "PART_TIME"}.get(j.get("contract_time") or "", "")
        if j.get("contract_type") == "contract":
            ctype = "CONTRACT"
        out.append(_job("Adzuna", j.get("id"), title=_clean(j.get("title")),
                        company=(j.get("company") or {}).get("display_name", ""),
                        location=(j.get("location") or {}).get("display_name", ""), country=country.upper(),
                        url=j.get("redirect_url"), description=_clean(j.get("description")), salary=sal,
                        posted_at=j.get("created"), employment_type=ctype,
                        remote="remote" in (j.get("title", "") + j.get("description", "")).lower()))
    return out


async def search_jooble(http: httpx.AsyncClient, s: Settings, query: str, country: str, page: int) -> list[dict]:
    if not s.jooble_api_key:
        return []
    location = COUNTRY_NAMES.get(country.upper(), "") if country.upper() != "REMOTE" else ""
    r = await http.post(f"https://jooble.org/api/{s.jooble_api_key}",
                        json={"keywords": query + (" remote" if country.upper() == "REMOTE" else ""),
                              "location": location, "page": str(max(page, 1))}, timeout=20)
    if r.status_code != 200:
        return []
    out = []
    for j in r.json().get("jobs", []):
        jtype = (j.get("type") or "").lower()
        etype = "PART_TIME" if "part" in jtype else "CONTRACT" if "contract" in jtype else (
            "FULL_TIME" if "full" in jtype else "")
        out.append(_job("Jooble", j.get("id") or j.get("link"), title=_clean(j.get("title")),
                        company=j.get("company") or "", location=j.get("location") or "", country=country.upper(),
                        url=j.get("link"), description=_clean(j.get("snippet")), salary=j.get("salary") or "",
                        posted_at=j.get("updated"), employment_type=etype,
                        remote="remote" in (j.get("title", "") + j.get("location", "")).lower()))
    return out


async def search(http: httpx.AsyncClient, s: Settings, query: str, countries: list[str], page: int = 1) -> list[dict]:
    key = f"{query.lower()}|{','.join(sorted(c.upper() for c in countries))}|{page}"
    hit = _cache.get(key)
    if hit and time.time() - hit[0] < CACHE_TTL:
        return hit[1]
    results: list[dict] = []
    seen: set[str] = set()
    for country in countries[:8]:
        for fn in (search_adzuna, search_jooble):
            try:
                batch = await fn(http, s, query, country, page)
            except httpx.HTTPError:
                batch = []
            for job in batch:
                dedupe = f"{job['title'].lower()}|{job['company'].lower()}"
                if dedupe not in seen:
                    seen.add(dedupe)
                    results.append(job)
    _cache[key] = (time.time(), results)
    if len(_cache) > 500:
        _cache.pop(next(iter(_cache)))
    return results
