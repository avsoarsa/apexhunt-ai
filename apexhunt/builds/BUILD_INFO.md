# Builds: v1.0.0 (versionCode 1)

| File | Use |
|---|---|
| `ApexHunt-AI-1.0.0-build1.aab` | Upload to Play Console → **Internal testing** or **Closed testing** |
| `ApexHunt-AI-1.0.0-arm64-sideload.apk` | Install directly on your own Android phone for a quick try (enable "Install unknown apps") |

- Signed with your upload key in `../../signing/` (SHA-256 `75:5C:C3:A2:EC:5C:B1:3E:48:28:1A:24:D0:4E:99:44:57:17:CB:5C:85:E0:C3:3C:B7:1F:F1:8C:3C:C8:BC:72`).
- Built with Flutter 3.47.9, targetSdk from Flutter defaults (Android 16 / API 36), minSdk 24.
- **This build has no `env/prod.json` baked in.** It runs in *Bring-Your-Own-Key* mode: testers paste a free Google Gemini key (aistudio.google.com/apikey) or any provider key in onboarding. Sign-in, Apex credits and purchases appear once you rebuild with your gateway, Supabase and RevenueCat values (docs/SETUP.md §6).
- Why upload it now: it starts the mandatory **14-day closed-testing clock** while you set up the backend. Ship the fully configured build as versionCode 2+ to the same track during the test.
- Every new upload needs a higher versionCode: bump `version: 1.0.0+N` in `app/pubspec.yaml`. The GitHub Action uses the run number automatically.
