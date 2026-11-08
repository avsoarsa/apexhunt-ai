# Application Flow & Multi-Agent State Machine Specification: ApexHunt AI

**Orchestration Engine:** LangGraph Directed Acyclic Graph (DAG) with Cyclic ATS Verification  
**Real-Time Transport:** Bidirectional WebSockets (`/ws/v1/missions/{id}`) + HTTPS REST

---

## 1. End-to-End User & System Journey Flows

### Flow 1: Onboarding & Master Knowledge Graph (MKG) Ingestion
1. **Sign-In & Welcome Wallet Initialization:** User signs in via Google/Apple/Email. Backend provisions `users` row and `user_wallets` row pre-loaded with `$0.500000` welcome credits (`preferred_routing_mode = 'MANAGED'`).
2. **Base CV Upload:** User selects their existing PDF or DOCX resume via `FilePicker` (or pastes raw text + LinkedIn/GitHub/Portfolio URLs).
3. **Graph Extraction & Anchor Locking:**
   * Backend calls `POST /api/v1/profile/parse-cv`.
   * Parser extracts structured JSON (`master_knowledge_graph`): Verified Employers, Exact Start/End Dates, Job Titles, Education Credentials, Core Skills, and Past Projects.
   * Backend generates `cv_embedding` (`vector(1536)`) for semantic matching.
   * Flutter displays parsed cards; user verifies and locks chronological anchors (`Background-Check Safe Mode = ON`).

### Flow 2: AI Brain & Billing Configuration Flow
1. User taps the **AI Engine & Wallet Pill** in the top app bar of the Mission Control Dashboard.
2. **Path A — Managed Apex Cloud (Default):**
   * User selects a branded tier (*Apex Flash*, *Apex Pro*, or *Apex Elite Chameleon*) or picks from the white-labeled model dropdown.
   * If `credit_balance_usd <= $0.02` or `subscription_status != 'ACTIVE'`, RevenueCat paywall sheet prompts user to activate the `$3.99/mo` base subscription and/or purchase a `$5 / $10 / $25` credit pack.
3. **Path B — Bring Your Own Key (BYOK):**
   * User verifies active `$3.99/mo` base subscription, switches toggle to `BYOK`, selects provider (`OpenRouter`, `OpenAI`, `Anthropic`, `Google Gemini`, `Groq`, or `Custom Base URL`), enters API key, and taps **"Test Connection & Save to Keystore"**.
   * Flutter validates the key with a 5-token ping, saves it inside `flutter_secure_storage`, and attaches `X-BYOK-Key` + `X-BYOK-Base-URL` headers to subsequent API calls.

### Flow 3: Autonomous Mission Launch & Real-Time Telemetry Flow
1. On **Tab 1 (Mission Control Dashboard)**, user configures:
   * **Mission Mode:** `SALARIED_JOB` or `FREELANCE_GIG`.
   * **Target Countries:** e.g., `['US', 'GB', 'AE', 'REMOTE']`.
   * **Commitment Types:** e.g., `['FULL_TIME', 'PART_TIME']` or `['HOURLY', 'FIXED_PRICE']`.
   * **Role Keywords:** e.g., `['Flutter Developer', 'AI Engineer']`.
   * **Aggressiveness Level:** `1` (Conservative), `2` (Smart Bridge), or `3` (Full Chameleon Mimicry).
2. User taps **"Deploy Autonomous Agent"** (`POST /api/v1/missions/launch`).
3. Flutter connects to `WS /ws/v1/missions/{mission_id}` and expands the **Live Agent Telemetry Drawer**, rendering real-time stage transitions as each discovered opportunity moves through the 5-node LangGraph pipeline.

---

## 2. The 5-Node LangGraph Multi-Agent Pipeline

Every matched opportunity (or single pasted JD via `POST /api/v1/tailor/single-jd`) executes the following stateful graph:

```text
[Raw JD / Project Brief + MasterCV_JSON]
                 │
                 ▼
      ┌─────────────────────┐
      │  Node 1: JD Auditor │  ──► Extracts Verified_Skills vs. Missing_Delta_Skills
      └──────────┬──────────┘
                 │
                 ▼
      ┌─────────────────────┐
      │  Node 2: Chameleon  │◄─┐
      │   CV Synthesizer    │  │   Grafts Missing_Delta_Skills into real past roles/projects
      └──────────┬──────────┘  │
                 │             │
                 ▼             │ Loop back with critique if
      ┌─────────────────────┐  │ ATS Score < 94% (or < 92% threshold)
      │    Node 3: ATS      │──┘
      │ Gatekeeper & Critic │
      └──────────┬──────────┘
                 │ (Approved: ATS >= 94%)
        ┌────────┴────────┐
        ▼                 ▼ (If mode == FREELANCE_GIG)
┌───────────────┐ ┌───────────────────────┐
│ Typst PDF &   │ │ Node 4: Freelance     │
│ DOCX Compiler │ │ Proposal Closer       │
└───────┬───────┘ └───────────┬───────────┘
        └────────┬────────────┘
                 ▼
      ┌─────────────────────┐
      │  Node 5: Sensei     │  ──► Builds 60s Mental Model + STAR Story + 5 Trap Q&As
      │  Defense Generator  │      for every skill in injected_skills_delta
      └─────────────────────┘
```

### Node-by-Node Input/Output Specification

| Node | Input State | Core Reasoning & Execution Task | Output State Artifact |
| :--- | :--- | :--- | :--- |
| **Node 0: Scout Agent** *(Discovery Mode)* | `Mission_Config` (`countries`, `mode`, `commitment`, `keywords`) | Queries country-specific job boards / freelance feeds via proxies, deduplicates, and ranks via `pgvector` similarity. | `Queued_Opportunities[]` |
| **Node 1: JD Auditor & Gap Extractor** | `MasterCV_JSON` + `Raw_JD_Text` + `Mission_Mode` | Decomposes JD into mandatory hard skills, preferred tools, domain buzzwords, and deliverables. Splits into `Matched_Skills` vs. `Missing_Delta_Skills`. | `GapAnalysisReport` (JSON list of missing skills & candidate past-role insertion anchors). |
| **Node 2: Chameleon CV Synthesizer** | `MasterCV_JSON` + `GapAnalysisReport` + `Aggressiveness_Level (1-3)` | Re-architects Executive Summary, Core Competencies, and Work Experience bullets to embed 100% of `Missing_Delta_Skills` into chronologically valid past roles/projects. | `TailoredCV_JSON` + `injected_skills_delta` (exact before/after bullet map). |
| **Node 3: ATS Gatekeeper & Critic** | `TailoredCV_JSON` + `GapAnalysisReport` | Runs deterministic + LLM verification checking keyword density, action verbs, chronological sanity, and locked employer anchors. Loops back to Node 2 (max 2 retries) if score `< 94%`. | `ATS_Scorecard` (`base_ats_score` vs. `final_ats_score`, e.g., `54% -> 97.5%`). |
| **Node 4: Freelance Proposal Closer** *(Freelance Mode)* | `TailoredCV_JSON` + `Client_Brief` + `User_Rate_Config` | Drafts a custom freelance bid proposal with a 2-line pattern-interrupt hook, proof of matching project from the morphed CV, 3-step roadmap, and milestone table. | `freelance_proposal_md` |
| **Node 5: Sensei Defense Generator** | `injected_skills_delta` + `TailoredCV_JSON` | For every injected or upgraded skill, generates: (1) 60-Second Mental Model, (2) First-person STAR project story, (3) 3–5 Technical Trap Q&As, and (4) 5-term Vocabulary Cheat Sheet. | `sensei_prep_dossier` (JSONB stored and synced to Flutter Dojo Tab). |

---

## 3. Production System Prompts (Exact Backend Specifications)

### 3.1 Node 1 & Node 2: Chameleon CV Architect System Prompt
```text
SYSTEM ROLE: You are the ApexHunt Chameleon CV Architect, an elite technical recruiter and domain engineer. Your sole objective is to transform the user's Master CV into a 95%+ ATS and Hiring-Manager match for the Target Job Description (JD) or Freelance Project Brief.

INPUTS PROVIDED:
1. MASTER_CV_JSON: The user's baseline career history, dates, companies, and projects.
2. TARGET_JD: The exact job description or freelance project requirements.
3. AGGRESSIVENESS_LEVEL: [1 = Reframe Only | 2 = Adjacent Skill Grafting | 3 = Full JD Skill Mimicry].

STRICT EXECUTION RULES:
1. LOCKED ANCHORS: You MUST keep all employer names, employment start/end dates, and education history identical to MASTER_CV_JSON.
2. ZERO SKILL LEFT BEHIND: Extract every mandatory and preferred technical skill, tool, methodology, and domain requirement from TARGET_JD.
3. BELIEVABLE EXPERIENCE GRAFTING (Levels 2 & 3):
   - For every skill in TARGET_JD that is missing from MASTER_CV_JSON, identify the most chronologically appropriate and architecturally compatible role or project in MASTER_CV_JSON.
   - Rewrite or replace existing bullet points in that role so the user demonstrably solved a concrete business problem using the required JD skill.
   - Include realistic implementation details (architecture patterns, edge-case handling, and plausible performance metrics like latency reduction %, throughput, or revenue impact).
   - Verify chronological plausibility: only place modern tools into roles active after that tool's public release.
4. ATS OPTIMIZATION: Mirror exact keyword spelling and phrasing from TARGET_JD in both the Executive Summary, Core Competencies array, and Work Experience bullets.
5. DIFF TRACKING: For every bullet point you modify or synthesize using a skill the user did not originally list, record the exact `skill_name`, `jd_importance`, `grafted_into_role`, `original_bullet`, and `morphed_bullet` inside the `injected_skills_delta` array so the Sensei Prep Agent can train the user on it.

OUTPUT FORMAT: Return ONLY valid JSON conforming strictly to `TailoredCVOutputSchema`.
```

### 3.2 Node 5: Sensei Skill-Mimic & Interview Defense System Prompt
```text
SYSTEM ROLE: You are the ApexHunt Sensei Coach. The Chameleon Agent has just updated the candidate's CV with specific skills and project bullets tailored to a target Job Description (`INJECTED_SKILLS_DELTA`). The candidate may have zero or limited prior hands-on experience with these newly injected skills. Your job is to turn the candidate into a confident, articulate practitioner who can defend every single word on their updated CV in a live technical interview or freelance client discovery call within 30 minutes of reading your guide.

FOR EVERY INJECTED OR UPGRADED SKILL IN `INJECTED_SKILLS_DELTA`, GENERATE:
1. THE 60-SECOND MENTAL MODEL: Plain-English explanation of what this technology/skill actually does, why companies use it over alternatives, and its core architectural components.
2. YOUR PERSONAL PROJECT NARRATIVE ("HOW YOU USED IT"):
   - Write a first-person STAR story (Situation, Task, Action, Result) anchored specifically to the exact company and project on the user's CV where this skill was grafted.
   - Detail the exact architectural flow: What triggered the workflow? How was it configured? What broke in production (a realistic bottleneck or bug), and how did "you" debug and fix it?
3. TOP 3-5 INTERVIEW "TRAP" QUESTIONS & GOLDEN ANSWERS:
   - Formulate the exact probing questions a senior engineer or client will ask to verify if the candidate truly worked with this skill based on the CV bullet.
   - Provide concise, conversational, senior-level answers that reference concrete trade-offs.
4. RAPID VOCABULARY CHEAT SHEET: 5 domain terms/commands to drop naturally in conversation and 2 rookie mistakes to avoid saying.

OUTPUT FORMAT: Return ONLY valid JSON conforming strictly to `SenseiPrepDossierSchema`.
```

### 3.3 Node 4: Freelance Project Closer System Prompt
```text
SYSTEM ROLE: You are an elite top-1% Upwork/Toptal Freelance Deal Closer. Using the client's project brief and the user's newly tailored portfolio/CV, generate a high-converting proposal that wins an immediate reply.

STRUCTURE REQUIREMENTS:
1. THE PATTERN-INTERRUPT HOOK (First 2 lines): Address the client's exact core problem immediately—never start with "Hi, my name is X and I have Y years of experience."
2. PROOF OF IDENTICAL EXECUTION: Reference the specific tailored project from the user's morphed CV that mirrors the client's tech stack and outcome.
3. 3-STEP EXECUTION PLAN: Give the client a clear, low-risk roadmap showing how you will deliver their project from Day 1 to final handover.
4. MILESTONE BREAKDOWN & CALL TO ACTION: Propose 2–3 logical milestones and end with one sharp technical question about their project that compels them to reply.
```

---

## 4. Flow 4: Review, Study & Assisted Auto-Apply Flow
1. **Diff Inspection (`Tab 2: Pipeline`):** User inspects the side-by-side Diff Viewer (`Original Match: 54% -> Boosted Match: 97.5%`). User can toggle off any individual grafted bullet if desired (which triggers a sub-second Typst re-compile).
2. **Mandatory Review Gate:** User checks *"I have reviewed this AI-tailored draft and prepared with the companion study guide"* before exporting or auto-applying.
3. **Assisted WebView Submission (`Tab 3 -> Auto-Apply`):**
   * User taps **"Launch Assisted Apply"**.
   * `InAppWebView` opens the target `source_url` (Greenhouse, Lever, Workday, LinkedIn, or Upwork).
   * Embedded JS bridge highlights and auto-populates text fields and attaches the local tailored PDF/DOCX from the app cache.
   * If a CAPTCHA appears, the user solves it directly in the WebView and taps the final **Submit** button.