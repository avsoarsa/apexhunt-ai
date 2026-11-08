# QA test plan: ApexHunt AI v1.0

File every finding as a GitHub issue (Bug report / Improvement template) with a severity label.

## Devices
At least one of each: a recent Pixel/Samsung (Android 14–16), a budget phone with 3–4 GB RAM (Android 10–12), and a small screen (≤ 5.8"). Also check large font (Settings → Display → Font size max) and dark/light system themes.

## 1. Install & onboarding
- [ ] Fresh install → welcome → "Get started" → AI step → CV step → review → dashboard.
- [ ] BYOK with a free Gemini key: "Test connection" works; a wrong key gives a clear error; a key with spaces is trimmed.
- [ ] BYOK: OpenAI / Anthropic / Groq / OpenRouter / custom Ollama URL on LAN.
- [ ] Managed (once the gateway is live): email code arrives within 1 min, wrong code is rejected, $0.50 welcome credit shows.
- [ ] CV import: text PDF, 2-column designer PDF, DOCX with bullets, TXT, **scanned PDF** (should ask to paste text), 10-page CV, non-English characters in name.
- [ ] "Skip for now" → basic offline import still lands on a usable profile.
- [ ] Kill the app mid-onboarding → reopen → sensible state.

## 2. Profile editor
- [ ] Edit/add/remove roles, bullets (one per line), skills, education, projects; Save persists across restarts.
- [ ] Re-import CV replaces the profile but keeps Vault entries.

## 3. Command (discovery)
- [ ] Jobs mode, Remote only: results from Remotive / Jobicy / Remote OK appear, ranked, with "via <source>".
- [ ] Countries: US, UK, UAE, DE, IN individually; results respect location (spot-check 10 listings).
- [ ] Freelance mode → Freelancer.com projects with budget + hourly/fixed.
- [ ] Watched boards: `greenhouse:stripe`, `lever:netflix` (or any live company); a misspelled slug doesn't break the mission.
- [ ] Airplane mode during a mission → per-source "unavailable" lines, no crash.
- [ ] "Paste a JD" with a short text is rejected; a full JD opens Tailor.

## 4. Tailor flow (core)
- [ ] Analyze → check-in lists requirements; "Backed by your CV" is correct.
- [ ] "I have it" requires a context line; that skill is saved to the profile (visible in the editor).
- [ ] **Truth Guard adversarial:** take a JD full of skills you don't have (e.g. Kubernetes, Kafka, Rust) and mark them "Don't have" → the tailored CV must not mention them anywhere (bullets, skills, summary, headline). Try 5 different JDs and 2 engines.
- [ ] Invented numbers: no metric appears that isn't in your original CV.
- [ ] Company names, titles, dates and education are identical to the profile.
- [ ] ATS before → after is plausible. "Requirements" tab matches reality.
- [ ] Out of credits / no key / network drop mid-run → clear message, no half-saved junk.
- [ ] Snippet-only listings (Adzuna/Jooble) prompt to paste the full description.

## 5. Vault & documents
- [ ] PDF preview renders; toggling a bullet off updates the PDF and the ATS score.
- [ ] Editing a bullet clears its review tick.
- [ ] Share PDF / DOCX blocked until "I have reviewed…" is ticked; after that it opens the share sheet (Gmail, WhatsApp, Drive).
- [ ] **ATS parse check:** upload 5 generated PDFs + DOCX to real parsers (a Greenhouse/Lever test application, Jobscan, Affinda demo). Name, contact, roles, dates and bullets must extract correctly.
- [ ] DOCX opens in Word, Google Docs and WPS without warnings.
- [ ] File names follow `First_Last_Company_Role.pdf`.
- [ ] Cover letter / proposal: copy, share, Report AI output.

## 6. Prep Dojo
- [ ] STAR stories come only from real experience; placeholders like "[your detail]" where facts are missing.
- [ ] Gap plans exist for every "Don't have"/"Learning" skill, with an honest answer script.
- [ ] Flip cards, Listen (TTS) start/stop, Mark mastered persists; works offline.

## 7. Settings, billing & compliance
- [ ] Engine tiers show cost per application; Apex Elite locked for free users.
- [ ] License-tester purchase of Pro → Pro unlocks in under 10 s; restore purchases on a reinstall.
- [ ] Credit pack → wallet increases once (no double credit after reopening).
- [ ] Report AI output from CV, letter and prep → row appears in `apexhunt.ai_content_flags`.
- [ ] Delete account & wipe data → server rows gone, Supabase user gone, app back to onboarding, BYOK key removed.
- [ ] Privacy, terms and delete-account pages open from Settings.

## 8. Gateway / backend
- [ ] `/health` reports models > 0; catalog never contains the word "OpenRouter".
- [ ] Ledger math: run 10 tailors, then compare `llm_usage_ledger` totals with OpenRouter's activity page (charge = (upstream + tokens×$0.000001)×1.15).
- [ ] Rate limit (30/min) returns 429 with a friendly message.
- [ ] Supabase: the `apexhunt` schema is not reachable with the anon key (RLS + non-exposed schema).
- [ ] Webhook with a wrong Authorization header → 401.

## 9. Non-functional
- [ ] Cold start under 3 s on a mid-range phone; no jank scrolling the Pipeline with 200+ items.
- [ ] Memory stays stable after 10 tailors (no leaks from PDF previews).
- [ ] TalkBack can complete onboarding and one tailor flow.
- [ ] Play Console **pre-launch report** has no crashes/ANRs; review its accessibility and security warnings.
