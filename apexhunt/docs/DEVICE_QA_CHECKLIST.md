# 30-minute phone check for build 3 (Sk)

A short, phone-only pass over the parts of `QA_TEST_PLAN.md` that no one can test without a real device. Build 3 is BYOK-only (no sign-in, no credits). Use the fictional CV and job below, not your own CV: on a free Gemini key, Google may use what you send to improve its models (#8).

**You need:** an Android phone (ideally a mid-range one on Android 10–14), build 3, an AI key (Gemini works; a paid key is better), and Wi-Fi.
**Report a problem:** open a GitHub issue with the Bug report template (device, Android version, build 3, steps, screenshot), or send the list to A and B. Mark each item ✅ / ❌.

## 0. Install (2 min)
- [ ] If an older ApexHunt build is installed, **uninstall it first**. The sideload APK and the Play build are signed differently and have different version codes, so Android refuses to update one with the other.
- [ ] Install build 3, from Play internal testing or the sideload APK.
- [ ] Open it: a welcome screen within about 3 seconds, with no crash.

## 1. Onboarding (5 min)
- [ ] AI step: paste the key with a **space before and after**, then "Test connection". It should pass (spaces trimmed).
- [ ] Change one character of the key, then test again. You should see a clear error, not a crash or a raw code.
- [ ] Read the data notice on the CV step. It should say what goes to the AI provider, and must **not** claim "nothing is used for AI training" without the free-tier caveat (#8).
- [ ] CV step: paste the **sample CV** below into "or paste it". The review screen should show both roles, the dates, and the skills Node.js and PostgreSQL.
- [ ] Optional: upload a real PDF and a DOCX CV. Names, roles and dates should come through. Known gap: contact details placed in a DOCX header are not read.

## 2. Truth Guard (8 min), the most important block
1. Command tab → **Paste a JD** → paste the **sample job** below → Tailor.
2. Skill check-in:
   - [ ] **Backed by your CV** shows only **Node.js** and **PostgreSQL**.
   - [ ] **Go, C, R, AWS Lambda, Microsoft Access, Kubernetes, Kafka and Rust** are **not** marked as backed. "go live", "C-level", "R&D", "lambda expressions" and "access" in the CV are ordinary words (#10, #23).
   - [ ] Tap × on a backed skill: it moves to the gaps.
   - [ ] "I have it" refuses to continue without a context line.
3. Mark everything that's not backed as **Don't have**, then generate.
4. In the Vault, read the tailored CV, cover letter and prep:
   - [ ] **None of Go, C, R, AWS Lambda, Access, Kubernetes, Kafka or Rust** appears in the CV, its skills list or its headline.
   - [ ] **No number** appears that isn't in the sample CV. Allowed: three (3), 40%, and the years 2019–2021. Not allowed: "8+ years", "team of 5", "10 services", or any new %.
   - [ ] Employer names, titles and dates are exactly as in the sample CV.
   - [ ] The cover letter doesn't claim the missing skills either. It has no automatic check yet (#12), so read it.
   - [ ] Prep has gap plans for the skills marked Don't have.

## 3. Discovery (6 min)
- [ ] Jobs mode, **country India only**, keywords "backend developer". Open 10 results: none should be US-only (look for "US only", a US state such as "Indianapolis, IN", or "US time zones") (#13).
- [ ] Repeat with **Germany only**: no "Wilmington, DE"-style US listings.
- [ ] A mission with **4 keywords**: the log doesn't say "Remotive unavailable right now". Remotive may add few or no matches, because its free feed only has about 12 jobs. Build 3 fetches it at most once every 6 hours, and a second mission within 6 hours reuses the copy on the phone.
- [ ] Each result shows "via <source>", and opening it goes to the real listing.
- [ ] Turn on **airplane mode**, run a mission: no crash. Remotive (and Jobicy within an hour) may still show earlier results from the copy saved on the phone; sources without a saved copy say "unavailable right now — skipped".

## 4. Vault and export (6 min)
- [ ] Turn off one bullet: the PDF preview and the ATS score update.
- [ ] Share PDF stays blocked until "I have reviewed…" is ticked, then the share sheet opens.
- [ ] Share the PDF and the DOCX to Google Drive (or Gmail to yourself). The file name starts with `Priya_Sharma_`.
- [ ] Open the PDF in Drive: the text is selectable, with no missing characters.
- [ ] Open the DOCX in Google Docs: no warnings, and the bullets intact.

## 5. Settings and wipe (2 min)
- [ ] Privacy, Terms and Delete-account links open.
- [ ] **Delete account & wipe data** → the app returns to onboarding, and the AI key field is empty.
- [ ] Known issue, don't re-report: copies of shared CV files can remain in the app cache after a wipe (#16).

## 6. Quick feel (1 min)
- [ ] Scroll a list of 50+ jobs: no stutter. Rotate the phone on the Vault: no crash.
- [ ] Optional: turn on TalkBack and get through the welcome and AI steps.

## After uploading to Play internal testing
- [ ] Play Console → **Pre-launch report** (runs automatically on real devices): note any crashes or ANRs, and the accessibility and security warnings.

---

### Sample CV (fictional; paste in onboarding)
```
Priya Sharma | +91 98765 43210 | priya.sharma@example.com | Hyderabad 500081

Backend Developer, Finlytics (Jan 2021 - Present)
- Built REST APIs in Node.js for loan processing.
- Helped the payments product go live in three cities.
- Presented sprint demos to C-level stakeholders.
- Cut report time by 40% with PostgreSQL indexes.
- Refactored payment rules with Java lambda expressions.

Junior Developer, CodeNest (Jul 2019 - Dec 2020)
- Wrote SQL reports in PostgreSQL.
- Supported R&D experiments on credit scoring.
- Gave stakeholders access to weekly loan reports.

Education: B.Tech Computer Science, JNTU, 2019
Skills: Node.js, PostgreSQL, SQL
```

### Sample job (paste in Command → Paste a JD)
```
Senior Backend Engineer, Payments (Remote, India)

We're hiring a backend engineer to build payment services.
Must have: Go (Golang), Kubernetes, Apache Kafka, AWS Lambda, PostgreSQL, Node.js.
Nice to have: C, R for analytics, Rust, Microsoft Access for legacy reports.
You'll design event-driven services, run them on Kubernetes, own on-call for 10 services,
and mentor a team of 5. 8+ years of backend experience preferred.
```
