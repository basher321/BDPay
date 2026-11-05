# 15 Release

Purpose
Prepare BDPay for real merchants: a separate production setup, real alert emails, a signed app with an
update notice, a download page, privacy and terms pages, a health check for monitoring, and clear
runbooks for launch and for problems. Claude Code prepares; I run every online step by hand.

Scope
Code (Claude Code writes and tests):
- supabase/functions/_shared/mailer.ts: ResendMailer (HTTPS call to the Resend email API with RESEND_API_KEY
  and ALERT_FROM_EMAIL from the environment). store_factory-style selection: BDPAY_FAKE_MAILER=1 -> FakeMailer;
  RESEND_API_KEY set -> ResendMailer; neither -> FakeMailer plus one warning log line "mailer not configured".
- Edge Function health: GET -> 200 {ok: true, db: true, time} when a simple Store read works, else 503
  {ok: false, db: false}. No user data, no auth needed, rate limit 60 per minute per IP hash.
- device-heartbeat response adds latestAppVersion and appDownloadUrl from env LATEST_APP_VERSION and
  APP_DOWNLOAD_URL (both optional).
- App: when latestAppVersion is newer than the running version, হোম shows an emerald card
  "নতুন ভার্সন {v} এসেছে" with button "ডাউনলোড করুন" (opens appDownloadUrl in the browser).
  Settings shows "গোপনীয়তা নীতি" and "শর্তাবলি" links that open the pages below.
- Android release signing: android/app/build.gradle reads android/key.properties if it exists (storeFile,
  storePassword, keyAlias, keyPassword) for the release build. Claude Code writes this gradle code but never
  creates, reads or prints key.properties or any keystore. versionName 1.0.0, versionCode 1.
- Pay page site files: privacy.html, terms.html (Bangla, placeholder text clearly marked
  "আইনজীবীর পর্যালোচনা প্রয়োজন" at the top), download.html (version, file size, SHA-256 of the APK,
  install steps in Bangla including "অজানা উৎস থেকে ইনস্টল চালু করুন", and a warning to download only from
  this page). The pay page footer links to privacy and terms. Same CSP and no-innerHTML rules as spec 07.
Documents (Claude Code writes, I follow):
- ops/production_runbook.txt
- ops/release_checklist.txt
- ops/incident_playbook.txt
Not in scope: Google Play submission, the Shopify App Store listing text and video, billing merchants,
new features, running any online command.

Contract
ResendMailer: POST to the Resend send-email endpoint with from = ALERT_FROM_EMAIL, to, subject, text.
2xx -> sent; anything else or timeout (10 s) -> failed. Never logs the address, subject or body.

production_runbook.txt (exact steps, each ending with a "check" line):
1. Production Supabase project "bdpay-prod" on a paid plan with daily backups (check the current plan
   names and prices); region near Bangladesh. Turn on the security and performance advisors and fix any
   error they show before launch.
2. supabase link to prod in my own terminal; supabase db push; load_parser_rules.ts with the latest rules.
3. Secrets: all names from staging with NEW random values for PAY_TOKEN_SECRET and CRON_SECRET (never reuse
   staging values), plus RESEND_API_KEY, ALERT_FROM_EMAIL, LATEST_APP_VERSION, APP_DOWNLOAD_URL.
   BDPAY_FAKE_* must not be set.
4. Deploy functions (the same --no-verify-jwt list as staging, plus health).
5. Vault secrets functions_url and cron_secret for the schedules; check in the cron history that the three
   jobs run every 5 minutes.
6. Domain: a BDPay domain; pay page at pay.<domain> on Cloudflare Pages; email sending domain verified in
   Resend (SPF, DKIM records); Supabase Auth custom SMTP set to Resend so login codes are not limited;
   paste otp_bn.html as the email template.
7. Shopify: a SEPARATE production app (not the staging app) pointing at production URLs; shopify app deploy;
   first pilot merchants through custom distribution; prepare the public app review (privacy URL, support
   email, compliance webhooks already built, demo video) as a separate task.
8. Release keystore: the exact keytool command to create it, where to keep it (outside the project, plus an
   offline backup), and how to write android/key.properties by hand. Warn: losing the keystore means
   merchants must uninstall and reinstall to update.
9. Build: flutter build apk --release --obfuscate --split-debug-info=build/symbols with the production
   --dart-define values; keep build/symbols privately; compute SHA-256 of the APK; put the APK and its
   SHA-256 on download.html; set LATEST_APP_VERSION and APP_DOWNLOAD_URL.
10. Monitoring: a free uptime monitor checking the health function and the pay page every 5 minutes,
    alerting my email/phone; weekly run of ops/e2e_queries.sql.
11. Backups: confirm the first daily backup exists; do one test restore into a scratch project before
    taking the first real merchant.

release_checklist.txt (go / no-go, each line a yes/no):
- Spec 14 checklist all PASS (or documented and fixed).
- Real SMS rules tested for every operator offered; untested operators turned off by default.
- Production secrets are all new; no BDPAY_FAKE_* set; staging and production Shopify apps are separate.
- Advisors show no errors; RLS on every table; supabase test db passes on the release commit.
- health is green; schedules running; a test alert email arrives from production.
- Privacy policy and terms reviewed by a lawyer and published; MFS account terms and Bangladesh Bank
  payment rules checked by a lawyer for the way BDPay is used.
- Keystore backed up offline; APK SHA-256 published.
- One full real payment on production with my own store passes before the first merchant.
- Support contact (phone/WhatsApp/email) written in the app settings footer and on download.html.

incident_playbook.txt (short steps for each case):
- A merchant's phone is offline (phoneSilent): call the merchant; checklist (power, internet, battery saver,
  auto-start, app not force-stopped); customers' pending payments verify by themselves when it returns.
- Payments stuck "যাচাই বাকি": check the merchant's phone health; check rejected SMS by reason; if a new SMS
  layout appeared, add it to tests/real_sms, fix rules, load a new rules version (no app update needed).
- Shopify "Paid" not set (syncFailed): the payment is still verified; the merchant marks it paid by hand;
  check reconnectNeeded and Shopify status.
- Server or database down: the phone keeps SMS queued; nothing is lost; check the Supabase status page.
- Suspected fraud (a TrxID used by the wrong customer): look up the claim, session and match by TrxID with
  read-only queries; the merchant decides; never delete records.
- A secret leaked: rotate it with supabase secrets set; for PAY_TOKEN_SECRET know that all open pay links stop
  working (customers reopen from the Shopify order page); for the Shopify secret rotate it in Shopify too.
- A phone stolen: the merchant logs in on a new phone; revoke the old device (set status revoked in Studio,
  written as an audit entry by hand).

Functional rules
- Production and staging never share secrets, Shopify apps or databases.
- No release step deletes data.
- Untested operators can be offered only after their real SMS samples pass.

Edge cases
- Resend down -> alerts stay open and retry (spec 11 behaviour); health stays green.
- APP_DOWNLOAD_URL not set -> no update card even if a newer version exists.
- An older app (before this spec) ignores the new heartbeat fields without errors.
- key.properties missing -> the release build fails with a clear message; debug builds still work.

Non-functional rules
- No secret, key, password or keystore in the repo; .gitignore covers key.properties, *.jks, *.keystore,
  build/symbols and every .env file.
- deno check/lint/fmt, flutter analyze, all tests pass.

Acceptance criteria
- deno test passes, including ResendMailer with a stub fetch (2xx sent, 500 failed, timeout failed, nothing
  logged), mailer selection rules, health ok/503 and rate limit, heartbeat fields present and optional.
- flutter test passes, including the update card (newer, same, older version, missing URL) and the
  privacy/terms links.
- flutter build apk --debug succeeds; the release build fails with a clear message when key.properties is missing.
- Pay page tests pass; privacy, terms and download pages have no innerHTML, no outside scripts, and work at 320 px.
- .gitignore check: git check-ignore confirms key.properties, a .jks file, build/symbols and .env files are ignored.
- A search shows no secrets or real URLs in code (only environment names and REPLACE_ME placeholders).
- The three ops files exist and every runbook step has a "check" line.
- I complete release_checklist.txt with all yes before the first real merchant.

Assumptions
- Spec 14 is done and its checklist passed.
- I have bought a domain, and have Resend, Cloudflare, Supabase (paid) and Shopify Partner accounts.
- A lawyer reviews the legal pages and the MFS / payment rules before launch.
