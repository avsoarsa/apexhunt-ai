# QA pass and code review: developer B (8 Nov 2026)

Reviewed at `035a2fd` (build 2). Every finding is a GitHub issue with a severity label (#4–#20). This page answers the questions in `HANDOFF.md` §4.

## What was tested, and how

| Area | How | Result |
|---|---|---|
| Spec vs build | Read the 8 spec docs, 6 PDFs and `SPEC_CHANGES.md` | Agree with every deviation. Not building the Chameleon grafting and its "anti-detection rules" was the right call. |
| Gateway | Python 3.12 venv; pytest without a DB and with Postgres 16 + `schema.sql`; probes against the real app code | 7/7 tests pass once #1 lands. Plain `pytest -q` fails today, which is why `main`'s CI is red. Found #4 and #5 by running the code. |
| App analyzer + tests | My workspace can't download Flutter or pub packages, so these ran in CI via the new App checks workflow (#2) | `flutter analyze` clean, 15/15 tests pass. HANDOFF's claim holds. |
| Truth Guard | Failing Dart tests in draft PR #3, run in CI (15 pass, 7 new fail); line-by-line port for extra probes | Bypasses #9, #10 and #11, plus the design gaps in #12 |
| Discovery | Port of `matchesCountries`; Remotive's published API terms | #13, #14 |
| Release builds | APK/AAB manifest, signing and contents inspected with androguard; SHA256SUMS checked | OK: package/version as documented, v2 signature with the upload cert, `allowBackup=false`, no secrets inside, 64-bit libs. The sideload APK is arm64-only, so 32-bit budget phones need Play internal testing. |
| Secrets | Pattern scan of the full git history | Clean |
| **Not done** | Real-device QA, live job APIs, live Gemini/OpenRouter calls (no phone; my workspace blocks those hosts) | See "Device QA still to do" below |

## Findings

**Before more testers use build 2 (BYOK):**

| Issue | Severity | What |
|---|---|---|
| #9 | major | Truth Guard: invented numbers pass when their digits appear in dates or phone numbers; headline not checked |
| #10 | major | Truth Guard: "go live" / "C-level" / "R&D" count as Go / C / R; AI-written aliases count as evidence |
| #11 | major | Truth Guard: revert restores the AI's "original", not the user's bullet |
| #8 | major | "Nothing is used for AI training" is false for free Gemini keys (the path we recommend) |
| #13 | major | Country filter: Indiana→India, California→Canada, "in US time zones"→India, Ukraine→UK |
| #14 | major | Every phone calls Remotive above its 2/min block limit; sources' terms need the gateway cache |
| #12 | major (design) | Guard can't see non-JD tools, skills moved between roles, parse mistakes, cover letters |
| #15–#18 | minor/polish | Ollama without a key; wipe leaves CV files in cache; letter failure discards a paid run; non-Latin names |

**Before turning on Apex credits (managed build):**

| Issue | Severity | What |
|---|---|---|
| #4 | **blocker** | Delete account → `/me` → `/billing/sync` re-grants $0.50 and re-credits every past pack, repeatedly |
| #5 | major | 10 concurrent requests on a $0.50 wallet → balance −$2.97 |
| #6 | major | Refunded credit packs keep their credits |
| #7 | major | Managed calls don't set OpenRouter `data_collection: "deny"` |
| #20 | minor | Sandbox purchases fail open, open AI relay, catalog retry, slow job search |
| #19 | minor | Release binaries in git (~240 MB already); no branch protection on `main` |

## Answers to HANDOFF §4

### 1. Top 5 launch blockers
1. **#4, the credits loop.** One purchase can be turned into unlimited managed credit, paid for by the master key. Blocks any managed build.
2. **The Truth Guard isn't yet the guarantee we market (#9, #10, #11).** The listing says "Truth Guard double-checks every line so nothing you didn't do sneaks in". Today invented "10+ years", "team of 8", "Go" and "AWS Lambda" claims get through. Honesty is the product and also our defence under Play's Deceptive Behavior policy, so I'd fix these before widening the test.
3. **Privacy statements that don't match the data flow (#7, #8).** Onboarding and both privacy pages promise no AI training, but free Gemini keys and default OpenRouter routing allow it. Play's User Data policy and the Data Safety form need these to match.
4. **Discovery quality and source terms (#13, #14).** India is the first market, and India searches currently fill with US-only jobs. Remotive blocks callers above 2 requests a minute, and every phone sends the same User-Agent, so a block by user agent would hit every user at once.
5. **Wallet safety (#5, #6) plus device QA.** Overspend and refunds must be closed before credits go live. Separately, the device half of the QA plan hasn't been run by anyone yet (the list below).

### 2. On-device pipeline vs a server agent
On-device is right for v1: no queue or workers to run, CVs never stored server-side, BYOK keys never leave the phone, and the deterministic Truth Guard works the same for both modes. I'd change three things:
- **Discovery belongs on the server now (#14).** It's the part where on-device is wrong: rate limits, terms, battery, and one shared User-Agent. A scheduled fetch plus cache on the gateway is cheaper than per-phone calls, and later enables server missions and push.
- **Managed mode should call tasks, not raw prompts (#20).** Today the gateway relays any prompt to the master key, and every prompt fix needs a Play release. A `/api/v1/ai/run {task, inputs}` endpoint with server-side templates keeps CVs in memory only (the same as today in managed mode), lets us fix prompts without a release, and limits abuse. BYOK stays fully on-device.
- **Reliability on phones.** A tailor is 4 AI calls with no retry or resume; one failed call loses the run (#17), and a 1–3 minute run can be killed if the user switches apps. Add retry with backoff for transient errors, save intermediate results (analysis → CV → prep) so a failed step resumes, and keep the screen awake during a run.

Cost isn't the issue: about $0.017 per application leaves a healthy margin. Abuse (#4, #5, welcome-credit farming) is the cost risk.

### 3. What I'd do first (rough effort for one developer with Claude)
| Order | Item | Effort |
|---|---|---|
| 1 | Truth Guard fixes #9–#11 (tests already in #3), then #12 | 2–3 days |
| 2 | Billing safety #4, #5, #6, #7, and sandbox default from #20 | 1–2 days |
| 3 | Privacy copy #8 + Data Safety/privacy updates | 0.5 day |
| 4 | Backlog: keyless sources behind the gateway with caching (#14), plus the country filter (#13) | 3–4 days |
| 5 | Backlog: crash reporting. Sentry with PII scrubbing so CV text never reaches breadcrumbs, then update Data Safety | 0.5–1 day |
| 6 | Builds out of git, branch protection (#19) | 0.5 day |
| 7 | Backlog: referral credits + annual plan, only after #4/#5 (referrals amplify farming) | 1–2 days |
| 8 | Backlog: Hindi/Arabic. String extraction, RTL checks, PDF font fallbacks (#18) | 3–5 days |
| 9 | Backlog: server missions + push (needs item 4 first) | 1–2 weeks |
| 10 | Backlog: assisted-apply WebView. ATS selectors break often; Submit stays manual | 1–2 weeks |
| 11 | Backlog: iOS (StoreKit/RevenueCat, review, device testing) | 1–2 weeks + Apple account |

### 4. Stack changes before users
- **Keep:** Riverpod 3, go_router, pdfrx, RevenueCat, Supabase, FastAPI + asyncpg. None of them is the bottleneck.
- **JSON storage: keep, but split `artifacts.json`.** Every tailored application (full CV + prep JSON) lives in one file that's rewritten on every change, so writes grow with history. Store one file per artifact plus a small index now (small change). Move to Drift when you need search or more than a few hundred items.
- **Sign-in:** email OTP alone makes welcome-credit farming cheap. Add Google Sign-In (supported by Supabase, one tap on Android) and verify Play Integrity on managed AI calls before credits go live.
- **Add:** Sentry for crashes, branch protection, and builds as GitHub Release assets.

## Device QA still to do (needs a phone)
In order. Items marked ⚠ are where I expect failures based on the code.
1. Install build 2, onboarding with a Gemini key; a wrong key and a key with spaces (§1).
2. CV import: text PDF, 2-column PDF, DOCX with the name/contact in the **header** ⚠ (header XML isn't read), scanned PDF, a 10-page CV ⚠ (the AI parse only sees the first 30,000 characters).
3. Truth Guard adversarial run (§4) with a real CV that has dates and a phone number ⚠ #9/#10.
4. Countries IN and DE (§3) ⚠ #13; a 4-keyword mission ⚠ Remotive "unavailable" (#14).
5. Custom Ollama URL without a key (§1) ⚠ #15.
6. Share PDF/DOCX → wipe data → check the cache folder ⚠ #16.
7. ATS parse check of 5 exported PDFs/DOCX (§5), a TalkBack pass (§9) and a large-font pass.
8. Budget 32-bit phone: needs Play internal testing, because the sideload APK is arm64-only.

## Open pull requests
- #1: plain `pytest` works (fixes `main`'s red Gateway tests). Ready to merge.
- #2: App checks workflow (analyze + test on PRs). Ready to merge; consider making it a required check.
- #3: draft, failing Truth Guard tests. Merge with the fixes.
