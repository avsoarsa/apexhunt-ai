# Builds

| File | Status | Use |
|---|---|---|
| **`ApexHunt-AI-1.0.0-build3.aab`** | ✅ **Current, upload this** | Play Console → Internal testing → Production (or Closed testing) |
| **`ApexHunt-AI-1.0.0-build3-arm64-sideload.apk`** | ✅ Current | Install directly on an Android phone ("Install unknown apps") |

Builds 1 and 2 were removed from this folder (Sk's decision, 10 Nov 2026) to keep it small; they remain in git history. Never upload them: build 1 has placeholder legal links, and build 2 predates the Truth Guard, privacy and discovery fixes below.

## Build 3 (v1.0.0, versionCode 3), built 10 Nov 2026 from `main` at 87022a6
- Signed with the upload key in `signing/` (local only). SHA-256 `75:5C:C3:A2:EC:5C:B1:3E:48:28:1A:24:D0:4E:99:44:57:17:CB:5C:85:E0:C3:3C:B7:1F:F1:8C:3C:C8:BC:72` (same as build 2)
- Flutter 3.47.9 · targetSdk 36 · minSdk 24 · all 64-bit native libraries 16 KB page-aligned (checked in the AAB; APK passes `zipalign -c -P 16`)
- Permissions: INTERNET, ACCESS_NETWORK_STATE, BILLING (+ internal receiver permission)
- Legal links: `apexhunt/docs/legal/` (privacy, terms, account deletion) · support email sk.wedmist@gmail.com
- **Bring-your-own-key mode.** No sign-in, credits or purchases yet; no backend config baked in. Testers and Google's reviewers paste an AI key in onboarding. With a **free Gemini key**, Google may use what's sent (including a CV) to improve its products, and only paid keys are allowed in apps offered in the EU/EEA, Switzerland and the UK. The app now shows this warning (#8). See `docs/PLAY_SUBMISSION_CHECKLIST.md`.

### What changed since build 2
- **Truth Guard** (#9, #10, #11, #22, #23): invented numbers (incl. number words, dates/phones), ordinary words as skill evidence ("go live", "lambda expressions", "access"), AI-written aliases, short forms ("Kafka", "AWS") and fake "original" bullets are all caught; real bullets are never mangled.
- **Privacy copy** (#8): no more "nothing is used for AI training"; Gemini free-tier warning in the key form; privacy policy updated.
- **Country filter** (#13): whole-word country names and cities, no two-letter codes (no more "Indianapolis, IN" for India); uppercase "US" counts as the US.
- **Job-source limits** (#14 stopgap): Remotive fetched at most every 6 hours and Jobicy at most hourly per region, cached on the phone.
- App tests: 59, `flutter analyze` clean.

Every new Play upload needs a higher versionCode: bump `version: 1.0.0+N` in `app/pubspec.yaml`.
Phone checks for this build: `docs/DEVICE_QA_CHECKLIST.md`.
