# System Architecture & Technical Stack Specification: ApexHunt AI

**Frontend:** Flutter 3.x (Dart 3, Feature-First Clean Architecture, Riverpod 2.x)  
**Backend:** Python 3.11+ (FastAPI, Uvicorn, Celery, Redis, LangGraph, Pydantic v2)  
**Document Engine:** Typst CLI (Primary ATS PDF Compiler) + `python-docx` (Word Compiler)  
**Database & Storage:** PostgreSQL 16 + `pgvector`, Cloudflare R2 / AWS S3

---

## 1. End-to-End Architectural Topology

ApexHunt AI uses a **Decoupled Hybrid Edge + Cloud Agent Architecture** to keep the Flutter Android client fast, battery-efficient, and immune to IP bans during heavy scraping:

| System Tier | Core Technologies | Architectural Responsibility |
| :--- | :--- | :--- |
| **Mobile Client Layer** | Flutter (Dart 3), Riverpod 2.x, GoRouter, Dio, Drift (SQLite), `flutter_secure_storage`, `pdfrx`, `flutter_inappwebview` | Renders Mission Control UI, streams real-time agent WebSocket logs, caches tailored PDFs and Prep Dossiers offline, encrypts user BYOK API keys in Android Keystore, and runs assisted WebView form filling. |
| **Optional On-Device Edge Layer** | Optional LiteRT / Local Gemma or Ollama over Tailscale/LAN | Handles lightweight local keyword highlighting, PII masking, offline study dossier review, or custom local LLM inference via BYOK custom base URL. |
| **API & Billing Gateway** | Python FastAPI, Uvicorn, Redis, RevenueCat Webhook Listener, Razorpay / Stripe | Authenticates users (Firebase/Supabase JWT), verifies active `$3.99/mo` base subscription status, enforces token wallet balances, and routes LLM calls via the White-Label OpenRouter Proxy or BYOK pass-through. |
| **Agent Orchestration Engine** | LangGraph (Stateful DAG), Celery Distributed Workers, Pydantic v2 Structured Outputs | Executes deterministic 5-node cyclic state machines: `Scout/Auditor` $\rightarrow$ `ChameleonGrafter` $\rightarrow$ `ATSGatekeeper` $\rightarrow$ `FreelanceCloser` $\rightarrow$ `SenseiPrepBuilder`. |
| **Discovery & Scraping Layer** | Crawl4AI, Playwright Stealth, JobSpy, Upwork/Freelancer RSS & API Bridges, Rotating Residential Proxies | Queries country-specific job boards and freelance marketplaces concurrently, bypasses anti-bot protections, normalizes messy HTML into clean Markdown, and deduplicates listings. |
| **Document Compilation & Storage** | Typst CLI (Primary) or LaTeX/Jinja2 + `python-docx`, Cloudflare R2 / AWS S3, PostgreSQL 16 + `pgvector` | Compiles structured JSON resumes into single-column ATS-compliant PDFs in `< 300ms` and stores versioned artifacts alongside `vector(1536)` semantic embeddings. |

---

## 2. Flutter Client Architecture (Feature-First Clean Architecture)

Because it is built in **Flutter**, the single codebase compiles natively to **Android (`.aab` for Google Play Store)**, **iOS**, and **Desktop/Web**. Each feature module is strictly separated into `presentation` (Widgets), `application` (Riverpod Notifiers), `domain` (Freezed immutable entities), and `data` (Dio remote repositories + Drift local SQLite DAOs).

### 2.1 Complete Flutter Directory Structure
```text
lib/
├── core/
│   ├── network/          # Dio client, AuthInterceptor, BYOKHeaderInterceptor, WebSocketManager
│   ├── security/         # SecureKeyVault (flutter_secure_storage wrapper for OpenRouter/LLM keys)
│   ├── billing/          # RevenueCat (purchases_flutter) & WalletBalanceController
│   ├── database/         # Drift (SQLite) tables for offline CVs, Diffs, and Sensei Prep Dossiers
│   └── theme/            # Material 3 Dark/Light "Cyber-Executive" Theme tokens
├── features/
│   ├── master_profile/   # Base CV upload, Master Knowledge Graph viewer & Background-Check lock toggles
│   ├── mission_control/  # Country chips, Job vs. Freelance switch, Aggressiveness slider, Live Telemetry
│   ├── pipeline_feed/    # Kanban/Swipeable matched opportunities, ATS score boost gauge, Diff viewer
│   ├── llm_gateway/      # White-label Apex Engine selector + BYOK Custom Provider modal sheet
│   ├── cv_vault/         # Side-by-side Diff Viewer, native PDF previewer (pdfrx), DOCX share sheet
│   ├── skill_dojo/       # Injected skill flashcards, STAR stories, 5 Trap Q&A defense scripts, TTS audio
│   └── auto_apply/       # InAppWebView with JS injection for Greenhouse, Lever, Workday & Upwork
└── main.dart
```

### 2.2 Mandatory `pubspec.yaml` Dependencies
| Category | Package Name | Implementation Role |
| :--- | :--- | :--- |
| **State Management** | `flutter_riverpod`, `riverpod_annotation` | Reactive state management for WebSocket agent streams, wallet balances, and filter states. |
| **Routing & Models** | `go_router`, `freezed_annotation`, `json_serializable` | Declarative deep-linkable navigation (5-tab shell) and immutable JSON data classes. |
| **Networking & Streaming** | `dio`, `web_socket_channel`, `eventsource` | REST API calls, custom BYOK header injection, WebSocket mission telemetry, and SSE streaming. |
| **Hardware Key Security** | `flutter_secure_storage` | Encrypts user-supplied OpenRouter/OpenAI/Anthropic/Gemini API keys inside Android Keystore (`AES-256-GCM`). |
| **Local Offline Cache** | `drift`, `sqlite3_flutter_libs`, `path_provider` | Offline SQLite persistence of generated CVs, proposals, and Sensei study decks. |
| **PDF & File Handling** | `pdfrx` (or `syncfusion_flutter_pdfviewer`), `file_picker`, `share_plus` | 60fps native PDF rendering inside the Vault tab, base CV upload, and 1-tap export to WhatsApp/Email/LinkedIn. |
| **Assisted Auto-Applier** | `flutter_inappwebview` | Injects JavaScript into job portals (Greenhouse, Lever, Workday, Upwork) to auto-fill forms and upload tailored CVs. |
| **Monetization & Billing** | `purchases_flutter` (RevenueCat) + Razorpay/Stripe | Manages the `$3.99/mo` base subscription and consumable `$5 / $10 / $25` AI Credit Packs on Google Play. |

---

## 3. White-Labeled OpenRouter Proxy & `+$1.00/1M` Markup Engine

To guarantee users never see OpenRouter branding in Managed Mode while giving them access to elite models and protecting platform unit economics, the FastAPI backend operates as a **Metered LLM Gateway**.

### 3.1 Dynamic Model Catalog Sync (`/api/v1/llm/catalog`)
1. Every 6 hours, a Celery Beat task calls `GET https://openrouter.ai/api/v1/models`.
2. The backend strips all OpenRouter references, maps top models to branded tiers (**Apex Flash / Eco**, **Apex Pro / Balanced**, **Apex Elite Chameleon**), and filters a curated list of the top 12 best-performing CV/proposal models (e.g., Claude 3.7/4.5 Sonnet, GPT-4o, DeepSeek V3/R1, Qwen Max, Gemini 2.5 Flash).
3. For every model, the backend transforms upstream per-token USD rates by adding **`+$0.000001` per token (`+$1.00` per 1,000,000 tokens)** to both `prompt` and `completion` rates and multiplying by the `1.15` gateway fee buffer before returning the catalog JSON to Flutter.

### 3.2 Production FastAPI Token Metering & BYOK Middleware
```python
from decimal import Decimal
from fastapi import Header, HTTPException

MARKUP_PER_TOKEN = Decimal("0.000001")  # Exactly +$1.00 per 1,000,000 tokens
GATEWAY_BUFFER = Decimal("1.15")        # 15% buffer to absorb Google Play Billing fees

async def execute_llm_step(
    user_id: str,
    mission_id: str | None,
    model_slug: str,
    messages: list[dict],
    x_byok_key: str | None = Header(default=None, alias="X-BYOK-Key"),
    x_byok_base_url: str | None = Header(default="https://openrouter.ai/api/v1", alias="X-BYOK-Base-URL")
) -> str:
    # 1. Verify active base subscription ($3.99/mo) for ALL users (Managed & BYOK)
    wallet = await db.get_user_wallet(user_id)
    if wallet.subscription_status not in ("ACTIVE", "GRACE_PERIOD"):
        raise HTTPException(status_code=402, detail="Active base subscription ($3.99/mo) required.")

    # 2. Track B: User supplied their own API key (BYOK Mode) -> $0.00 platform token cost
    if x_byok_key:
        response = await call_openai_compatible_provider(
            base_url=x_byok_base_url,
            api_key=x_byok_key,
            model=model_slug,
            messages=messages
        )
        await db.log_llm_ledger(
            user_id=user_id,
            mission_id=mission_id,
            execution_mode="BYOK",
            upstream_model_slug=model_slug,
            prompt_tokens=response.usage.prompt_tokens,
            completion_tokens=response.usage.completion_tokens,
            upstream_openrouter_cost_usd=Decimal("0"),
            platform_markup_usd=Decimal("0"),
            total_deducted_usd=Decimal("0")
        )
        return response.content

    # 3. Track A: Managed White-Label Proxy -> Enforce minimum wallet balance ($0.02)
    if wallet.credit_balance_usd <= Decimal("0.020000"):
        raise HTTPException(status_code=402, detail="Insufficient Apex AI Credits. Please top up wallet.")

    # Execute via Master OpenRouter Key
    response = await call_openrouter_master(model=model_slug, messages=messages)
    prompt_tokens = response.usage.prompt_tokens
    completion_tokens = response.usage.completion_tokens
    total_tokens = Decimal(prompt_tokens + completion_tokens)
    upstream_cost = Decimal(str(response.usage.total_cost_usd))

    # Calculate +$1.00 per 1M tokens markup + 15% Google Play gateway buffer
    platform_markup = total_tokens * MARKUP_PER_TOKEN
    total_user_charge = (upstream_cost + platform_markup) * GATEWAY_BUFFER

    # Atomically decrement PostgreSQL user_wallets.credit_balance_usd & append to llm_usage_ledger
    await db.deduct_wallet_and_log_ledger(
        user_id=user_id,
        mission_id=mission_id,
        execution_mode="MANAGED_PROXY",
        upstream_model_slug=model_slug,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        upstream_openrouter_cost_usd=upstream_cost,
        platform_markup_usd=platform_markup,
        total_deducted_usd=total_user_charge
    )
    return response.content
```

---

## 4. Multi-Source Discovery & Semantic Pre-Filter Pipeline

1. **Salaried Job Connectors:** Country-localized adapters across LinkedIn Jobs, Indeed (`indeed.com`, `indeed.co.uk`, `indeed.ae`, `in.indeed.com`, `de.indeed.com`), Glassdoor, Wellfound, RemoteOK, and direct ATS feeds (Greenhouse, Lever, Ashby, Workday) filtered by `target_countries`, `remote_status`, and `commitment_types` (`FULL_TIME`, `PART_TIME`, `CONTRACT`).
2. **Freelance Project Connectors:** Queries Upwork RSS/API feeds, Freelancer.com Active Projects API, PeoplePerHour, Toptal public boards, and LinkedIn hiring posts (`"looking for a freelance" AND [skill]`). Extracts client budget, hourly vs. fixed-price terms, client country, and required deliverables.
3. **Semantic `pgvector` Pre-Filter:** Before invoking multi-node LLM tailoring, the backend computes cosine similarity between `users.cv_embedding` (`vector(1536)`) and scraped listings, queuing the highest-value matches for the LangGraph Chameleon pipeline.

---

## 5. Sub-Second ATS Document Compilation Engine (Typst + DOCX)

Legacy ATS parsers (Workday, Taleo, Greenhouse, Sovren, Affinda) frequently fail on multi-column CSS/HTML PDFs, canvas elements, tables, or icon fonts. ApexHunt AI guarantees **100% ATS parseability**:
1. The LangGraph Chameleon node outputs strictly validated JSON conforming to `TailoredCVOutputSchema`.
2. The backend injects the JSON into a single-column **Typst** template (primary) or LaTeX/Jinja2 template and compiles a crisp PDF in memory in **< 250–400ms**.
3. Simultaneously, a matching **`python-docx`** pipeline compiles an editable Word `.docx` artifact.
4. Both files (`FirstName_LastName_Company_Role.pdf` and `.docx`) are uploaded to Cloudflare R2 / S3 with signed URLs and pushed via WebSocket (`PDF_READY`) to the Flutter client.