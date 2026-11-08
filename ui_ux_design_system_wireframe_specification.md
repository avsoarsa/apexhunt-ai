# Flutter UI/UX Design System & Screen Specification: ApexHunt AI

**Design Language:** Material 3 Adaptive ("Cyber-Executive" Dark & Light Themes)  
**Navigation Pattern:** 5-Tab Persistent `NavigationBar` + Expandable Modal Bottom Sheets

---

## 1. Visual Identity & Design System Tokens

The Flutter interface combines high-trust executive typography with live autonomous telemetry visuals. It avoids horizontal scrolling tables on mobile screens by using progressive disclosure cards, radial/linear ATS confidence gauges, and color-coded inline diff pills.

### 1.1 Color Palette Tokens
| Token Name | Hex Code | Usage in Flutter UI |
| :--- | :--- | :--- |
| `surfaceObsidian` (Dark Primary) | `#0F172A` | Primary background in Dark Mode, top app bar, and telemetry console surface. |
| `surfaceSlateCard` | `#1E293B` | Elevated Bento cards, opportunity pipeline cards, and modal sheets. |
| `accentElectricCobalt` | `#2563EB` | Primary CTA buttons ("Deploy Autonomous Agent"), active tab indicators, selected filter chips. |
| `chameleonEmerald` | `#10B981` | Highlights for newly injected skills (`+ Injected Skill`), rewritten CV diff spans, and `95%+` ATS badges. |
| `senseiAmberAlert` | `#F59E0B` | Unstudied Skill-Mimic Dojo cards ("3 Injected Skills to Master Before Your Call") and wallet low-balance alerts. |
| `dangerRose` | `#EF4444` | Removed/replaced original weak CV bullets in the Diff Viewer and error states. |

### 1.2 Typography Tokens
* **Display & Metric Headings (`Plus Jakarta Sans`, Bold/ExtraBold):** Used for screen titles, ATS match percentages (`97.5%`), and Bento dashboard counters.
* **Body & Dense Resume Prose (`Inter`, Regular/Medium/SemiBold):** Used for CV bullet diffs, freelance proposals, and Sensei STAR study narratives.
* **Telemetry & Key Masks (`JetBrains Mono`, Regular):** Used for the live WebSocket agent terminal logs, token usage counters, and masked BYOK API keys.

---

## 2. 5-Tab Navigation Architecture & Route Inventory

| Route / Tab | Screen Name | Primary Flutter Widgets | Key User Actions & State Bindings |
| :--- | :--- | :--- | :--- |
| `/onboarding` | **Onboarding & Base CV Ingest** | `FilePicker`, `LinearProgressIndicator`, `ChipList`, `SwitchListTile` | Upload existing PDF/DOCX CV, inspect extracted Master Knowledge Graph cards, lock employer/date anchors. |
| `/dashboard` *(Tab 1)* | **Command Center (Dashboard)** | `SegmentedButton`, `FilterChip`, `Slider`, `BentoGrid`, `TelemetryTerminal` | Switch Salaried Job vs. Freelance mode, pick countries, toggle Full/Part-time, set Aggressiveness (1–3), launch agent. |
| `/pipeline` *(Tab 2)* | **Live Agent Feed (Pipeline Queue)** | `Dismissible` Cards, `RichText` Diff Highlighter, `CircularProgressIndicator` | Browse discovered jobs/gigs, see `Before 54% -> After 97%` ATS boost, expand green-highlighted injected skills. |
| `/vault` *(Tab 3)* | **Chameleon CV & Bid Vault** | `PdfViewer` (`pdfrx`), `TabBarView` (CV vs. Proposal), `SharePlus`, `IconButton` | Preview compiled single-column ATS PDF & freelance proposal, inline-edit bullets, flag AI output, export or auto-apply. |
| `/dojo` *(Tab 4)* | **Skill-Mimic Dojo (Prep Center)** | `ExpansionTile`, Flip Flashcards, STAR Script Reader, TTS Audio Player | Study the 60s mental model, personal STAR project story, 5 Trap Q&As, and vocabulary list for every grafted skill. |
| `/settings` *(Tab 5)* | **Master Profile, AI Brain & Billing** | Model Picker Dropdown, RevenueCat Paywall, BYOK Key Vault, Account Delete | Manage `$3.99/mo` subscription, top up Managed Wallet (`+$5/$10/$25`), configure BYOK key, or wipe account data. |

---

## 3. Detailed Screen-by-Screen Wireframe Specifications

### 3.1 Tab 1: Mission Control Dashboard (`/dashboard`)
```text
+-------------------------------------------------------------------+
| [Avatar] Base CV: Synced ✓          [⚡ Apex Pro • $4.82] [⚙️]    |
+-------------------------------------------------------------------+
|  [ 💼 Salaried Job Search (Active) ]  [ 🚀 Freelance Project ]    |
|                                                                   |
|  TARGET COUNTRIES                                                 |
|  (🌐 Remote) (🇺🇸 USA) (🇬🇧 UK) (🇦🇪 UAE) (🇩🇪 DE) (🇮🇳 IN) (+ Add)    |
|                                                                   |
|  WORK TYPE & COMMITMENT                                           |
|  [x] Full-Time   [x] Part-Time   [ ] Contract   [ ] Visa Sponsor  |
|                                                                   |
|  TARGET ROLES / KEYWORDS                   [📋 Paste Single JD]   |
|  [ Flutter Dev x ] [ AI Engineer x ] [ Full-Stack x ]             |
|                                                                   |
|  CHAMELEON SKILL-MIMIC AGGRESSIVENESS: Level 3 (Full Chameleon)   |
|  Conservative o----------------o================● Full Mimicry    |
|                                                                   |
|  +-------------------------------------------------------------+  |
|  |           🚀 DEPLOY AUTONOMOUS AGENT MISSION                |  |
|  +-------------------------------------------------------------+  |
|                                                                   |
|  LIVE AGENT TELEMETRY (WebSocket Stream)                          |
|  > [00:02] Scanning 38 roles in UK, UAE & Remote...               |
|  > [00:06] Match: Senior Mobile Lead @ FinTech Co (Base: 54%)     |
|  > [00:09] Gap Found: 'GraphQL' & 'Fastlane CI' missing on CV     |
|  > [00:14] Grafting into 2024 E-Commerce role... ATS Score: 98%!  |
|                                                                   |
|  METRICS BENTO GRID                                               |
|  +---------------+ +---------------+ +---------------+ +-------+  |
|  | 42 Scanned    | | 11 CVs Ready  | | 96.8% Avg ATS | | 4 Sent|  |
|  +---------------+ +---------------+ +---------------+ +-------+  |
+-------------------------------------------------------------------+
|  [1: Command]  [2: Pipeline]  [3: CV Vault]  [4: Dojo]  [5: AI]   |
+-------------------------------------------------------------------+
```

### 3.2 Tab 2: Opportunity Card & Interactive CV Diff Viewer (`/pipeline`)
Tapping any opportunity card opens a full-height modal sheet with three sub-tabs:
1. **Sub-Tab A — Visual CV Diff:**
   * Displays each modified work experience entry.
   * **Original Bullet (Muted Strikethrough):** *"Built REST APIs in Node.js for order processing and database updates."*
   * **Morphed Chameleon Bullet (Emerald Highlight):** *"Architected high-throughput event-driven order pipelines using **Apache Kafka** and Node.js with **idempotent consumers** and **dead-letter queues**, reducing peak checkout latency by 42%."*
   * **Skill Pills:** `[+ Injected: Apache Kafka]` `[+ Injected: Event-Driven Microservices]` with an individual switch to accept or revert each bullet.
2. **Sub-Tab B — ATS & JD Requirement Checklist:**
   * Displays all 15–25 skills extracted from the JD with green checkmarks showing the exact CV section where each requirement is now satisfied.
3. **Sub-Tab C — Direct Sensei Dojo Bridge:**
   * Amber callout banner: *"⚠️ 3 new skills were grafted onto this CV. Tap here to complete your 10-minute Sensei Defense Briefing before your interview."*

### 3.3 Tab 3: Chameleon CV Vault & Assisted Apply (`/vault`)
* **Top Switcher:** Toggle between **Tailored ATS Resume (PDF)** and **Freelance Bid Proposal (Markdown/Copy)** (when in Freelance Mode).
* **Native 60fps PDF Preview (`pdfrx`):** Displays the single-column Typst-compiled PDF (`FirstName_LastName_Company_Role.pdf`).
* **Play Store Compliance Bar:** Includes a 1-tap `🚩 Report / Flag AI Output` icon and the mandatory confirmation checkbox: `[x] I have reviewed this AI-tailored draft and prepared with the companion study guide.`
* **Action Bar:** `[📥 Download PDF]` `[📄 Export DOCX]` `[📤 Share via WhatsApp/Email]` `[⚡ Launch Assisted Auto-Apply]`.

### 3.4 Tab 4: Skill-Mimic Dojo (`/dojo`)
* Organizes prep decks by target job/client.
* Each grafted skill card expands into four structured learning panels:
  1. **⏱️ 60-Second Mental Model:** Plain-English architectural overview.
  2. **🗣️ Your Personal Project STAR Story ("How You Used It"):** First-person script anchored to the exact company on the user's CV where the skill was grafted, including the production bug story. Includes a **[🔊 Listen in Audio Mode]** TTS button.
  3. **🎯 Top Interview Trap Questions (Interactive Flip Cards):** Question on front, senior-level trade-off answer on back.
  4. **🧠 Rapid Vocabulary Cheat Sheet:** 5 pro terms to drop naturally + 2 rookie phrases to avoid, followed by a `[✓ Mark Skill as Mastered]` button that updates `mastery_status`.

### 3.5 Modal Sheet: White-Labeled AI Brain & BYOK Hub
* **Zero OpenRouter Branding in Managed Mode:** When **Tab A: Managed Apex Cloud** is active, users see their `credit_balance_usd`, quick top-up packs (`+$5`, `+$10`, `+$25`), and white-labeled engines (*Apex Flash ~$0.01/CV*, *Apex Pro ~$0.03/CV*, *Apex Elite ~$0.06/CV*) plus a curated model dropdown with the `+$1.00/1M` token markup already baked into the displayed estimate.
* **Tab B: Bring Your Own API Key (BYOK):** Unlocked for active `$3.99/mo` base subscribers. Includes Provider Dropdown (`OpenRouter`, `OpenAI`, `Anthropic`, `Google Gemini`, `Groq`, `Custom OpenAI-Compatible URL`), masked password input, model slug input, and **"Verify & Save to Android Keystore"** CTA.