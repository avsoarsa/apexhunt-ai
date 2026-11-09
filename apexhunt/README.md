# ApexHunt AI

Android app (Flutter) + a lean AI gateway (FastAPI) for an AI career agent. It finds jobs and freelance gigs worldwide, tailors your **real** CV to each one, writes the cover letter or proposal, and preps you for the interview.

```
apexhunt/
├── app/                 Flutter Android app (package com.apexhunt.ai)
│   ├── lib/core/        theme, models, storage, AI clients, prompts, matching, billing
│   ├── lib/features/    onboarding, discovery (Command), pipeline, tailor, vault, dojo, settings
│   ├── test/            unit tests (Truth Guard, ATS scoring, matching, DOCX)
│   └── env/example.json build-time config template (copy to env/prod.json)
├── gateway/             FastAPI service: managed AI credits, RevenueCat webhooks, job proxy, privacy pages
│   ├── schema.sql       run in Supabase; re-run when it changes, before deploying
│   └── tests/
└── docs/                setup guide, Play Store listing, data safety, launch plan, spec changes

Repo root (one level up) also holds .github/workflows/ (cloud .aab build + gateway tests),
render.yaml (Render blueprint) and the original spec documents.
```

## How it works

```
 Phone (Flutter)                                   Cloud
 ┌──────────────────────────────┐                 ┌──────────────────────────────┐
 │ CV import (PDF/DOCX on-device)│                 │ ApexHunt gateway (FastAPI)    │
 │ Mission Control ──► job APIs ─┼─ Remotive, Jobicy, Remote OK, Arbeitnow,        │
 │                               │  Greenhouse/Lever boards, Freelancer.com        │
 │                               │──► /jobs/search ─► Adzuna + Jooble (server keys)│
 │ Tailor pipeline               │                 │                              │
 │  1 JD audit (AI)              │── Apex credits ─►│ /llm/chat ─► OpenRouter      │
 │  2 Skill check-in (you)       │                 │  +$1/1M tokens ×1.15, ledger  │
 │  3 CV tailor (AI)             │── or BYOK ──────► your own provider directly   │
 │  4 Truth Guard (on-device)    │                 │ /billing/revenuecat webhook   │
 │  5 ATS score (on-device)      │                 │ /privacy /terms /delete-account│
 │  6 Prep dossier (AI)          │                 └──────────────┬───────────────┘
 │  7 Cover letter / proposal    │                                │
 │ PDF + DOCX built on-device    │                       Supabase Postgres + Auth
 │ Vault + Dojo stored offline   │
 └──────────────────────────────┘
```

**Honest by design.** Tailoring rewrites and reorders what you actually did, in the job's vocabulary. Skills you don't have go to a learning plan, not onto your CV. The on-device Truth Guard reverts any AI-written line that adds a skill or number your profile doesn't contain. See `docs/SPEC_CHANGES.md` for why this differs from the original Chameleon spec.

## Quick start

```bash
# Gateway
cd gateway && python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt && pytest -q
cp .env.example .env   # fill in, then:
uvicorn app.main:app --reload

# App (Flutter 3.47+)
cd app && flutter pub get && flutter test
flutter run --dart-define-from-file=env/prod.json        # device/emulator
flutter build appbundle --release --dart-define-from-file=env/prod.json
```

Without `env/prod.json` the app runs in Bring-Your-Own-Key mode with purchases hidden, which works for local testing.

Full walkthrough from zero to Play Store production: **[docs/SETUP.md](docs/SETUP.md)**.
