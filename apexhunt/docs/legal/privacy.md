# ApexHunt AI: Privacy Policy

**Effective:** 8 November 2026 · **Developer:** Sk Arif Majid ("ApexHunt AI", "we") · **Contact:** sk.wedmist@gmail.com

ApexHunt AI is an Android app that helps you find jobs and freelance projects, tailor your own CV to a job description, and prepare for interviews. This policy explains what data the app handles, where it goes, and the choices you have.

## 1. Summary
- Your CV, career profile, saved jobs, tailored documents and interview-prep notes are **stored on your phone**, not on our servers.
- When you run an AI feature, the text needed for that step (for example your CV and a job description) is **sent to an AI provider** to generate the result.
- We do **not** show ads, sell data, use advertising IDs, or include analytics or tracking SDKs.
- You can wipe everything with **Settings → Delete account & wipe data**.

## 2. Data stored only on your device
| Data | Purpose |
|---|---|
| CV text and the career profile built from it (name, contact details, work history, education, skills, projects) | Tailoring and interview prep |
| Job and freelance listings you discover or paste | Your pipeline |
| Tailored CVs, cover letters, proposals, prep decks | Your vault and prep dojo |
| App settings | Remembering your choices |
| Your own AI API key (if you add one) | Calling the AI provider you chose. Stored in Android Keystore-backed encrypted storage. |

This data is excluded from Android cloud backup and device-to-device transfer. We cannot access it.

## 3. Data sent to third parties when you use a feature
**AI providers.** When you run an AI step (CV import, requirement analysis, tailoring, cover letter/proposal, interview prep), the relevant text is sent to an AI model provider. Where it goes depends on how you power the AI:
- **Your own API key:** sent **directly from your phone** to the provider you selected (OpenAI, Anthropic, Google Gemini, Groq, OpenRouter, or a custom server you configure), under that provider's privacy policy and API terms. It never passes through our servers.
- **Apex AI credits** (when offered): sent through the ApexHunt gateway to a model provider via OpenRouter. The gateway does not store the content of requests or responses. It records token counts and cost for billing.

**Job sources.** When you run a search mission, your search keywords and selected countries are sent to job APIs: Remotive, Jobicy, Remote OK, Arbeitnow, Freelancer.com, Greenhouse and Lever company boards you choose, and (when signed in) Adzuna and Jooble via our gateway. Opening a listing takes you to the original website, which has its own policy.

**Text-to-speech.** "Listen" mode uses your phone's built-in text-to-speech engine.

**Purchases** (when offered) are handled by Google Play Billing and our billing provider RevenueCat. We receive subscription and purchase status, never your payment details.

## 4. Account data (only if you sign in for Apex AI credits)
If you sign in, we process your **email address** (sign-in via Supabase), your **credit balance and subscription status**, a **usage ledger** (date, model, token counts and cost per AI request, with no content), and any **AI-output reports** you submit. This is used only to run your account and billing.

## 5. Reporting AI output
Every AI-generated CV, letter, proposal and prep deck has a **Report** button. Depending on your setup, the report is sent to our gateway or opens an email to sk.wedmist@gmail.com containing the reason and an excerpt you can review before sending. We use reports only to improve the quality and safety of AI output.

## 6. What we don't do
We don't sell or rent personal data, show advertising, build advertising profiles, use your CV to train AI models, or collect location, contacts, photos, microphone or device identifiers.

## 7. Retention and deletion
- **On your phone:** data stays until you delete it. **Settings → Delete account & wipe data** erases all app data and your stored API key. Uninstalling the app also removes it.
- **Account (if any):** the same button deletes your account, wallet, usage ledger and reports from our servers. You can also request deletion at the account-deletion page linked below, or by email. We complete requests within 30 days, except records we must keep by law (e.g. tax records of purchases). We keep two small records afterwards: the deleted account's random ID and deletion date (so it can't be reopened to claim new free credit), and purchase records (product, amount and the store's transaction ID) detached from your account, so a purchase is never credited twice.
- **Third parties:** data sent to an AI provider using your own key is governed by that provider's retention policy.

## 8. Security
All network traffic uses HTTPS. API keys are stored in encrypted, Keystore-backed storage. Server databases (for accounts) are accessible only to the ApexHunt gateway.

## 9. Children
ApexHunt AI is intended for adults (18+) and is not directed to children.

## 10. Changes
We'll update this page and the effective date when the policy changes. Material changes will be highlighted in the app or on the store listing.

## 11. Contact
sk.wedmist@gmail.com

Account deletion: https://github.com/avsoarsa/apexhunt-ai/blob/main/apexhunt/docs/legal/delete-account.md · Terms: https://github.com/avsoarsa/apexhunt-ai/blob/main/apexhunt/docs/legal/terms.md
