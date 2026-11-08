# CLAUDE.md: working on ApexHunt AI

Context for Claude (Claude Code / Cowork) and human teammates. Read this before changing anything.

## What this is
ApexHunt AI is an Android app (Flutter) plus a lean FastAPI "gateway". It discovers jobs and freelance gigs, tailors the user's **real** CV to each posting, writes cover letters and proposals, and builds interview prep. Owner: Sk Arif Majid (GitHub `avsoarsa`). Package ID `com.apexhunt.ai` (permanent).

## Non-negotiable product rule: honesty
The app must never fabricate experience. It rephrases, reorders and mirrors JD vocabulary only for things the user actually did.
- Skills the user lacks go to *Learning* / *Gap Plans*, never into CV bullets or the skills list.
- `TailorEngine.applyTruthGuard` (`apexhunt/app/lib/features/tailor/tailor_engine.dart`) reverts any line that adds a JD skill or a number not present in the profile. Don't weaken it; add tests when touching it.
- Prompts live in `apexhunt/app/lib/core/ai/prompts.dart` and all share `Prompts.truthRules`.
- The original spec's "Chameleon" skill-grafting was deliberately not built. See `apexhunt/docs/SPEC_CHANGES.md`. Don't reintroduce it, and keep store copy accurate (Play Deceptive Behavior policy).

## Repo map
```
.github/workflows/      android-release.yml (signed .aab), gateway-tests.yml
render.yaml             Render blueprint → apexhunt/gateway
signing/                Play UPLOAD key, LOCAL ONLY (git-ignored; never commit; repo is public)
apexhunt/app/           Flutter app
  lib/core/             config, theme, models, storage, ai/ (llm clients, prompts), text_match (ATS/Truth Guard), billing, gateway client, app_state (Riverpod providers)
  lib/features/         profile (onboarding, CV import), discovery (job sources, mission), pipeline, tailor, vault (PDF/DOCX), dojo, settings
  test/                 core_test.dart, pipeline_test.dart (scripted-AI end-to-end + widget test)
  env/example.json      build-time config template → env/prod.json (git-ignored)
apexhunt/gateway/       FastAPI: app/{main,llm,pricing,store,billing,jobs,auth,pages}.py, schema.sql, tests/
apexhunt/docs/          SETUP, PLAY_STORE_LISTING, DATA_SAFETY, LAUNCH_PLAN, SPEC_CHANGES, QA_TEST_PLAN, store-assets/
*.md (root)             original product spec; superseded where SPEC_CHANGES says so
apexhunt/builds/        signed release .aab/.apk (bump versionCode for every Play upload)
```

## Commands
```bash
# App (Flutter 3.47.x, Dart 3.13)
cd apexhunt/app
flutter pub get
flutter analyze                       # must stay at "No issues found"
flutter test                          # 15 tests
flutter run --dart-define-from-file=env/prod.json      # or no flag = BYOK-only dev mode
flutter run --dart-define=DEMO_SEED=true               # fictional demo data (screenshots only; never ship)
flutter build appbundle --release --dart-define-from-file=env/prod.json

# Gateway (Python 3.12)
cd apexhunt/gateway
python -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt
pytest -q                             # Postgres test runs when TEST_DATABASE_URL is set (apply schema.sql first)
uvicorn app.main:app --reload         # reads env vars; see .env.example
```

## Conventions
- State: Riverpod 3 (`Notifier`/`AsyncNotifier` + `Provider`), no code generation. Navigation: go_router (5-tab `StatefulShellRoute`).
- Models: plain Dart classes with `fromJson`/`toJson` in `lib/core/models.dart`. Offline storage: `LocalStore` JSON documents.
- UI widgets never call Dio or storage directly. Go through providers in `core/app_state.dart`.
- Design tokens: `core/theme.dart` (Cyber-Executive palette; Plus Jakarta Sans, Inter, JetBrains Mono).
- Gateway money math lives only in `gateway/app/pricing.py` (`(upstream + tokens×$0.000001) × 1.15`). Tests pin the spec example.
- The provider name "OpenRouter" must never reach the managed-mode UI or gateway responses.
- Every PR: `flutter analyze` clean, `flutter test` and `pytest` green, and a new test for any engine/pricing change.
- Version bump for each Play upload: `version: 1.0.0+N` in `apexhunt/app/pubspec.yaml` (CI uses the run number).

## Who's who in commits
Everyone commits as `avsoarsa` (the owner's account). Tag every commit subject so the author is visible:
- **(A)** = Claude, e.g. `Fix PDF export on Android 10 (A)`
- **(B)** = the developer, e.g. `Add Hindi strings (B)`

Work on a branch per change, open a pull request, `git pull` before starting, and never force-push `main`.

## Secrets
- **The GitHub repo is public.** Treat every committed byte as world-readable.
- `signing/` (Play upload key + passwords) is git-ignored and lives only on the owner's machine. CI gets the key from the `UPLOAD_KEYSTORE_BASE64` and `KEY_PROPERTIES` Actions secrets.
- Never commit `env/prod.json`, `gateway/.env`, API keys or tokens. Never print secrets in logs or CI output.
- If the upload key ever leaks, request an upload-key reset in Play Console → App integrity.

## Where things stand
See `HANDOFF.md` for status, owner tasks, developer tasks and open questions.
