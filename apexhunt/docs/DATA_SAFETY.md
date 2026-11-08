# Play Console: Data safety answers (managed build)

> For the current bring-your-own-key build (no sign-in, no purchases), use the shorter answers in `PLAY_SUBMISSION_CHECKLIST.md` §5. This page applies once sign-in, Apex credits and purchases ship.

These answers reflect the code as built. Update them if you add analytics, crash reporting, ads or server-side CV storage.

**Does your app collect or share any of the required user data types?** Yes
**Is all user data encrypted in transit?** Yes (HTTPS everywhere)
**Do you provide a way for users to request that their data is deleted?** Yes: in-app *Settings → Delete account & wipe data*, plus `https://<gateway>/delete-account`

## Data types

| Category → type | Collected | Shared | Optional? | Purpose | Notes |
|---|---|---|---|---|---|
| Personal info → **Email address** | Yes | No | Required for managed AI credits (BYOK users can skip sign-in) | Account management | Supabase Auth |
| Personal info → **Name, phone, address** (inside CV text) | Yes | **Yes**, with AI providers when the user runs an AI step | Optional (user-initiated) | App functionality | Processed ephemerally to generate tailored content, not stored on our servers. Disclose as "shared" because a third party (the AI model provider) processes it. |
| Personal info → **Other info** (work history, education, skills) | Yes | Yes, same as above | Optional | App functionality | Same as above |
| Financial info → **Purchase history** | Yes | No | Required to use paid features | App functionality, account management | Google Play + RevenueCat; we never see card details |
| App activity → **Other user-generated content** (AI-output reports) | Yes | No | Optional | App functionality (abuse/quality review) | Only when the user taps "Report AI output" |
| App activity → **App interactions** (AI token usage ledger) | Yes | No | Required for credits | Account management, fraud prevention | Token counts and cost per request, no content |

**Not collected:** location, contacts, photos/videos, audio, files beyond what the user picks, health, messages, device IDs, web browsing, ads data.

**Processed ephemerally?** For CV/job text sent to AI: **Yes**. It is processed in memory to fulfil the request and not stored by ApexHunt.

## Security section

- Data is encrypted in transit: **Yes**
- Users can request deletion: **Yes**
- Independent security review: No (leave unchecked unless you get one)

## Bring-your-own-key note

With BYOK, CV text goes straight from the phone to the provider the user chose (OpenAI, Anthropic, Google, Groq, OpenRouter or a custom URL). The API key is stored in Android Keystore-backed encrypted storage and never reaches ApexHunt servers.
