# Store assets

- `play_icon_512.png`: Play Store icon (512×512, no transparency).
- `feature_graphic.png`: 1024×500 feature graphic.
- `screenshots/`: 1080×1920 phone screenshots rendered from the real app UI with fictional demo data (`--dart-define=DEMO_SEED=true`, persona "Alex Rivera").

Retake the screenshots on a real device once your production build is configured, so the top bar shows "Apex Pro • $x.xx" instead of "BYOK active". To reproduce these: `flutter run --dart-define=DEMO_SEED=true`. Never ship a DEMO_SEED build.
