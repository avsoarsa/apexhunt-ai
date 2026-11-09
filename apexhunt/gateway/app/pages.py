"""Public pages Google Play requires: privacy policy, account deletion, terms."""

from html import escape

from .config import Settings

_CSS = """
:root{--bg:#0F172A;--card:#1E293B;--fg:#E2E8F0;--muted:#94A3B8;--accent:#3B82F6}
@media (prefers-color-scheme: light){:root{--bg:#F8FAFC;--card:#FFFFFF;--fg:#0F172A;--muted:#475569;--accent:#2563EB}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,-apple-system,
Segoe UI,Roboto,sans-serif}main{max-width:760px;margin:0 auto;padding:32px 16px 64px}h1{font-size:28px;margin:0 0 4px}
h2{font-size:19px;margin:28px 0 8px}p,li{color:var(--fg)}small,.muted{color:var(--muted)}a{color:var(--accent)}
.card{background:var(--card);border-radius:14px;padding:20px;margin:16px 0}code{font-size:14px}
"""


def _page(title: str, body: str, s: Settings) -> str:
    return (f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' "
            f"content='width=device-width,initial-scale=1'><title>{escape(title)} · {escape(s.app_name)}</title>"
            f"<style>{_CSS}</style></head><body><main>{body}<p class='muted'><small>&copy; {escape(s.company_name)}"
            f" · <a href='/privacy'>Privacy</a> · <a href='/terms'>Terms</a> · <a href='/delete-account'>Delete account"
            f"</a></small></p></main></body></html>")


def landing(s: Settings) -> str:
    return _page("Home", f"""
<h1>{escape(s.app_name)}</h1>
<p class='muted'>AI career assistant: honest CV tailoring, job discovery and interview prep.</p>
<div class='card'><p>This server powers the {escape(s.app_name)} Android app. Get the app on Google Play.</p>
<p>Support: <a href='mailto:{escape(s.support_email)}'>{escape(s.support_email)}</a></p></div>""", s)


def privacy(s: Settings) -> str:
    app, mail = escape(s.app_name), escape(s.support_email)
    return _page("Privacy Policy", f"""
<h1>Privacy Policy</h1><p class='muted'>Last updated: November 2026</p>
<p>{app} ("we") helps you tailor your CV to job descriptions, discover openings and prepare for interviews.
This policy explains what we collect and why.</p>
<h2>1. Data that stays on your device</h2>
<p>Your CV, career profile, saved jobs, tailored CVs, proposals and prep notes are stored locally on your phone.
We do not keep copies of them on our servers. Your own AI API key (if you use "Bring your own key") is kept in
Android Keystore-backed encrypted storage and is sent only to the AI provider you chose.</p>
<h2>2. Data we process</h2>
<ul>
<li><b>Account:</b> your email address, used to sign you in and to hold your AI credit balance and subscription status.</li>
<li><b>AI requests:</b> when you run an AI feature using {app} credits, the relevant text (for example your CV and a
job description) is sent through our server to an AI model provider to generate the result. We do not store the
content of these requests or responses. We record token counts and cost for billing.</li>
<li><b>Purchases:</b> handled by Google Play and our billing partner RevenueCat. We receive your subscription status
and credit purchases, never your payment card details.</li>
<li><b>Job search:</b> your search keywords and selected countries are sent to job sources (for example Adzuna, Jooble,
Remotive, Arbeitnow, Jobicy, Remote OK, Greenhouse, Lever and Freelancer.com) to fetch listings.</li>
<li><b>Reports:</b> if you report an AI output, we store your reason and the excerpt you chose to send.</li>
</ul>
<h2>3. What we don't do</h2>
<p>We don't sell your data, show ads, or use your CV to train AI models. AI providers we route to process requests
under their API terms, which prohibit training on API data by default.</p>
<h2>4. Retention and deletion</h2>
<p>Account and billing records are kept while your account exists. You can delete your account at any time in the
app (Settings → Delete account & wipe data) or at <a href='/delete-account'>/delete-account</a>. Deletion removes your
account, wallet, usage ledger and reports within 30 days, except records we must keep for tax or legal reasons.
We keep two small records afterwards: the deleted account's random ID and deletion date (so it can't be reopened to
claim new free credit), and purchase records (product, amount and the store's transaction ID) detached from your
account, so a purchase is never credited twice.</p>
<h2>5. Security</h2><p>All traffic uses HTTPS. Access to our database is restricted to the gateway service.</p>
<h2>6. Children</h2><p>{app} is intended for adults (18+) and is not directed to children.</p>
<h2>7. Contact</h2><p><a href='mailto:{mail}'>{mail}</a></p>""", s)


def terms(s: Settings) -> str:
    app = escape(s.app_name)
    return _page("Terms", f"""
<h1>Terms of Use</h1><p class='muted'>Last updated: November 2026</p>
<h2>Accuracy of your CV</h2><p>{app} rewrites and reorganises information you provide. You are responsible for making
sure every statement in any CV, cover letter or proposal you send is true. Review every AI draft before using it.
Do not use {app} to misrepresent your experience, qualifications or identity.</p>
<h2>AI output</h2><p>AI output can be wrong. Use the in-app "Report" button to flag problems.</p>
<h2>Credits and subscriptions</h2><p>Subscriptions renew through Google Play until cancelled in Google Play settings.
AI credits are consumed per request at the prices shown in the app and are non-refundable except where required by
law or Google Play policy. If Google Play refunds a purchase, the credits it added (including a Pro plan's monthly
bonus) are removed from your balance, even if that takes it below zero. AI requests that use credits then pause until
a top-up covers the difference.</p>
<h2>Job listings</h2><p>Listings come from third-party sources and link to the original posting. We don't control or
endorse them.</p>""", s)


def delete_account(s: Settings) -> str:
    app, mail = escape(s.app_name), escape(s.support_email)
    return _page("Delete your account", f"""
<h1>Delete your {app} account</h1>
<div class='card'><h2 style='margin-top:0'>In the app (instant)</h2>
<ol><li>Open {app}.</li><li>Go to the <b>AI &amp; Settings</b> tab.</li>
<li>Tap <b>Delete account &amp; wipe data</b> and confirm.</li></ol>
<p>This deletes your account, AI credit wallet, usage history and reports from our servers, and wipes all career data
stored on your phone.</p></div>
<div class='card'><h2 style='margin-top:0'>By email</h2>
<p>If you no longer have the app, email <a href='mailto:{mail}?subject=Delete%20my%20{app}%20account'>{mail}</a>
from the address you signed in with, subject "Delete my account". We'll confirm within 7 days and complete deletion
within 30 days.</p></div>
<p class='muted'>Unused AI credits are forfeited on deletion. Cancel any active subscription in Google Play →
Payments &amp; subscriptions first, otherwise Google will keep billing it.</p>""", s)
