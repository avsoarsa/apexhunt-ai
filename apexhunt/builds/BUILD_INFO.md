# Builds

| File | Status | Use |
|---|---|---|
| **`ApexHunt-AI-1.0.0-build2.aab`** | ✅ **Current, upload this** | Play Console → Internal testing → Closed testing |
| **`ApexHunt-AI-1.0.0-build2-arm64-sideload.apk`** | ✅ Current | Install directly on an Android phone ("Install unknown apps") |
| `ApexHunt-AI-1.0.0-build1.aab` / `…-arm64-sideload.apk` | ⛔ Superseded, **do not upload** | Kept for history: placeholder legal links, no support email |

## Build 2 (v1.0.0, versionCode 2)
- Signed with the upload key in `signing/` (local only). SHA-256 `75:5C:C3:A2:EC:5C:B1:3E:48:28:1A:24:D0:4E:99:44:57:17:CB:5C:85:E0:C3:3C:B7:1F:F1:8C:3C:C8:BC:72`
- Flutter 3.47.9 · targetSdk 36 · minSdk 24 · all 64-bit native libraries 16 KB page-aligned
- Permissions: INTERNET, ACCESS_NETWORK_STATE, BILLING (+ internal receiver permission)
- Legal links: `apexhunt/docs/legal/` (privacy, terms, account deletion) · support email sk.wedmist@gmail.com
- **Bring-your-own-key mode.** No sign-in, credits or purchases yet: testers and Google's reviewers paste an AI key (e.g. a free Gemini key) in onboarding. See `docs/PLAY_SUBMISSION_CHECKLIST.md`.
- Every new Play upload needs a higher versionCode: bump `version: 1.0.0+N` in `app/pubspec.yaml`.
