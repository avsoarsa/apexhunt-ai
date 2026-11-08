# Database Schema, API Contracts & Billing Ledger Specification: ApexHunt AI

**Primary Database:** PostgreSQL 16 + `pgvector` Extension  
**Local Offline Database (Flutter):** Drift (SQLite3) + `flutter_secure_storage` (Android Keystore)

---

## 1. Complete PostgreSQL DDL Schema

Run this migration script to initialize all relational tables, vector indexes, and financial audit ledgers:

```sql
-- Enable UUID and Vector extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";

-- 1. USERS & MASTER CAREER KNOWLEDGE GRAPH
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    base_cv_raw_text TEXT,
    master_knowledge_graph JSONB NOT NULL DEFAULT '{}'::jsonb, -- Verified companies, dates, degrees, base skills
    target_preferences JSONB NOT NULL DEFAULT '{}'::jsonb,     -- Default countries, salary/hourly floor, links
    background_check_safe_mode BOOLEAN NOT NULL DEFAULT TRUE,  -- Locks employer names & dates from modification
    cv_embedding vector(1536),                                 -- For semantic JD-to-CV pre-filtering
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. SUBSCRIPTION & WHITE-LABEL AI WALLET
CREATE TABLE user_wallets (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    subscription_tier TEXT NOT NULL DEFAULT 'FREE_TRIAL',      -- 'FREE_TRIAL', 'PRO_MONTHLY'
    subscription_status TEXT NOT NULL DEFAULT 'INACTIVE',      -- 'ACTIVE', 'GRACE_PERIOD', 'EXPIRED', 'INACTIVE'
    subscription_plan_id TEXT,                                 -- 'apex_monthly_399'
    subscription_expires_at TIMESTAMPTZ,
    credit_balance_usd NUMERIC(12, 6) NOT NULL DEFAULT 0.500000, -- Includes $0.50 welcome bonus
    preferred_routing_mode TEXT NOT NULL DEFAULT 'MANAGED_PROXY', -- 'MANAGED_PROXY' or 'BYOK'
    preferred_model_slug TEXT NOT NULL DEFAULT 'apex-pro',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. IMMUTABLE LLM TOKEN & +$1/1M MARKUP LEDGER
CREATE TABLE llm_usage_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mission_id UUID,
    execution_mode TEXT NOT NULL,                              -- 'MANAGED_PROXY' or 'BYOK'
    upstream_model_slug TEXT NOT NULL,                         -- e.g., 'anthropic/claude-3.7-sonnet'
    prompt_tokens INT NOT NULL,
    completion_tokens INT NOT NULL,
    upstream_openrouter_cost_usd NUMERIC(12, 6) NOT NULL DEFAULT 0,
    platform_markup_usd NUMERIC(12, 6) NOT NULL DEFAULT 0,     -- ((prompt + completion) / 1,000,000) * $1.00
    total_deducted_usd NUMERIC(12, 6) NOT NULL DEFAULT 0,      -- (upstream + markup) * 1.15 gateway buffer
    net_profit_usd NUMERIC(12, 6) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. AUTONOMOUS SEARCH MISSIONS
CREATE TABLE search_missions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    mission_mode TEXT NOT NULL,                                -- 'SALARIED_JOB' or 'FREELANCE_GIG'
    target_countries TEXT[] NOT NULL,                          -- e.g., '{US, GB, AE, IN, REMOTE}'
    commitment_types TEXT[] NOT NULL,                          -- e.g., '{FULL_TIME, PART_TIME, CONTRACT, HOURLY, FIXED_PRICE}'
    role_keywords TEXT[] NOT NULL,
    aggressiveness_level INT NOT NULL DEFAULT 3,               -- 1 (Conservative), 2 (Smart Bridge), 3 (Full Chameleon)
    status TEXT NOT NULL DEFAULT 'RUNNING',                    -- 'RUNNING', 'COMPLETED', 'FAILED', 'PAUSED'
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. DISCOVERED OPPORTUNITIES (SCRAPED JOBS & FREELANCE GIGS)
CREATE TABLE opportunities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mission_id UUID REFERENCES search_missions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_platform TEXT NOT NULL,                             -- 'LINKEDIN', 'INDEED', 'GREENHOUSE', 'UPWORK', 'MANUAL'
    external_url TEXT NOT NULL,
    title TEXT NOT NULL,
    company_or_client TEXT NOT NULL,
    country_code TEXT NOT NULL,
    compensation_text TEXT,
    raw_jd_text TEXT NOT NULL,
    extracted_keywords JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. TAILORED CV ARTIFACTS & FREELANCE PROPOSALS
CREATE TABLE tailored_artifacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mission_id UUID REFERENCES search_missions(id) ON DELETE CASCADE,
    opportunity_id UUID REFERENCES opportunities(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    job_title TEXT NOT NULL,
    company_or_client TEXT NOT NULL,
    country_code TEXT NOT NULL,
    source_url TEXT NOT NULL,
    raw_jd_text TEXT NOT NULL,
    base_ats_score NUMERIC(5,2) NOT NULL,
    final_ats_score NUMERIC(5,2) NOT NULL,
    tailored_cv_json JSONB NOT NULL,
    injected_skills_delta JSONB NOT NULL,                      -- Array of grafted skills, before/after bullets, and defense data
    freelance_proposal_md TEXT,                                -- Populated in FREELANCE_GIG mode
    pdf_download_url TEXT NOT NULL,
    docx_download_url TEXT NOT NULL,
    sensei_prep_dossier JSONB NOT NULL,                        -- Full STAR stories, 60s mental models & 5 Trap Q&As
    user_reviewed_confirmed BOOLEAN NOT NULL DEFAULT FALSE,    -- Mandatory Play Store confirmation gate
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. DEDICATED PREP DOSSIERS & MASTERY TRACKING
CREATE TABLE prep_dossiers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    artifact_id UUID NOT NULL REFERENCES tailored_artifacts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bridged_skill_narratives JSONB NOT NULL,
    mock_qa_pairs JSONB NOT NULL,
    mastery_status INT NOT NULL DEFAULT 0,                     -- 0 = Unstudied, 1 = In Progress, 2 = Mastered
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. AI CONTENT FLAGS (GOOGLE PLAY GENERATIVE AI POLICY COMPLIANCE)
CREATE TABLE ai_content_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    artifact_id UUID NOT NULL REFERENCES tailored_artifacts(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for fast lookup and vector search
CREATE INDEX idx_users_cv_embedding ON users USING ivfflat (cv_embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_missions_user_id ON search_missions(user_id);
CREATE INDEX idx_artifacts_user_id ON tailored_artifacts(user_id);
CREATE INDEX idx_ledger_user_id ON llm_usage_ledger(user_id);
```

---

## 2. REST & WebSocket API Contracts

| Method & Endpoint | Request Headers / Payload | Response & System Behavior |
| :--- | :--- | :--- |
| `GET /api/v1/llm/catalog` | `Authorization: Bearer <jwt>` | Returns white-labeled model catalog with OpenRouter branding stripped and `+$1.00/1M` token markup + `1.15` buffer pre-applied to display rates. |
| `POST /api/v1/profile/parse-cv` *(Alias: `/api/v1/profile/ingest`)* | `Multipart/Form-Data (file)` + Optional `X-BYOK-Key`, `X-BYOK-Base-URL` | Extracts text from PDF/DOCX, constructs `master_knowledge_graph` JSONB, and saves `cv_embedding`. |
| `POST /api/v1/missions/launch` *(Alias: `/api/v1/missions/start`)* | JSON: `mission_mode`, `target_countries[]`, `commitment_types[]`, `role_keywords[]`, `aggressiveness_level` | Enqueues Celery discovery + tailoring pipeline. Returns `mission_id` and WebSocket URL for live telemetry. |
| `WS /ws/v1/missions/{id}` *(Alias: `/ws/v1/missions/{id}/telemetry`)* | WebSocket Upgrade with JWT token | Streams real-time JSON events: `JOB_FOUND`, `GAP_DETECTED`, `SKILL_GRAFTED`, `PDF_READY`, `WALLET_UPDATED`. |
| `POST /api/v1/tailor/single-jd` | JSON: `raw_jd_text`, `mission_mode`, `aggressiveness_level` + Optional `X-BYOK-Key` | Immediate single-target execution: runs Gap Audit, Chameleon CV Rewrite, Typst PDF/DOCX compile, and Sensei Prep generation in one call. |
| `POST /api/v1/artifacts/{id}/regenerate` | JSON: `aggressiveness_level`, `disabled_skills[]` + Optional `X-BYOK-Key` | Re-runs Chameleon synthesis or re-compiles Typst PDF when a user toggles off a specific grafted bullet. |
| `GET /api/v1/artifacts/{id}/prep-dossier` | `Authorization: Bearer <jwt>` | Fetches the Sensei Defense Dossier (`bridged_skill_narratives` + `mock_qa_pairs`) and `mastery_status`. |
| `POST /api/v1/artifacts/{id}/flag` | JSON: `reason`, `notes` | Logs user report in `ai_content_flags` to satisfy Google Play Generative AI content reporting policy. |
| `DELETE /api/v1/users/me` | `Authorization: Bearer <jwt>` | Cascading hard delete of user account, Master CV graph, wallet, and R2/S3 files (Google Play Data Safety compliance). |
| `POST /api/v1/billing/webhook` | RevenueCat / Razorpay HMAC Signature | Processes `INITIAL_PURCHASE`, `RENEWAL` (sets `subscription_status = 'ACTIVE'`), and `NON_RENEWING_PURCHASE` (increments `credit_balance_usd`). |

---

## 3. Canonical JSON Schemas

### 3.1 `master_knowledge_graph` Schema
```json
{
  "candidate_name": "Alex Rivera",
  "contact": {
    "email": "alex@example.com",
    "phone": "+1-555-0192",
    "location": "London, UK",
    "linkedin": "linkedin.com/in/alexrivera",
    "github": "github.com/alexrivera",
    "portfolio": "alexrivera.dev"
  },
  "locked_work_history": [
    {
      "role_id": "role_1",
      "company": "TechNova Solutions",
      "title": "Backend Engineer",
      "start_date": "2023-02",
      "end_date": "PRESENT",
      "is_locked_anchor": true,
      "base_bullets": [
        "Built REST APIs in Node.js for order processing and database updates.",
        "Maintained PostgreSQL schemas and reduced query latency by 25%."
      ]
    }
  ],
  "education": [
    {
      "institution": "University of Manchester",
      "degree": "B.Sc. in Computer Science",
      "graduation_year": 2022,
      "is_locked_anchor": true
    }
  ],
  "verified_skills": ["Node.js", "TypeScript", "PostgreSQL", "Docker", "REST APIs", "Git"]
}
```

### 3.2 `injected_skills_delta` & `sensei_prep_dossier` Payload Schema
```json
{
  "artifact_id": "9f8c2b10-44a1-4e9b-8a1d-32891c7b90e1",
  "base_ats_score": 54.0,
  "final_ats_score": 97.5,
  "injected_skills_delta": [
    {
      "skill_name": "Apache Kafka & Event-Driven Microservices",
      "jd_importance": "MANDATORY",
      "grafted_into_role": "Backend Engineer @ TechNova Solutions (2023-02 - PRESENT)",
      "original_bullet": "Built REST APIs in Node.js for order processing and database updates.",
      "morphed_bullet": "Architected high-throughput event-driven order pipelines using Apache Kafka and Node.js with idempotent consumers and dead-letter queues, reducing peak checkout latency by 42%.",
      "sensei_defense": {
        "sixty_second_mental_model": "Kafka is a distributed commit log where producers write events to partitioned topics and consumer groups read them asynchronously without tight coupling.",
        "star_story_script": "At TechNova, synchronous REST calls were timing out during flash sales. I introduced a 3-broker Kafka cluster partitioned by `merchant_id` so order events were ingested in under 15ms and processed asynchronously by inventory workers. When a poison-pill payload caused consumer lag, I implemented a dead-letter queue with exponential backoff...",
        "trap_questions": [
          {
            "question": "How did you prevent duplicate order processing when a Kafka consumer crashed mid-batch?",
            "golden_answer": "We disabled auto-commit and committed offsets manually only after writing the order state and event `idempotency_key` inside a single atomic PostgreSQL transaction."
          }
        ],
        "vocabulary_cheat_sheet": {
          "terms_to_drop": ["Consumer Group Rebalancing", "Idempotent Producer", "Dead-Letter Queue (DLQ)", "Partition Key Skew", "Manual Offset Commit"],
          "rookie_mistakes_to_avoid": [
            "Never say you stored large binary PDFs directly inside Kafka messages.",
            "Don't claim you used random partition keys if order sequence per merchant mattered."
          ]
        }
      }
    }
  ]
}
```