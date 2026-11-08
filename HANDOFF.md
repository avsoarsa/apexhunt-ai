# Team handoff: ApexHunt AI

*Last updated: Nov 8, 2026. Owner: Sk (`avsoarsa`). Built with Claude; context for Claude sessions is in `CLAUDE.md`.*

## 1. What exists today
| Area | Status |
|---|---|
| Flutter Android app (`apexhunt/app`) | ✅ Feature-complete v1: onboarding + CV import (PDF/DOCX/TXT), discovery across 7 job sources, honest tailoring with skill check-in + Truth Guard, ATS scoring, PDF/DOCX export, cover letter/proposal, Prep Dojo (STAR, questions, gap plans, TTS), BYOK + managed credits, RevenueCat paywall, report-AI-output, review gate, delete account |
| Gateway (`apexhunt/gateway`) | ✅ Code complete + tested: Supabase JWT auth, wallet + welcome credit, metered proxy (+$1/1M ×1.15), white-label catalog, Adzuna/Jooble proxy, RevenueCat webhook + sync, flags, account deletion, privacy/terms/deletion pages. **Not deployed yet.** |
| Tests | ✅ App: analyze clean, 15 tests (incl. end-to-end tailor flow + widget test). Gateway: 7 tests (incl. Postgres integration). |
| Release build | ✅ **v1.0.0 build 2** signed `.aab` + arm64 `.apk` in `apexhunt/builds/` (build 1 is superseded: placeholder legal links, do not upload). **BYOK-only** (no backend config baked in). Never run on a physical device yet. |
| Play compliance | ✅ Privacy policy, terms and account-deletion pages in `apexhunt/docs/legal/`; form-by-form answers in `apexhunt/docs/PLAY_SUBMISSION_CHECKLIST.md`; support email sk.wedmist@gmail.com |
| CI | ✅ `Android release` workflow builds a signed `.aab` once Sk adds the signing secrets (until then it builds debug-signed). `Gateway tests` runs pytest + Postgres. |
| Store assets | ✅ Listing copy, data-safety answers, icon, feature graphic, 7 screenshots (demo data) in `apexhunt/docs/` |
| Play Console | ⏳ Not started |

Key design decisions are in `CLAUDE.md` (honesty rule, architecture) and `apexhunt/docs/SPEC_CHANGES.md` (differences from the original spec).

## 2. Owner tasks (Sk: needs your accounts, payment or identity)
1. **Revoke the GitHub token that was pasted in chat** (Settings → Developer settings → Fine-grained tokens) and create a new one if needed.
2. The repo is **public** by choice. Everything is published except the signing key (`signing/`). Add Actions secrets `UPLOAD_KEYSTORE_BASE64` and `KEY_PROPERTIES` (SETUP.md §6) so CI can produce signed bundles. Give the key to the teammate privately only if he will make release builds locally.
3. Add the teammate: repo **Settings → Collaborators → Add people** → his GitHub username → he accepts the email invite.
4. Play Console: follow `apexhunt/docs/PLAY_SUBMISSION_CHECKLIST.md`. Upload **build2** `.aab` to **Internal testing** first, then **Closed testing** → invite 12–20 testers → keep them opted in for 14 days.
5. Create a free Gemini API key for Google's reviewers and paste it into *App access* (see the checklist).
6. Create accounts (cards needed for some): Supabase, OpenRouter (+$10–20 credits, spending limit), Render (Starter ~$7/mo), RevenueCat, Resend (sign-in emails); optional Adzuna + Jooble API keys. Then either do `apexhunt/docs/SETUP.md` yourself or give the teammate access to these dashboards.
7. Play Console → Users & permissions: invite the teammate if he will handle releases.

## 3. Developer tasks (teammate), suggested order
**Week 1: verify and harden**
1. Clone, run app + gateway locally (`CLAUDE.md` → Commands). Install `apexhunt/builds/ApexHunt-AI-1.0.0-build2-arm64-sideload.apk` on a real phone.
2. Run the **QA pass** in `apexhunt/docs/QA_TEST_PLAN.md`; file issues with severity.
3. Code review with fresh eyes, especially `tailor_engine.dart` (Truth Guard), `text_match.dart`, `app_state.dart`, `gateway/app/main.py`, `pricing.py`, `billing.py`.
4. Deploy the gateway with Sk (SETUP.md §1–5), fill `apexhunt/app/env/prod.json`, add the `APP_ENV_JSON` Actions secret, run the workflow → v1.0.0+2 with sign-in, credits and purchases → upload to the same closed-testing track.

**Week 2+: backlog (pick with Sk)**
- Move keyless job sources behind the gateway with caching (rate limits / ToS at scale)
- Crash reporting (Sentry/Crashlytics; update Data Safety if added)
- Assisted-apply WebView (spec P1; final Submit must stay manual)
- Referral credits, annual plan, Hindi/Arabic localization
- Server-side missions + push notifications for 90%+ matches
- iOS build (Flutter codebase is ready; needs Apple account + StoreKit setup)

## 4. Questions for the teammate
1. After the QA pass: what are the top 5 issues blocking a production launch?
2. Is the on-device pipeline (vs a server agent) right for v1, or do you see reliability or cost problems?
3. Which backlog items would you do first, and your effort estimates?
4. Anything in the stack (Riverpod 3, go_router, JSON storage, pdfrx, RevenueCat, Supabase) you'd change before we have users?

## 5. Working with Claude
- **Claude Code** (CLI/IDE) in this repo reads `CLAUDE.md` automatically. Ask it to fix issues, write tests, or review PRs.
- **Claude project "AI agent for Job search"** (Sk's claude.ai): has this context. Sk can share it if you're in the same organization.
- Workflow: branch per change → PR (template asks for tests + honesty check) → review → merge to `main`. Tag `v*` to trigger a release build.
- **Commit tags:** end every commit subject with **(A)** for Claude or **(B)** for the developer. Both commit as `avsoarsa`, so the tag is how we tell authors apart.

## 6. Release checklist (each Play upload)
1. Bump `version: 1.0.0+N` (or let CI use the run number).
2. CI green → download the `.aab` artifact → Play Console → testing track → release notes.
3. Before production: gateway `ALLOW_SANDBOX_PURCHASES=false`; retake screenshots on a device with the managed build.
