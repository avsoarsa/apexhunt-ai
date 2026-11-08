# System Guardrails, Coding Standards & Compliance Rules: ApexHunt AI

Every AI coding assistant, backend engineer, prompt engineer, and Flutter developer working on **ApexHunt AI** must strictly enforce the rules defined in this document.

---

## 1. The 5 Non-Negotiable Laws of Believable Skill Grafting (Chameleon Engine)

1. **Law 1 — Immutable Background-Check Anchors:**
   * When `background_check_safe_mode = TRUE` (the default), the Chameleon Agent is **strictly forbidden** from altering employer names, employment start/end dates, university names, degrees, or graduation years from `master_knowledge_graph`.
   * Background check agencies (HireRight, Checkr, First Advantage) verify *where* and *when* a candidate worked via tax/PF records—not which internal framework or architecture they used on a sprint. Only internal bullet points, project stacks, and summaries may be morphed.
2. **Law 2 — Chronological Release-Year Lock:**
   * The agent must verify the public release year of every technology before grafting it into a past role.
   * **Hard Constraint:** Never claim experience exceeding the candidate's graduation/career start year, and never inject a tool released in year $Y$ into an employment block that ended prior to year $Y$. Place modern tools into the user's current/most recent role or an ongoing *"Independent Technical Consulting & R&D"* block.
3. **Law 3 — Contextual Ecosystem Pairing:**
   * Never drop a missing JD keyword in isolation. Every grafted skill must be surrounded by its authentic technical ecosystem inside the bullet point (e.g., if grafting *Apache Kafka*, pair it with *partition keys, consumer groups, idempotent processing, and dead-letter queues*).
4. **Law 4 — Domain-Adjacency Guardrail:**
   * Graft skills across adjacent engineering/business domains seamlessly (e.g., grafting *React Native* or *GraphQL* onto a Flutter/Mobile engineer's CV), but flag an explicit UI warning before attempting cross-discipline leaps requiring statutory licenses (e.g., medical/legal licensure).
5. **Law 5 — Mandatory XYZ Quantified Bullet Structure:**
   * Every rewritten CV bullet must follow the formula: **Accomplished [X] as measured by [Y], by implementing [Z (Injected JD Skill + Real Project Context)]**.
6. **Law 6 — 1:1 Sensei Defense Parity:**
   * Not a single skill may be injected into `tailored_cv_json` unless it is simultaneously logged in `injected_skills_delta` and paired with a complete **Sensei Defense Dossier** (60s mental model + first-person STAR story + 3–5 Trap Q&As + vocabulary cheat sheet).

---

## 2. White-Label OpenRouter & BYOK Monetization Rules

1. **Zero OpenRouter Leakage in Managed UI:**
   * The string `"OpenRouter"` must **never** appear in the Managed Mode frontend UI, model picker labels, or error messages sent to the Flutter client. Only show `"OpenRouter"` as one of the selectable providers inside the optional developer **BYOK Mode** dropdown.
2. **No Unlimited Flat-Rate AI Execution:**
   * Never bypass `execute_llm_step()` token accounting. Every Managed Mode LLM call must atomically deduct:
     $$\text{Total Deducted USD} = \left( \text{Upstream Cost USD} + (\text{Total Tokens} \times \$0.000001) \right) \times 1.15$$
   * Both Managed Mode and BYOK Mode require `user_wallets.subscription_status IN ('ACTIVE', 'GRACE_PERIOD')` (`$3.99/mo` base subscription).
3. **Zero Server-Side Persistence of BYOK Keys:**
   * User-supplied BYOK API keys (`X-BYOK-Key`) must reside exclusively inside hardware-backed `flutter_secure_storage` on the mobile device. The FastAPI backend may accept `X-BYOK-Key` in memory to execute the upstream request, but **must never** log it to disk, Sentry, or PostgreSQL.

---

## 3. ATS Document Formatting & Compilation Rules

1. **Strict Single-Column Semantic Layout:**
   * All PDFs compiled via Typst (`ats_single_column.typ`) and Word documents compiled via `python-docx` must be **strictly single-column**, top-to-bottom linear layouts.
2. **Banned Elements in Resume Outputs:**
   * **NEVER** use multi-column tables, floating text boxes, sidebars, skill progress bars, profile photos, icons, or canvas-rendered text in generated CVs—these cause parsing failures in Workday, Taleo, and Greenhouse.
3. **Deterministic File Naming:**
   * Every generated artifact must be named deterministically: `{FirstName}_{LastName}_{SanitizedCompany}_{SanitizedRole}.pdf` (and `.docx`).

---

## 4. Flutter Architecture & Mobile Security Rules

1. **Feature-First Clean Architecture Enforcement:**
   * UI Widgets (`presentation`) must never call `Dio` or `Drift` directly. All state mutations must flow through Riverpod `AsyncNotifier` / `Notifier` classes (`application`) calling repository interfaces (`domain` / `data`).
2. **Offline-First Study Access:**
   * Every generated `tailored_artifact` (including local PDF bytes and `sensei_prep_dossier` JSON) must be mirrored into local `Drift` SQLite tables immediately upon receipt so the user can study their interview defense scripts without an internet connection.
3. **Residential-IP Assisted Applying:**
   * Bulk job index scraping must run on backend workers via rotating proxies—never run heavy background scraping loops on the user's phone battery. Use on-device `flutter_inappwebview` strictly for final assisted form filling and submission under the user's residential IP.

---

## 5. Google Play Store Compliance Guardrails

1. **Store & UI Copy Positioning:**
   * Always describe the application in UI copy, metadata, and store listings as an **"AI Career Optimization, Resume Tailoring & Technical Interview Upskilling Simulator."**
2. **Mandatory Human-in-the-Loop (HITL) Confirmation Gate:**
   * Before unlocking PDF export, sharing, or Assisted Auto-Apply submission, the UI must require the user to check the confirmation gate (`user_reviewed_confirmed = true`).
3. **Generative AI Content Reporting & Data Deletion:**
   * Every generated CV and proposal preview screen must display a visible `🚩 Report / Flag AI Output` action (`POST /api/v1/artifacts/{id}/flag`).
   * The Settings screen must maintain a functional 1-tap `"Delete Account & Wipe Career Data"` action (`DELETE /api/v1/users/me`).