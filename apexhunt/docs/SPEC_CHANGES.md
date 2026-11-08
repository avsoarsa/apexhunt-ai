# What changed from the original 6-document spec, and why

| Spec item | Built | Why |
|---|---|---|
| **Chameleon Engine Levels 2–3**: graft JD skills the user lacks into real past roles, with "plausible" metrics | **Not built.** Replaced by truthful tailoring + **Skill check-in** + on-device **Truth Guard** | The spec's own "Anti-Detection Rules" exist to keep fabricated experience past background checks. That misleads employers and freelance clients, and it exposes users to offers being rescinded or termination. The planned Play listing framing ("upskilling simulator") would also misdescribe the app, which risks account termination under Play's Deceptive Behavior policy. |
| Level 1 "Conservative" (keyword alignment, zero new skills) | **Built, as the only mode** | This is the honest core: rephrase, reorder and mirror JD vocabulary for things the user actually did. |
| Sensei "How you used it" first-person STAR stories for grafted skills | **Built for real experience only**. Gaps get a *Gap Plan*: mental model, honest answer script, related-experience bridge, 48-hour learning steps, practice project | Same study value, without coaching anyone to defend things they didn't do. A practice project gives users real experience they can then truthfully add. |
| Aggressiveness slider 1–3 | Removed | There is only one honest level. |
| "Background-Check Safe Mode" anchor locks | **Always on, by construction** | The CV document is rebuilt from profile anchors, so the model cannot change companies, titles, dates or education. |
| Scrapers: LinkedIn, Indeed, Glassdoor via Playwright Stealth + rotating residential proxies; Upwork RSS | **Official/public APIs**: Remotive, Jobicy, Remote OK, Arbeitnow, Greenhouse & Lever boards, Freelancer.com; Adzuna + Jooble via the gateway | Stealth scraping breaks those sites' terms (LinkedIn litigates), breaks often, and costs proxy money. Upwork shut down its RSS feeds in 2024. |
| FastAPI + Postgres/pgvector + Redis + Celery + LangGraph + WebSockets + Typst + R2 | **Lean gateway** (FastAPI + Supabase Postgres/Auth). The pipeline runs on-device; PDF/DOCX are generated on-device | Much less to host and maintain before revenue. CVs never touch the server, which simplifies privacy and Data Safety. |
| WebSocket telemetry | Local telemetry terminal (same UX) | The pipeline is on-device, so no socket is needed. |
| White-label OpenRouter proxy, +$1/1M markup ×1.15, ledger, wallet, $0.50 welcome credit | **Built as specified** (`gateway/app/pricing.py`, tested against the spec example) | |
| BYOK: OpenRouter, OpenAI, Anthropic, Gemini, Groq, custom URL; keys in Keystore | **Built.** Calls go device → provider directly, so the key never transits our server | Stronger than the spec's header pass-through. |
| $3.99/mo subscription + $5/$10/$25 credit packs via RevenueCat | **Built** (+ $1 monthly Pro bonus credits) | |
| Report AI output, review gate, delete account, deletion URL | **Built** | Play generative-AI and data-deletion requirements. |
| ATS-pure single-column PDF + DOCX, deterministic file names | **Built** (`dart pdf` + hand-built DOCX, no tables/columns/icons) | |
| Drift offline cache | JSON document store in app-private storage | Same offline behaviour without code generation. Swap to Drift later if data grows. |
| Assisted auto-apply WebView (P1) | Not in v1. "Apply on site" opens the listing | Ship v1 first. Auto-fill must keep the final Submit manual, as the spec says. |
| Voice mock interviewer (P2), desktop sync, agency profiles | Not in v1 | Roadmap. |
| pgvector semantic pre-filter | Deterministic on-device skill/title scoring | Free and instant. Add embeddings server-side when discovery moves to the backend. |

## Known limits / next steps

- **Keyless job APIs are called from each phone.** Past roughly 1k daily users, move them behind the gateway with caching so you respect each source's rate limits and attribution terms. Read every source's API terms before a commercial launch.
- **Freelance proposals** reference only real projects. Encourage users to fill out the Projects section of their profile.
- **Localization**: English only. Hindi and Arabic are the obvious next languages for India and the GCC.
