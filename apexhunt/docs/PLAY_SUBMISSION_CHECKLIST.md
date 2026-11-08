# Play Console submission checklist: ApexHunt AI v1.0.0 (versionCode 2)

The answers below match **this build** (`apexhunt/builds/ApexHunt-AI-1.0.0-build2.aab`). It runs in *bring-your-own-key* mode: no sign-in, no purchases, no server of ours. When you ship the managed build (Apex credits + Pro), revisit sections 5, 6 and 7.

Never upload `build1`: it has placeholder legal links. Use **build2** or newer.

## 1. Create the app
- App name: **ApexHunt AI** · Default language: English (United States) · App · **Free** · accept the declarations.
- Package (comes from the bundle): `com.apexhunt.ai`. This is permanent and can never be reused.

## 2. Test first (no review, live in minutes)
**Testing → Internal testing** → Create release → upload build2 `.aab` → add your Gmail (and the developer's) as testers → copy the opt-in link → open it on your phone → install from the Play Store.

## 3. Store listing (Grow → Store presence → Main store listing)
- Short/full description: `PLAY_STORE_LISTING.md`
- Icon `store-assets/play_icon_512.png`, feature graphic `store-assets/feature_graphic.png`, phone screenshots `store-assets/screenshots/` (use 4–7)
- Category **Business**, contact email **sk.wedmist@gmail.com**

## 4. App content (Policy → App content)
| Form | Answer for build2 |
|---|---|
| **Privacy policy** | `https://github.com/avsoarsa/apexhunt-ai/blob/main/apexhunt/docs/legal/privacy.md` |
| **App access** | "Some functionality is restricted." Instructions: *"No login. Discovery, profile and documents work without credentials. AI features (CV import with AI, tailoring, prep) need an AI provider key: on the 'Power your AI' screen choose Google Gemini, paste this key: `<REVIEWER_GEMINI_KEY>`, model `gemini-2.5-flash`, tap Test connection & save."* Create a free key at aistudio.google.com/apikey just for reviewers and set a low quota. |
| **Ads** | No, the app does not contain ads |
| **Content rating** (IARC) | Category: *Utility, Productivity, Communication or Other*. No violence, sexual content, profanity, drugs or gambling. Users can't interact with each other. No location sharing. No digital purchases in this build. Mention AI-generated text if asked. Expected rating: Everyone / PEGI 3. |
| **Target audience** | **18 and over** only. Not designed for children. |
| **News app** | No |
| **Health / Financial features / Government** | None / No / No |
| **Advertising ID** | No, the app doesn't use advertising ID (there is no AD_ID permission) |
| **Data safety** | See section 5 |
| **Account deletion** | Build2 has **no user accounts**, so answer that users can't create accounts. When the managed build adds sign-in: Yes, with URL `…/apexhunt/docs/legal/delete-account.md` |

## 5. Data safety (build2)
- Collects or shares required data types? **Yes**
- Encrypted in transit? **Yes**
- Users can request deletion? **Yes** (in-app wipe; no server data)

| Data type | Collected | Shared | Processed ephemerally | Required/optional | Purpose |
|---|---|---|---|---|---|
| Personal info → Name, Email address, Phone number, Address (inside the CV text) | Yes | **Yes**: AI provider chosen by the user | Yes | Optional | App functionality |
| Personal info → Other info (work history, education, skills) | Yes | Yes: AI provider | Yes | Optional | App functionality |
| App activity → In-app search history (job keywords + countries) | Yes | Yes: job-listing APIs | Yes | Optional | App functionality |

Everything else: **not collected** (location, contacts, photos, audio, files, health, financial, messages, device IDs, browsing).

## 6. Monetization
Build2 has no in-app products. Billing (Pro subscription + credit packs) arrives with the managed build; set up products only then (SETUP.md §4).

## 7. Policy self-check (done in code)
- [x] targetSdk 36 (meets the current target API requirement); minSdk 24
- [x] 16 KB memory page size: every 64-bit native library is 16 KB-aligned
- [x] Permissions: only INTERNET, ACCESS_NETWORK_STATE, BILLING (+ an internal receiver permission); no sensitive or runtime permissions
- [x] No ads SDK, no analytics/tracking SDK, no advertising ID
- [x] Privacy policy + terms linked in onboarding and in Settings; CV-to-AI disclosure shown before the first AI call
- [x] Generative-AI policy: **Report** button on every CV, letter, proposal and prep deck (emails sk.wedmist@gmail.com in this build); review gate before export
- [x] Honest positioning (Deceptive Behavior policy): the app never adds skills, employers or numbers the user didn't provide; the listing says so
- [x] In-app data wipe; app data excluded from cloud backup
- [x] Job sources attributed ("via Remotive") and every listing links to the original posting
- [x] Fonts are OFL-licensed (licences shown in Settings → Open-source licences); icon and artwork are original

## 8. Closed → production
Closed testing track → 12+ testers opted in for 14 consecutive days → **Apply for production** → answer the questionnaire honestly (what the app does, how you tested, what changed after feedback).

## 9. One developer account, many apps
Your Play developer account can publish many apps. Each needs its own package name, and a new keystore is recommended. Keep every app policy-compliant: serious or repeated violations on one app can suspend the **whole account**, including your other apps.
