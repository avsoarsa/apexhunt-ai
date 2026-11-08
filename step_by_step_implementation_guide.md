# End-to-End Implementation & Play Store Launch Guide: ApexHunt AI

**Target Velocity:** 8-Week Accelerated Sprint Plan (with 12-Week Extended Enterprise Buffer)  
**Release Target:** Google Play Store Production Track (`.aab` Android App Bundle)

---

## 1. Phase-by-Phase Engineering Implementation Guide

### Phase 1 (Weeks 1–2): Backend Foundation, Database & White-Label OpenRouter Proxy
1. **Provision Infrastructure:**
   * Deploy PostgreSQL 16 with `pgvector` and Redis (Upstash/Render/AWS).
   * Execute the complete SQL DDL from `Schema.md`.
2. **Build FastAPI Auth & Billing Middleware:**
   * Configure JWT validation (Supabase Auth or Firebase Auth).
   * Implement `GET /api/v1/llm/catalog` with a Celery Beat background job that syncs `https://openrouter.ai/api/v1/models` every 6 hours, strips OpenRouter strings, maps branded tiers (`apex-flash`, `apex-pro`, `apex-elite`), and adds `+$0.000001/token` (`+$1.00/1M tokens`) + `1.15` gateway buffer.
   * Implement `execute_llm_step()` middleware handling both Track A (Managed Proxy with atomic PostgreSQL wallet deduction) and Track B (stateless BYOK header pass-through via `X-BYOK-Key` and `X-BYOK-Base-URL`).
3. **Initialize Flutter Clean Architecture Scaffold:**
   * Run `flutter create --org com.apexhunt apexhunt_ai`.
   * Set up `flutter_riverpod`, `go_router`, `dio`, `drift`, and `flutter_secure_storage`.
   * Build the `SecureKeyVault` service to store BYOK keys in Android Keystore (`EncryptedSharedPreferences = true`).

### Phase 2 (Weeks 3–4): Master CV Parser, Chameleon LangGraph & Typst PDF Compiler
1. **Master CV Ingestion (`/api/v1/profile/parse-cv`):**
   * Use `pymupdf` (`fitz`) and `python-docx` to extract clean text from uploaded resumes.
   * Pass extracted text to an LLM structured-output node to populate `master_knowledge_graph` JSONB and compute the `vector(1536)` embedding.
2. **LangGraph 5-Node Pipeline:**
   * Implement Node 1 (`JDAuditor`), Node 2 (`ChameleonSynthesizer`), Node 3 (`ATSGatekeeper` with conditional loop-back edge if score `< 94%`), Node 4 (`FreelanceCloser`), and Node 5 (`SenseiDefenseGenerator`) using the exact system prompts in `AppFlow.md`.
   * Enforce chronological sanity checks (comparing tool release years against role end dates) and locked employer/date anchors when `background_check_safe_mode = TRUE`.
3. **Sub-Second Typst & DOCX Compilation:**
   * Install the `typst` binary in your backend Docker container.
   * Create `ats_single_column.typ` accepting `TailoredCV_JSON` and compiling to PDF in `< 250ms`.
   * Create matching `compile_docx.py` using `python-docx`, upload both artifacts to Cloudflare R2 / S3, and return signed download URLs.
4. **Flutter Base Profile & Quick-Tailor Screens:**
   * Build `/onboarding` CV upload UI, Master Knowledge Graph card editor, and native PDF previewer (`pdfrx`).

### Phase 3 (Weeks 5–6): Multi-Country Scrapers, Mission Dashboard & Skill-Mimic Dojo
1. **Discovery Scrapers (`Scout Agent`):**
   * Integrate `JobSpy`, `Crawl4AI`, and Playwright Stealth with rotating residential proxies for LinkedIn, Indeed (country-localized TLDs), Greenhouse, Lever, and RemoteOK.
   * Integrate Upwork RSS/API and Freelancer.com Active Projects API for `FREELANCE_GIG` mode.
2. **WebSocket Live Telemetry (`/ws/v1/missions/{id}`):**
   * Publish Redis Pub/Sub events from Celery workers (`JOB_FOUND`, `GAP_DETECTED`, `SKILL_GRAFTED`, `PDF_READY`, `WALLET_UPDATED`) and forward them over FastAPI WebSockets to the Flutter Mission Control Dashboard.
3. **Flutter Dashboard, Diff Viewer & Sensei Dojo:**
   * Build **Tab 1 (Mission Control)** with country chips, Job/Freelance segmented toggle, commitment checkboxes, and Aggressiveness Slider (1–3).
   * Build **Tab 2 (Pipeline & Diff Viewer)** rendering `RichText` green spans for injected skills and per-bullet revert switches.
   * Build **Tab 4 (Skill-Mimic Dojo)** with 60s mental models, first-person STAR scripts, TTS audio briefing, and interactive flip flashcards for the 5 Trap Q&As.

### Phase 4 (Weeks 7–8): RevenueCat Billing, Assisted WebView Auto-Applier & Play Store Launch
1. **Google Play Billing & RevenueCat Integration:**
   * Configure Google Play Console Products:
     * Subscription: `apex_monthly_399` (`$3.99/month` or `₹249/month`).
     * Consumable In-App Products: `apex_credits_5` (`$5`), `apex_credits_10` (`$10`), `apex_credits_25` (`$25`).
   * Connect RevenueCat (`purchases_flutter`) and point webhooks to `POST /api/v1/billing/webhook`.
2. **Assisted Auto-Apply Browser (`flutter_inappwebview`):**
   * Build the embedded browser screen with JavaScript DOM selectors for Greenhouse, Lever, Workday, and Upwork to auto-fill candidate details and attach the local tailored PDF while keeping the final "Submit" button manual.
3. **Play Store Compliance & Production Submission:**
   * Wire up the 1-tap `🚩 Report / Flag AI Output` button (`POST /api/v1/artifacts/{id}/flag`), mandatory user review checkbox, and in-app + web Account Deletion endpoint (`DELETE /api/v1/users/me`).

---

## 2. Google Play Store Approval & Policy Compliance Playbook

1. **2026 Play Console 14-Day Closed Testing Rule:**
   * If publishing under a newly registered **Personal/Individual** Google Play Developer account, Google requires **at least 12 testers opted-in continuously for 14 days** on the Closed Testing track before unlocking Production access.
   * **Action:** Upload your internal/alpha `.aab` build at the start of **Week 5** and enroll 15+ testers immediately so the 14-day timer finishes in Week 7. *(Alternatively, register as an Organization account using a D-U-N-S number to bypass the 14-day waiting period entirely).*
2. **Store Listing Framing (Preventing "Deceptive Behavior" Rejections):**
   * Frame all store copy, screenshots, and onboarding around **"AI Career Optimization, Resume Role-Alignment & Technical Interview Upskilling Simulator."**
   * Emphasize that the app bridges skill gaps by teaching the candidate the required technology via personalized study dossiers while aligning transferable experience.
3. **Billing Policy Compliance:**
   * Do not include external web checkout links telling users to buy OpenRouter credits outside the app. Keep the BYOK API key field cleanly inside `Settings -> Developer / Advanced BYOK Mode` for users who already possess API keys.

---

## 3. Quality Assurance (QA) & Validation Protocol

| Test Suite | Verification Procedure | Mandatory Pass Threshold |
| :--- | :--- | :--- |
| **1. ATS Parser Stress Test** | Run 50 generated PDF and DOCX files across 5 industries through commercial ATS parsers (Affinda, Sovren, Greenhouse simulator, Workday parser). | **100% extraction accuracy** on contact info, chronological work history, and injected skills; **0 formatting scrambles**. |
| **2. Chronological Sanity Test** | Feed JDs requiring bleeding-edge tools (e.g., released in 2024–2026) against a user CV containing jobs from 2018–2026. | Agent **never** injects a modern tool into a pre-release employment block (**0 chronological hallucinations**). |
| **3. Token Billing & Markup Audit** | Execute 100 agent missions across Managed Proxy Mode and BYOK Mode; reconcile PostgreSQL `llm_usage_ledger` against OpenRouter API activity logs. | **100% exact reconciliation** of upstream cost + `$1.00/1M` markup + `1.15` buffer; **$0.00 charged** to master key during BYOK runs. |
| **4. Sensei Coverage Audit** | Verify that every single skill added to `injected_skills_delta` has a corresponding 60s mental model, STAR story, and 3–5 Trap Q&As in the Dojo tab. | **1:1 mapping** between green-highlighted CV skills and generated study cards. |