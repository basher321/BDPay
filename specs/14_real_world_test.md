# 14 Real-world test (staging)

Purpose
Prove BDPay works with real things: a Shopify development store, a real Android phone with real
bKash / Nagad / Rocket / Upay SIMs, real SMS and small real payments. Fix the SMS rules from real
messages, and check that the phone-silent alert does not fire falsely when Android saves battery.

Scope
Claude Code prepares (and never runs anything against an online project):
- ops/staging_runbook.txt: the exact steps I run by hand, in order (see Contract).
- A new migration that schedules the three timed jobs with pg_cron and pg_net (see Contract).
- supabase/scripts/load_parser_rules.ts: loads supabase/functions/_shared/parser_rules.json as a new active
  version into a database I choose at run time.
- tests/real_sms/: real SMS samples I collect (numbers and names changed by me), one file per message,
  first line = sender, rest = body, plus an expected-result file per message.
- New parser tests from those samples in all three places: Dart (app), Kotlin (SmsFilter) and Deno (server).
- Rule fixes in parser_rules.json (both copies) until every real sample gives the expected result,
  with "version" increased.
- tests/e2e/E2E_CHECKLIST.txt: the test list below with an empty results table for me to fill.
- ops/e2e_queries.sql: read-only SELECT queries I run in Studio (see Contract).
I do by hand: everything in the runbook, the real payments, filling in the checklist.
Not in scope: production, app store release, the real email provider (spec 15), new features.

Contract
Runbook (ops/staging_runbook.txt), each step with the exact command or dashboard path:
1. Create a Supabase project "bdpay-staging" (region nearest to Bangladesh, for example Singapore).
2. In my own terminal: supabase link, supabase db push (applies all migrations), then run
   load_parser_rules.ts with the staging URL and service key given as environment variables in that terminal only.
3. Set Edge Function secrets with supabase secrets set (names from specs 10-12a; values never written in files):
   PAY_TOKEN_SECRET and CRON_SECRET as new random values, SHOPIFY_API_KEY, SHOPIFY_API_SECRET, SHOPIFY_SCOPES,
   SHOPIFY_API_VERSION, FUNCTIONS_URL, PAY_PAGE_URL, PAY_PAGE_ORIGIN, BDPAY_FAKE_MAILER=1.
   BDPAY_FAKE_STORE and BDPAY_FAKE_SHOPIFY must NOT be set.
4. Deploy every Edge Function (supabase functions deploy). Device, pay page, Shopify webhook, OAuth callback
   and cron functions must allow calls without a Supabase user token (they check their own signatures);
   list exactly which functions need --no-verify-jwt.
5. Vault secrets for the schedules: functions_url and cron_secret (Dashboard > Vault).
6. Auth: enable email OTP with 6 digits; paste supabase/templates/otp_bn.html as the email template
   (Dashboard > Authentication > Email templates). Note that the built-in email sender has a low hourly limit.
7. Pay page: set pay_page/config.js API_BASE to the staging functions URL and USE_MOCK false, update the CSP
   connect-src, and upload the pay_page folder to Cloudflare Pages (direct upload in the dashboard).
   Its address becomes PAY_PAGE_URL / PAY_PAGE_ORIGIN (go back to step 3 if they changed).
8. Shopify: shopify app config link; put the real FUNCTIONS_URL in shopify.app.toml and src/config.ts;
   shopify app deploy; install on the development store through custom distribution; set the store currency
   to BDT; create the manual payment method "bKash / Nagad (BDPay)"; add the BDPay pay box on the Thank you
   and Order status pages in the checkout editor; request network access for the extension.
9. App: build a release-mode APK with the staging --dart-define values, install it on the real phone,
   sign in, add the real wallets with the right SIM slots, connect Shopify from the app, turn off battery
   optimization, turn on auto-start on Xiaomi/Oppo/Vivo/Realme phones.
Each step ends with a "check" line (what I should see).

Schedules migration (pg_cron + pg_net), every 5 minutes: claims-expire, shopify-sync, alerts-check.
Each job reads the URL and secret from Vault (functions_url, cron_secret) at run time; no URL or secret is
written in the migration. If the Vault secrets do not exist (local), the job does nothing and does not fail.

load_parser_rules.ts:
- Reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from the environment of the terminal where I run it.
- Refuses if that version already exists. In one call: inserts the new version, makes it the only active one.
- Prints only the version number and "loaded".

e2e_queries.sql (SELECT only):
- Verification time per payment: sms received_at -> match created_at, and claim created_at -> match created_at,
  in seconds, last 7 days; plus the median.
- Heartbeat gaps per device: the biggest gaps between heartbeats over the last 48 hours (from audit or
  last_seen_at history; if the history is not kept, say so and suggest a read-only alternative).
- Rejected SMS by reason, last 7 days (counts only, no body).
- Order syncs not done, and open alerts.
No query shows SMS body, payer numbers or tokens.

Real SMS samples (tests/real_sms/):
- For each operator I can test: at least 3 "money received" messages, plus at least 1 each of OTP, outgoing
  payment (send money / payment made), cash out, and promotion from the same sender.
- I replace phone numbers with other numbers of the same format, and names with "X". I keep TrxIDs,
  amounts and layout exactly.
- Expected-result file: keep or drop, and when keep: operator, trxId, amountPoisha, payerNumber, kind.

Test list (tests/e2e/E2E_CHECKLIST.txt; I fill result, time and notes):
A. Real order -> pay box on the Thank you page -> pay page -> pay Tk 10 -> enter TrxID -> "পেমেন্ট নিশ্চিত হয়েছে"
   -> Shopify order shows Paid with tag BDPay-verified. One run per operator available.
B. Pay first and wait 2 minutes, then enter the TrxID -> verified at once.
C. Pay Tk 11 for a Tk 10 order -> "টাকা মেলেনি" in the app -> approve -> pay page verified -> Shopify Paid.
D. Enter a wrong TrxID, then change it to the right one -> verified; attempts left shown correctly.
E. Phone in airplane mode -> customer pays and enters TrxID -> pay page pending -> airplane mode off ->
   verified without touching the phone.
F. Phone locked and not touched overnight (8+ hours) -> a morning payment verifies -> check heartbeat gaps.
G. Reboot the phone, do not open the app -> a payment verifies.
H. Dual SIM: a payment to the SIM 2 wallet -> the SMS shows the right SIM and wallet.
I. Request a real OTP from an MFS app -> no new row in sms_messages.
J. Send money out from the merchant wallet -> no new row.
K. Cancel an unpaid order in Shopify -> the pay page shows expired.
L. Leave a pay page open 60+ minutes without paying -> expired.
M. Uninstall the app in Shopify -> the BDPay app shows Shopify not connected; reinstall from the app works.
N. Two phones for one merchant (if available) -> both register; a payment to either verifies.
O. Pay page on a slow connection (Chrome dev tools "Slow 4G" and "3G") -> usable, no broken screens.
P. Leave the phone untouched for 24 hours -> count phoneSilent alerts (should be 0 when the phone had internet).

Functional rules
- Real money tests use small amounts (Tk 10-20). Return test money by hand afterwards.
- If any test fails, the fix goes in a new small spec (14a, 14b ...) before release; this spec only records results.
- If F or P show heartbeat gaps over 15 minutes while the phone was fine, write it in the checklist notes;
  the fix (a longer phoneSilent limit or a different heartbeat method) becomes spec 14a.

Edge cases
- A real SMS layout differs from the samples -> add it to tests/real_sms first, then fix the rules, never the other way.
- A rules fix must not break any older sample (all samples are tested every time).
- An operator I cannot test -> mark it "not tested" in the checklist; its rules stay marked SAMPLE.

Non-functional rules
- No secret, key, token or real customer data in any file in the repo.
- The runbook never asks to put secrets in files; secrets go only into supabase secrets set, Vault or the
  terminal environment of a single command.
- Claude Code does not run supabase link, supabase db push, supabase functions deploy, supabase secrets set,
  shopify app deploy or any command against an online service.

Acceptance criteria
- All earlier automated tests still pass (flutter test, Kotlin tests, deno test, supabase test db).
- Every file in tests/real_sms gives its expected result in Dart, Kotlin and Deno tests.
- The schedules migration applies locally without errors and does nothing locally without the Vault secrets.
- load_parser_rules.ts refuses a version that already exists (tested against local Supabase).
- A search shows no secret values, keys or real phone numbers in the repo.
- I complete the checklist: A-P all PASS (or "not tested" with a reason), median verification time under
  10 seconds for online tests, and test P with 0 false phoneSilent alerts — or the failing items are written
  as new specs before spec 15.

Assumptions
- Specs 01 to 13a are done and pass locally.
- I have a Shopify Partner account and development store, a Supabase account, a Cloudflare account,
  a real Android phone, and MFS wallets for testing (merchant accounts if possible).
