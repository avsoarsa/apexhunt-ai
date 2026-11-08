# Launch & revenue plan

A realistic plan, not a promise. Most new apps earn little until something in distribution works, so the goal of the first 90 days is to find that thing cheaply.

## Unit economics (from the code's pricing)

| Item | Value |
|---|---|
| Typical tailored application | ~12k tokens over 4 AI calls |
| Apex Pro upstream cost (Claude Haiku 5.5 class) | ≈ $0.003 per application |
| User charge with +$1/1M markup ×1.15 | ≈ $0.017 per application |
| $4.99 credit pack → $5 credit | ≈ 290 applications; you net ≈ $4.24 after Play's 15%, upstream ≈ $0.85 → **≈ $3.40 gross margin** |
| Pro $3.99/mo | ≈ $3.39 net after Play; $1 bonus credit costs ≤ $0.20 upstream |
| Welcome credit $0.50 | ≈ 29 applications, costs you ≈ $0.08 upstream per new user |
| Fixed costs | Render ≈ $7, Supabase free → $25 at scale, RevenueCat free < $2.5k/mo, email free tier |

Break-even on fixed costs is about 3 Pro subscribers. Track this daily with `apexhunt.daily_margin`.

## Days 0–14: closed test, which is also your first growth loop

- Recruit 20 testers who are actively job hunting. Classmates, ex-colleagues and freelancer friends are ideal because they will really use it.
- Ask each tester to tailor 3 real applications and send one screenshot of the before/after ATS score. Those become your first marketing assets.
- Fix the top 3 friction points they hit (CV import, sign-in email, cost clarity).

## Days 15–45: launch in 2–3 markets first

Start where you have reach and where demand is clear:
1. **India**: huge volume, price-sensitive. Pro at ₹249/mo, credit packs at full USD-equivalent price.
2. **UAE/GCC**: expat job seekers with high intent. English works.
3. **Remote/global freelancers**: proposals are a strong hook.

Channels, roughly in order of cost-effectiveness:
- **Short videos** (Reels/Shorts/LinkedIn): "I tailored my CV to 10 jobs in 10 minutes — honestly." Show the Truth Guard and the gap plan. Honesty is the differentiator; competitors will happily fabricate.
- **Communities**: r/resumes, r/jobs, r/developersIndia, r/freelance, Indian and GCC job Telegram/WhatsApp groups. Give value first: free CV reviews using the app.
- **College placement cells and bootcamps**: a free semester of Pro for a cohort in exchange for feedback and a testimonial. Keep testimonials genuine and consented, and keep the details accurate.
- **ASO**: iterate the title/short description monthly. Run Play Store listing experiments on the icon and first screenshot.

## Days 45–90: retention and monetization

- Add a **referral**: both sides get $1 in credits (gateway: one more `credit_purchase` idempotency key).
- Add an **annual plan** ($29.99) and test a 7-day free trial on Pro.
- Ship **Hindi and Arabic** localization.
- Ship the **assisted apply** WebView (P1 in the spec), keeping Submit manual.
- Push notification when a mission finds 90%+ matches (needs server-side missions).

## Metrics that matter

| Funnel step | Target to aim for |
|---|---|
| Install → CV imported | > 60% |
| CV imported → first tailored application | > 50% |
| D7 retention | > 20% |
| Payer conversion (Pro or top-up) | 2–5% of active users |
| AI-output flag rate | < 1% of generated artifacts |

## Risks to manage

- **Policy**: keep listing copy accurate. Never market "beat background checks" or "fake experience"; that gets apps removed.
- **Cost spikes**: OpenRouter spend limit + gateway `MAX_COMPLETION_TOKENS` + per-user rate limit are already in place.
- **Source terms**: honor each job API's attribution and rate limits. Move keyless sources behind the gateway cache before scaling.
- **Welcome-credit abuse**: if sign-ups from throwaway emails spike, lower `WELCOME_CREDIT_USD` or require Pro for managed AI (`REQUIRE_SUBSCRIPTION_FOR_MANAGED=true`).
