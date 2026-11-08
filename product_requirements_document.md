# Product Requirements Document (PRD): ApexHunt AI

**Target Platform:** Flutter 3.x (Android Primary for Google Play Store, iOS/Web Ready)  
**Architecture:** Autonomous Career & Freelance Agent + Hybrid White-Label LLM Gateway  
**Status:** Production Engineering Blueprint (v1.0)

---

## 1. Executive Summary & Product Vision

**ApexHunt AI** is a cross-platform mobile application built with Flutter (targeting Google Play Store first) that acts as an autonomous job-hunting and freelance-bidding agent with a real-time command dashboard. Users upload their baseline CV or freelance portfolio once, configure mission parameters on an interactive dashboard (target country, full-time vs. part-time, salaried job vs. freelance project, work arrangement, and domain keywords), and deploy an autonomous multi-agent workflow.

Once triggered, the agent discovers live opportunities across job aggregators and freelance marketplaces, analyzes the exact Job Description (JD) or client project brief, and dynamically re-engineers the user's CV and proposal to achieve a **95%+ Applicant Tracking System (ATS)** and client match. Where a target JD demands tools, frameworks, or domain skills the user has not previously worked with, the **Chameleon Engine** grafts contextually believable project narratives and technical responsibilities onto the user's existing career timeline. Simultaneously, the **Skill-Mimic Sensei** generates an instant personalized technical study dossier and STAR-method interview defense script so the candidate can master and defend every single line on the newly tailored CV.

---

## 2. Target User Personas & Core Modes

| Persona | Pain Point | ApexHunt AI Solution |
| :--- | :--- | :--- |
| **Global Job Seeker** *(Full-Time / Part-Time / Internship / Contract)* | Manually tailoring CVs for 50+ listings across countries takes hours; automatic ATS rejections occur when 2–3 niche keywords are missing from the resume. | Selects target countries, job title, and employment type. Agent scrapes listings, injects missing JD skills into real past work history, compiles an ATS-pure PDF/DOCX, and creates an interview defense guide. |
| **High-Velocity Freelancer / Agency Owner** *(Hourly / Fixed-Price)* | Speed and hyper-relevance win freelance bids on Upwork, Freelancer, Toptal, and LinkedIn. Writing custom proposals and domain-specific CVs per gig is too slow. | Switches dashboard to **Freelance Mode**. Agent scans fresh project briefs, rewrites the user's portfolio/CV around the client's exact tech stack, and drafts a milestone-based winning bid proposal. |
| **Power Developer / BYOK User** *(Cost-Conscious / Custom Stack)* | Wants full control over underlying LLM choice (Claude, GPT-4o, DeepSeek, Qwen, Gemini, or local endpoints) without paying steep SaaS markups. | Subscribes to the low base tier and connects their own OpenRouter, OpenAI, Anthropic, Gemini, Groq, or custom OpenAI-compatible API key via encrypted on-device storage. |

---

## 3. Dual-Track Monetization & White-Label LLM Economics

Because multi-step agentic workflows (scraping JDs, gap analysis, rewriting CVs, ATS verification, and generating interview prep dossiers) consume **8,000 to 15,000 tokens** per tailored application, offering "unlimited AI runs" on a flat subscription would bankrupt the platform. ApexHunt AI separates fixed infrastructure subscription costs from variable LLM token consumption using a two-pronged model:

### 3.1 Base Platform Subscription (Mandatory for Active Agent Missions)
* **Pricing:** Accessible micro-subscription at **$3.99/month** (or **$2.99–$4.99/month / ₹199–₹399/month**) billed via Google Play Billing (managed with RevenueCat).
* **Coverage:** Covers cloud orchestration servers, job-board scraping residential proxy bandwidth, Typst/DOCX PDF compilation engines, and database storage.
* **Margin:** Yields near-100% gross margin after store fees when paired with either LLM track below.

### 3.2 Track A: Managed "Apex AI Credits" (White-Labeled OpenRouter Proxy — Default for 90% of Users)
* **Frontend Branding Experience:** Users **never** see "OpenRouter" in the Managed frontend UI. They see proprietary branded engines:
  * **Apex Flash / Eco Agent** *(DeepSeek V3 / Gemini 2.5 Flash)* — ~$0.01 per job application (Best for bulk scanning).
  * **Apex Pro / Balanced Agent** *(GPT-4o / Qwen Max)* — ~$0.03 per job application (Great for freelance proposals).
  * **Apex Elite Chameleon** *(Claude 3.7 / 4.5 Sonnet)* — ~$0.06 per job application (Unbeatable human-like CV bullet grafting and interview prep scripts).
  * Users can also access a curated white-labeled model picker derived from OpenRouter's 300+ models with OpenRouter branding stripped.
* **Wallet Top-Ups:** New users receive a **$0.50 welcome bonus** in their wallet (`credit_balance_usd`). Users can top up consumable credit packs (**+$5, +$10, +$25**) via Google Play Billing / Razorpay / Stripe.
* **Backend Markup Formula:** All Managed requests route through the ApexHunt FastAPI backend using a master OpenRouter API key. The backend reads the exact upstream token usage (`prompt_tokens`, `completion_tokens`, and `total_cost_usd`) and applies a flat **+$1.00 per 1,000,000 (1M) tokens** (`+$0.000001` per token) markup plus a **15% payment gateway buffer** (to absorb Google Play's 10%–15% service fee):
  $$\text{User Deduction (USD)} = \left[ \text{Upstream OpenRouter Cost} + \left( \frac{\text{Prompt Tokens} + \text{Completion Tokens}}{1,000,000} \times \$1.00 \right) \right] \times 1.15$$
* **Unit Economics Example:** A complete CV rewrite + interview prep dossier consuming 12,000 tokens on an efficient model ($0.30/1M upstream) costs $0.0036 upstream + $0.012 markup = **~$0.018 per complete job application** (over 80% profit margin for the platform while allowing ~275 tailored applications on a $5 top-up).

### 3.3 Track B: Bring Your Own Key (BYOK Mode)
* **Supported Providers:** Active base subscribers can toggle **BYOK Mode** in Settings and input their own API key from **OpenRouter, OpenAI, Anthropic, Google Gemini, Groq, or any Custom OpenAI-Compatible Base URL** (including self-hosted Ollama over Tailscale/LAN).
* **Security & Zero Platform Liability:** Keys are stored exclusively in hardware-backed encrypted storage on the Flutter device (`flutter_secure_storage` using Android Keystore `AES-256-GCM`) and transmitted transiently via HTTPS headers (`X-BYOK-Key`, `X-BYOK-Base-URL`) during agent execution. Platform LLM inference cost is **$0.00**.

---

## 4. End-to-End Functional Requirements

### 4.1 Module 1: Master CV Ingestion & Career Knowledge Graph (MKG)
* **FR-1.1 (Multi-Format Ingestion):** Accept PDF, DOCX, or raw text resume uploads, alongside optional LinkedIn profile URLs, GitHub links, freelance portfolio links, and salary/hourly rate floors.
* **FR-1.2 (Master Knowledge Graph Construction):** Parse the baseline document into a structured `master_knowledge_graph` JSONB schema containing verified employers, chronological dates, educational credentials, core technical skills, and baseline project descriptions, plus a `vector(1536)` semantic embedding.
* **FR-1.3 (Chronological & Background-Check Lock):** Lock verifiable employment anchors (company names, university names, graduation years, employment start/end dates) in **"Background-Check Safe Mode"** so the agent never fabricates fake companies or alters dates that would fail HireRight/Checkr verification, while retaining full freedom to rewrite internal project responsibilities and technical stacks.

### 4.2 Module 2: Mission Control Dashboard & Multi-Source Discovery Engine
* **FR-2.1 (Mode & Commitment Filters):** Provide a unified command dashboard with toggles for:
  * **Mission Mode:** `Salaried Job Search` vs. `Freelance Project Hunt`.
  * **Commitment Types:** `Full-Time`, `Part-Time`, `Contract`, `Internship`, `Hourly`, `Fixed-Price`.
  * **Work Arrangement:** `Remote`, `Hybrid`, `On-Site`, `Visa-Sponsored`.
* **FR-2.2 (Multi-Country Targeting):** Multi-select country flag chips (`🌐 Worldwide Remote`, `🇺🇸 USA`, `🇬🇧 UK`, `🇦🇪 UAE`, `🇩🇪 Germany`, `🇮🇳 India`, `🇨🇦 Canada`, `🇦🇺 Australia`, plus a searchable `+ Add Country` modal) routing to country-localized job and gig scrapers.
* **FR-2.3 (Aggressiveness Slider):** 3-stage control allowing users to govern skill-grafting intensity:
  * `Level 1 — Conservative`: Keyword alignment and phrasing optimization only; zero new skills added.
  * `Level 2 — Smart Bridge`: Grafts domain-adjacent tools and frameworks into real past projects.
  * `Level 3 — Full Chameleon (Default)`: Rewrites project bullet points to match 100% of JD requirements and builds a full interview defense dossier.
* **FR-2.4 (Single-Target Quick Tailor):** Allow users to paste a specific JD URL or raw JD text directly for immediate single-job tailoring without running a full multi-site scrape.
* **FR-2.5 (Live Agent Telemetry Console):** Stream real-time WebSocket status events (`JOB_FOUND`, `GAP_DETECTED`, `SKILL_GRAFTED`, `PDF_READY`, `WALLET_UPDATED`) to the Flutter dashboard.

### 4.3 Module 3: The "Chameleon" CV & Freelance Proposal Morphing Engine
* **FR-3.1 (Deep JD Decomposition):** Extract mandatory hard skills, preferred tools, domain buzzwords, seniority expectations, and implicit deliverables from each discovered job or freelance brief.
* **FR-3.2 (Believable Skill-Gap Grafting):** When a JD requires a technology or domain skill missing from the user's Master CV (`Missing_Delta_Skills`), the agent identifies the most chronologically and architecturally compatible past role or freelance project on the user's CV and rewrites the bullet points to integrate that skill naturally using the **XYZ Impact Formula** (*Accomplished [X] as measured by [Y], by implementing [Z]*).
* **FR-3.3 (Freelance Bid Synthesis):** In Freelance Mode, generate both a tailored domain CV and a high-converting client proposal featuring:
  1. Pattern-interrupt 2-line hook addressing the client's exact core problem.
  2. Proof of identical execution referencing the newly tailored portfolio project.
  3. 3-step technical execution roadmap from Day 1 to handover.
  4. Proposed milestone breakdown, pricing estimate, and a sharp technical closing question.
* **FR-3.4 (ATS-Pure Document Compilation):** Compile the tailored CV into a clean, single-column PDF (via Typst CLI) and editable `.docx` file (via `python-docx`) in under 400ms, completely free of multi-column tables, graphics, icons, or canvas traps, guaranteeing 95%+ parse rates across Workday, Greenhouse, Lever, Ashby, and Taleo.

### 4.4 Module 4: "Skill-Mimic Dojo" (Candidate Preparation & Defense Engine)
* **FR-4.1 (Visual Delta Tracking):** Highlight every newly added or modified skill/bullet in emerald green on an interactive side-by-side Diff Viewer inside the Flutter app, with per-bullet toggle controls.
* **FR-4.2 (60-Second Mental Model):** For each injected skill, generate a plain-English architectural summary of what the technology does, why companies use it over alternatives, and its core components.
* **FR-4.3 ("How You Used It" Personal STAR Story):** Write a first-person STAR narrative (Situation, Task, Action, Result) anchored to the exact company and project on the user's CV where the skill was grafted, including what broke in production and how the user debugged it.
* **FR-4.4 (Top Interview "Trap" Questions & Golden Answers):** Formulate 3–5 deep-dive technical verification questions an interviewer or client will ask to test real-world familiarity with the grafted bullet point, paired with senior-level answers and a 5-term vocabulary cheat sheet (plus 2 rookie mistakes to avoid).

### 4.5 Module 5: Assisted Auto-Apply Browser
* **FR-5.1 (In-App WebView Form Filler):** Provide an embedded `flutter_inappwebview` browser that leverages the user's residential IP and authenticated mobile sessions to inject JavaScript and auto-populate standard application fields (Name, Email, Links, Custom Cover Letter, and local tailored PDF upload) on Greenhouse, Lever, Workday, LinkedIn, and Upwork while keeping the final "Submit" click under user confirmation.

---

## 5. Feature Prioritization Matrix (MoSCoW)

| Priority Tier | Feature Set | Acceptance Criteria for Play Store Launch |
| :--- | :--- | :--- |
| **P0 — Must Have (MVP Launch)** | Master CV Parser & Graph, Mission Control Dashboard, Country/Job/Freelance Filters, Multi-Source Scraper Engine, Chameleon CV Morphing Engine, Skill-Mimic Prep Dossier, White-Label OpenRouter Wallet (+$1/1M markup) + BYOK. | User can upload CV, select country + mode, connect BYOK or top up wallet, run search, view green bullet diffs, download tailored ATS PDF/DOCX, and study the generated interview defense script in `< 45 seconds` per listing. |
| **P1 — Should Have (v1.1 Fast Follow)** | Freelance Proposal & Milestone Writer, Assisted `InAppWebView` Auto-Applier, Audio Podcast Prep Mode (TTS briefing on the go). | Embedded browser auto-fills standard Greenhouse/Lever/Upwork fields and uploads the morphed PDF while keeping final "Submit" click under user confirmation. |
| **P2 — Could Have (v1.2 Expansion)** | Interactive AI Voice Mock Interviewer, Chrome/Desktop Companion Sync, Multi-Profile Agency Switcher. | Real-time voice simulation grilling the user specifically on the injected bullet points of a selected tailored CV. |

---

## 6. Non-Functional Requirements (NFRs)

1. **Latency & Streaming:** First token of live agent telemetry must reach the Flutter dashboard within `< 800ms` via WebSockets. Deterministic Typst PDF compilation must complete in `< 300ms` (total document storage & signed URL return `< 1.5s`).
2. **Offline Resilience:** Generated CVs (`.pdf` and `.docx`), bullet diffs, and Sensei Prep Dossiers must be cached locally in Flutter using Drift (SQLite) so candidates can review their interview defense scripts on airplanes or in low-connectivity environments before an interview.
3. **Play Store & Legal Compliance:** All store listings, onboarding flows, and UI copy position the product as an **"AI Career Optimization, Resume Role-Alignment & Technical Interview Upskilling Assistant."** Every generated AI artifact includes a 1-tap "Report / Flag AI Output" action and a mandatory user review confirmation gate prior to export/submission.