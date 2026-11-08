# Engineering Execution, QA & Launch Tracker: ApexHunt AI

Use this master checklist to track engineering progress across Backend, AI Agents, Flutter Mobile, Billing, QA, and Google Play Store compliance from Day 1 to launch.

---

## 1. Sprint 1 (Weeks 1–2): Infrastructure, Auth & White-Label LLM Gateway
- [ ] **DB-01:** Provision PostgreSQL 16 instance with `pgcrypto` and `vector` (`pgvector`) extensions enabled.
- [ ] **DB-02:** Execute all 8 DDL tables (`users`, `user_wallets`, `llm_usage_ledger`, `search_missions`, `opportunities`, `tailored_artifacts`, `prep_dossiers`, `ai_content_flags`) and vector indexes.
- [ ] **BE-01:** Scaffold Python FastAPI backend + Redis + Celery worker queue.
- [ ] **BE-02:** Implement JWT authentication and automatic `$0.500000` welcome wallet provisioning on signup.
- [ ] **BE-03:** Build Celery Beat task to sync `https://openrouter.ai/api/v1/models` every 6 hours, strip OpenRouter branding, map `apex-flash`, `apex-pro`, and `apex-elite`, and apply `+$1.00/1M` token markup.
- [ ] **BE-04:** Implement `execute_llm_step()` token-metering middleware supporting both Track A (`MANAGED_PROXY` with `+$0.000001/token` markup * `1.15` gateway buffer) and Track B (`BYOK` pass-through via `X-BYOK-Key` & `X-BYOK-Base-URL`).
- [ ] **FL-01:** Initialize Flutter 3.x Clean Architecture project (`core`, `features`, `main.dart`) with Material 3 "Cyber-Executive" theme tokens.
- [ ] **FL-02:** Implement `SecureKeyVault` (`flutter_secure_storage`) with Android Keystore `AES-256-GCM` encryption for BYOK API keys.
- [ ] **FL-03:** Build the **AI Brain & Billing Modal Sheet** (Managed Apex Wallet tab + BYOK Provider/Key configuration tab with connection test ping).

---

## 2. Sprint 2 (Weeks 3–4): Master CV Parser, Chameleon Agent & Typst PDF Engine
- [ ] **BE-05:** Build `POST /api/v1/profile/parse-cv` to extract text from PDF/DOCX, construct `master_knowledge_graph` JSONB, and compute `vector(1536)` embedding.
- [ ] **AI-01:** Implement LangGraph **Node 1 (JD Auditor & Gap Extractor)** separating `Matched_Skills` from `Missing_Delta_Skills`.
- [ ] **AI-02:** Implement LangGraph **Node 2 (Chameleon CV Synthesizer)** enforcing locked company/date anchors (`background_check_safe_mode`), release-year chronological sanity, Ecosystem Pairing, and the XYZ Impact Formula across Aggressiveness Levels 1, 2, and 3.
- [ ] **AI-03:** Implement LangGraph **Node 3 (ATS Gatekeeper & Critic)** with conditional loop-back edge to Node 2 if ATS score `< 94%`.
- [ ] **AI-04:** Implement LangGraph **Node 4 (Freelance Proposal Closer)** generating 2-line pattern-interrupt hooks, matching project proof, 3-step roadmap, and milestone tables.
- [ ] **BE-06:** Build deterministic single-column **Typst CLI PDF compiler** (`< 300ms`) and **`python-docx` compiler**, uploading outputs to Cloudflare R2 / S3.
- [ ] **FL-04:** Build `/onboarding` Base CV upload screen and interactive Master Knowledge Graph editor with anchor lock switches.
- [ ] **FL-05:** Build `POST /api/v1/tailor/single-jd` Quick-Tailor flow and integrate 60fps native PDF preview (`pdfrx`) in **Tab 3 (Chameleon CV Vault)**.

---

## 3. Sprint 3 (Weeks 5–6): Multi-Country Scrapers, Mission Dashboard & Sensei Dojo
- [ ] **BE-07:** Integrate salaried job scrapers (`JobSpy`, `Crawl4AI`, Playwright Stealth + rotating proxies) for LinkedIn, Indeed (country TLDs), Greenhouse, Lever, Workday, and RemoteOK.
- [ ] **BE-08:** Integrate freelance project connectors (Upwork RSS/API, Freelancer.com API, PeoplePerHour, LinkedIn hiring posts) for `FREELANCE_GIG` mode.
- [ ] **BE-09:** Implement `pgvector` semantic pre-filtering and `WS /ws/v1/missions/{id}` real-time telemetry streaming.
- [ ] **AI-05:** Implement LangGraph **Node 5 (Sensei Defense Generator)** producing 60-second mental models, first-person STAR stories (with production bug narratives), 3–5 Trap Q&As, and 5-term vocabulary cheat sheets for every item in `injected_skills_delta`.
- [ ] **FL-06:** Build **Tab 1 (Mission Control Dashboard)** with Job/Freelance mode switcher, multi-country flag chips, commitment checkboxes, Aggressiveness Slider, Bento metrics grid, and Live Telemetry Drawer.
- [ ] **FL-07:** Build **Tab 2 (Opportunity Pipeline & Visual Diff Viewer)** with emerald-green injected skill highlights and per-bullet toggle controls (`POST /api/v1/artifacts/{id}/regenerate`).
- [ ] **FL-08:** Build **Tab 4 (Skill-Mimic Dojo)** with expandable skill cards, interactive flip flashcards, TTS audio mode, and mastery status checkboxes (`Drift` offline SQLite sync).
- [ ] **GP-01 (CRITICAL TIMING):** Upload initial `.aab` to **Google Play Console Closed Testing Track** in Week 5 and opt-in 12–15+ testers to start the 14-day continuous testing clock.

---

## 4. Sprint 4 (Weeks 7–8): Billing, Assisted Auto-Applier, QA & Production Release
- [ ] **BE-10:** Implement `POST /api/v1/billing/webhook` to handle RevenueCat / Google Play Billing subscription events (`$3.99/mo`) and consumable credit pack top-ups (`+$5`, `+$10`, `+$25`).
- [ ] **FL-09:** Integrate `purchases_flutter` (RevenueCat SDK) paywall and wallet top-up flows inside Flutter.
- [ ] **FL-10:** Build **Assisted Auto-Apply Browser (`flutter_inappwebview`)** with JS auto-fill injection for Greenhouse, Lever, Workday, LinkedIn, and Upwork, keeping final "Submit" click manual.
- [ ] **GP-02:** Add 1-tap `🚩 Report / Flag AI Output` button (`POST /api/v1/artifacts/{id}/flag`) and mandatory user review confirmation gate (`user_reviewed_confirmed`) before PDF export/apply.
- [ ] **GP-03:** Implement in-app `"Delete Account & Wipe Career Data"` button (`DELETE /api/v1/users/me`) and public web deletion URL for Google Play Data Safety form.
- [ ] **QA-01:** Pass **ATS Parser Stress Test** (50 PDFs/DOCXs across 5 industries -> 100% parse accuracy, 0 formatting scrambles).
- [ ] **QA-02:** Pass **Chronological Sanity Test** (0 modern frameworks grafted into pre-release job dates).
- [ ] **QA-03:** Pass **Token Billing Reconciliation Audit** (100% match between PostgreSQL `llm_usage_ledger` and OpenRouter logs; $0.00 master key deduction on BYOK runs).
- [ ] **QA-04:** Pass **Sensei Coverage Audit** (100% 1:1 mapping between `injected_skills_delta` and Dojo study decks).
- [ ] **GP-04:** Complete 14-day Closed Testing verification and promote `.aab` to **Google Play Store Production**.