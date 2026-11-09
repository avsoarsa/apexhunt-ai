# ApexHunt AI: from zero to Google Play production

Budget about 2–3 hours of setup, then a mandatory 14-day closed test if your Play developer account is a new personal account.

## 0. Accounts you need

| Service | Why | Cost |
|---|---|---|
| Google Play Console | Publish the app | $25 one-time |
| Supabase | Sign-in (email code) + Postgres for wallets/ledger | Free tier |
| OpenRouter | Upstream models behind "Apex" engines | Prepaid credits (start with $10–20) |
| Render (or Railway/Fly) | Hosts the gateway | Starter ≈ $7/mo (free tier sleeps → slow first request) |
| RevenueCat | Google Play Billing, subscription status, webhooks | Free up to $2.5k monthly revenue |
| Resend / any SMTP | Sends sign-in codes. Supabase's built-in mailer allows only a few emails per hour | Free tier |
| Adzuna, Jooble (optional) | More job listings by country | Free API keys |
| GitHub | Code + cloud builds of the signed .aab | Free |

## 1. Supabase

1. Create a project (pick the region closest to most users, e.g. Mumbai).
2. **SQL Editor** → paste `gateway/schema.sql` → Run. Run it again whenever an update changes `schema.sql`, *before* deploying that gateway version (it's safe to re-run, and the new code expects the new tables).
3. **Authentication → Sign In / Providers → Email**: enabled. Turn **Confirm email** on.
4. **Authentication → Emails → Templates**: in both *Magic Link* and *Confirm signup*, make the body show the code: `Your ApexHunt code is {{ .Token }}`. The app signs in with the 6-digit code, not the link.
5. **Authentication → Emails → SMTP Settings**: plug in Resend (or similar) and send from your own domain, or a free `onboarding@resend.dev` sender while testing.
6. Collect:
   - Project URL → `SUPABASE_URL` (app + gateway)
   - **Publishable key** (`sb_publishable_…`) → app `SUPABASE_ANON_KEY`
   - **Secret / service_role key** → gateway `SUPABASE_SERVICE_ROLE_KEY` only. Never put it in the app.
   - **Connect → Session pooler** URI → gateway `DATABASE_URL`
   - Only on legacy projects using HS256: **JWT secret** → gateway `SUPABASE_JWT_SECRET`. Newer projects use signing keys, and the gateway reads them from JWKS automatically.

## 2. OpenRouter

1. Create an API key and buy credits.
2. Set a **monthly spending limit** on the key. It caps your downside if something goes wrong.
3. Key → gateway `OPENROUTER_API_KEY`.

Tier → model mapping lives in `gateway/app/config.py` (`TIER_*_MODELS`). Each tier lists fallbacks, and the first model present in the live catalog wins. Override with env vars whenever better or cheaper models ship.

## 3. Deploy the gateway (Render)

1. Push this repo to GitHub (private is fine).
2. Render → **New → Blueprint** → select the repo. `render.yaml` (repo root) creates `apexhunt-gateway` from `apexhunt/gateway`.
3. Fill the env vars (see `gateway/.env.example`). Set `PUBLIC_BASE_URL` to the Render URL.
4. Check that `https://<your-app>.onrender.com/health` returns `"ok": true` with `models > 0`.
5. Open `/privacy`, `/terms` and `/delete-account`. Play Console needs the first and last URLs.

## 4. Google Play Console: create the app

1. **Create app** → name "ApexHunt AI", App, Free, accept policies.
2. **Test and release → Setup → App signing**: use Google-managed signing (Play App Signing).
3. Upload the first bundle to **Internal testing** (see §6). Play only unlocks product creation after a bundle with the billing permission is uploaded. RevenueCat's SDK adds that permission.
4. **Monetize → Products**:
   - **Subscriptions** → create `apex_pro` → base plan `monthly`, auto-renewing, **$3.99**. Add `yearly` ($29.99) if you like. Set local prices; Play suggests conversions. Consider ₹249/month for India.
   - **In-app products** → `apex_credits_5`, `apex_credits_10`, `apex_credits_25` at $4.99 / $9.99 / $24.99. Don't price credit packs below their USD credit value in any country, or you lose money on every AI call. Discount the subscription instead.
5. **Setup → License testing**: add your Gmail plus your testers. Their purchases are free test purchases.

## 5. RevenueCat

1. New project → **Add app → Google Play** → package `com.apexhunt.ai`.
2. Upload **service account credentials**: follow RevenueCat's "Google Play service credentials" guide. It creates a Google Cloud service account and grants it access in Play Console → Users & permissions. Allow up to 36 h to propagate.
3. **Products**: import `apex_pro:monthly` (+ `:yearly`) and the three credit packs.
4. **Entitlements**: create `pro`, attach the subscription products only.
5. **Offerings**: `default` → packages `$rc_monthly` → `apex_pro:monthly`, `$rc_annual` → `apex_pro:yearly`. Credit packs are fetched by product ID and don't need an offering.
6. **Integrations → Webhooks**: URL `https://<gateway>/api/v1/billing/revenuecat`. Set the Authorization header value to exactly the gateway's `REVENUECAT_WEBHOOK_AUTH`.
7. **API keys**: Google public key (`goog_…`) → app `REVENUECAT_ANDROID_KEY`. Secret key (`sk_…`) → gateway `REVENUECAT_SECRET_KEY`.

## 6. Build the signed app bundle

Your upload key is in `signing/` (`apexhunt-upload.jks` + `key.properties`). **Back both files up now.** If you lose them, Play support has to reset your upload key, which takes days.

Create `app/env/prod.json` from `app/env/example.json` with your real values.

**Option A: GitHub Actions (no local Flutter needed).** Add the repository secrets listed at the top of `.github/workflows/android-release.yml` (repo root). Run these from the `Job-search-ai-agent` folder:
```bash
base64 -i signing/apexhunt-upload.jks | pbcopy     # → UPLOAD_KEYSTORE_BASE64
cat signing/key.properties | pbcopy                # → KEY_PROPERTIES
cat apexhunt/app/env/prod.json | pbcopy            # → APP_ENV_JSON
```
Then **Actions → Android release → Run workflow**, and download the `.aab` artifact. Add a `PLAY_SERVICE_ACCOUNT_JSON` secret to auto-upload to the internal track.

**Option B: local.** Install Flutter 3.47+ and Android Studio, then:
```bash
cp signing/apexhunt-upload.jks app/android/app/upload-keystore.jks
cp signing/key.properties app/android/key.properties   # storeFile=upload-keystore.jks
cd app && flutter build appbundle --release --dart-define-from-file=env/prod.json
# → app/build/app/outputs/bundle/release/app-release.aab
```
Bump `version:` in `pubspec.yaml` (the number after `+`) for every upload. GitHub Actions uses the run number automatically.

## 7. Closed testing (new personal developer accounts)

Google requires **12+ testers opted in for 14 consecutive days** before you can apply for production.
1. **Testing → Closed testing** → create a track → upload the bundle → add testers via an email list or Google Group.
2. Share the opt-in link with 15–20 people: friends, classmates, freelancer/dev communities. Keep them opted in for the full 14 days.
3. Collect feedback and ship 1–2 updates during the test; Google looks for active testing.
4. After 14 days → **Apply for production access** and answer the questionnaire honestly.

An **organization** account (needs a D-U-N-S number) skips the 14-day requirement.

## 8. Store listing and policy forms

- Listing copy, screenshots and feature graphic: `docs/PLAY_STORE_LISTING.md` and `docs/store-assets/`.
- **Data safety**: answers in `docs/DATA_SAFETY.md`.
- **Privacy policy URL**: `https://github.com/avsoarsa/apexhunt-ai/blob/main/apexhunt/docs/legal/privacy.md`. **Account deletion URL**: `…/apexhunt/docs/legal/delete-account.md` (the gateway also serves `/privacy` and `/delete-account`).
- Exact answers for every App content form: **`docs/PLAY_SUBMISSION_CHECKLIST.md`**.
- **App access**: "All features available. Sign in with any email address to receive a 6-digit code."
- **Ads**: No. **Content rating**: complete the questionnaire (utility/productivity, no user-to-user content). **Target audience**: 18+.
- **AI-generated content**: the app has an in-app "Report AI output" flag on every generated CV, letter, proposal and prep deck, as Play's generative-AI policy requires.

## 9. Go live

Production → create release → upload the latest bundle → roll out to 20% → watch Android vitals and reviews → 100%.

Before rollout, set gateway `ALLOW_SANDBOX_PURCHASES=false` so license-tester purchases stop minting real credits.

## Operating checklist

- Watch margin daily: `select * from apexhunt.daily_margin;` in Supabase.
- Check OpenRouter spend against RevenueCat revenue weekly.
- Review `apexhunt.ai_content_flags` weekly and respond to reports.
- Rotate `REVENUECAT_WEBHOOK_AUTH` if it leaks; update RevenueCat at the same time.
