# Plan 14 - Real-world test (staging)

Spec: specs/14_real_world_test.md. Written 2026-10-30.
Read with: CLAUDE.md, specs 08-13a, plans 12a/13/13a, and the current repo (supabase/, app/, pay_page/, shopify_app/).

Default rule: until you answer a decision below, the build follows the spec text; where the spec cannot work as
written I stop and ask. Claude Code never runs anything against an online service (spec + CLAUDE.md); every
online step is a line in the runbook that you run.

Reviewed 2026-10-30 against the spec and CLAUDE.md; section 8 lists what the review changed.

Decisions and build notes (2026-10-30): D180 = A; D183 = no SQL function, so load_parser_rules.ts switches
versions with REST calls through the database API (plain fetch, no package): insert inactive, old off, new on,
and the old one is switched back on if activation fails (a short moment with no active version, written in the
runbook); the load_parser_rules migration and its pgTAP test are therefore not written. D191 = yes.
Build findings: (1) app/android/app/build.gradle.kts declares tests/real_sms as a unit-test input, otherwise
Gradle kept an old RealSmsTest result after a sample changed. (2) shopify_app/ lacks spec 10a's
shopify.app.toml, extension toml and src/config.ts - added to the runbook's prerequisites. (3) Runbook step 8
tells you not to open the custom-distribution install link: shopify-oauth-callback only accepts installs BDPay
started (single-use state), so the install starts from the app in step 9.

Claude Code command rules for this spec (because runbook step 2 links this same folder to staging):
- Every supabase command I run names the local target explicitly (`--local` where the command has it) and is one
  of: migration new, migration up --local, test db --local, status, start, stop. I never run link, unlink,
  db push/pull/diff, migration list/repair, functions deploy/serve against a project, secrets, inspect,
  projects, gen types --linked or anything with --linked / --project-ref / --db-url to a non-local host.
- Before any supabase command I check that supabase/.temp/project-ref does not exist; if it does (you linked
  staging and did not unlink, runbook step 4b) I stop and ask.
- Every script or test I run that takes SUPABASE_URL gets it set explicitly to http://127.0.0.1:54321 in that
  command, never inherited, and calls assertLocal before anything else.
- Never shopify app deploy / dev / config link / generate, never wrangler or any Cloudflare command.
- Package downloads by deno / flutter / gradle from their registries are not "online services" in this sense,
  but a build that starts installing SDK parts is stopped and reported (as in plan 13a D165).

## 0. Blockers (spec 14 assumes "specs 01 to 13a are done and pass locally")

| Needed by spec 14 | Today (checked 2026-10-30) | Effect |
|---|---|---|
| supabase/migrations (spec 12), seed.sql, supabase/tests (pgTAP) | No migrations folder, no seed, no pgTAP tests | The schedules migration has nothing to build on; "supabase test db" cannot run |
| supabase/config.toml (spec 13: 6-digit OTP locally) | Missing (supabase init never ran) | Local Supabase cannot start from this repo |
| Supabase CLI + Docker | Neither is installed (shopify CLI and node are) | No local database: the migration and load_parser_rules.ts acceptance checks cannot run |
| PgStore, store_factory, supabase-js pinned (spec 12a) | Not built | Edge Functions only run on FakeStore; staging would answer 503 storeNotReady |
| Spec 09 functions: pay-session, claim-review, sms-status, claims-expire (+ token.ts, cors.ts, rate_limit.ts, session_view.ts) | Not built (only match_rules.ts / matcher.ts) | No pay page API, no claims, nothing for claims-expire to schedule |
| Spec 10 functions: shopify-connect-link, -oauth-callback, -webhooks, -paylink, -sync, -status | _shared parts exist (shopify_auth, shopify_client, shopify_orders, money_text, fake_shopify); no function folders, no shopify_notifier.ts | No Shopify flow; nothing for shopify-sync to schedule |
| Spec 11 functions: alerts-check, alerts-list | _shared parts exist (alert_rules, alert_messages, mailer); no function folders | Nothing for alerts-check to schedule; test P cannot be measured |

- D180. **Build order.** A (recommended) write now what does not depend on the missing pieces and can be
  checked without a database: the real-SMS loaders and tests in Dart, Kotlin and Deno (they pass with an empty
  folder and fail on any bad sample), tests/e2e/E2E_CHECKLIST.txt, ops/staging_runbook.txt, ops/e2e_queries.sql
  (written against the spec 12 column names), the schedules migration and load_parser_rules.ts (written, with
  their local checks left as "waits for spec 12 + Docker"), the repo scan. B first finish specs 09, 10, 11, 12,
  12a (and install the Supabase CLI and Docker - your machine, your yes), then spec 14. Nothing in staging can
  work before B is done; A only saves time later.

## 1. Files

New = created by this spec. [CHANGED nn] = an earlier spec's file.

### Ops and checklist (plain text, no secrets)
- ops/staging_runbook.txt - the 9 steps of the Contract, each with the exact command or dashboard path and a
  "check:" line. Secret handling (D198): every secret value is typed into a hidden prompt and kept in a
  variable, so neither the screen, the PowerShell history file (PSReadLine saves command lines, not variable
  values) nor any file ever holds it:
    $s = Read-Host -AsSecureString "SHOPIFY_API_SECRET"; $v = [Net.NetworkCredential]::new('', $s).Password
    supabase secrets set "SHOPIFY_API_SECRET=$v"; Remove-Variable s, v
  New random secrets (PAY_TOKEN_SECRET, CRON_SECRET) come from the crypto random generator, not Get-Random:
    $b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    $v = [Convert]::ToBase64String($b)
  CRON_SECRET is also needed in Vault (step 5): the runbook copies it with Set-Clipboard, you paste it in
  Dashboard > Vault, then `Set-Clipboard -Value ' '` clears the clipboard. Never `supabase secrets set
  --env-file`, never `-p <password>` on supabase link (type it at the prompt), never a value written after `=`
  on the command line. The anon key for the APK build (step 9) uses the same hidden-prompt pattern.
  Step 4b (D199): `supabase unlink` after the last deploy / secrets command, so this folder is local-only again.
- ops/e2e_queries.sql - read-only SELECTs for Studio: verification times (+ median), heartbeat gaps, rejected SMS
  by reason, order syncs not done, open alerts. Column rules (D200): never `*`; never sms_messages.body,
  payer_number, trx_id, sender; payment_sessions.token_hash; stores.token_secret_id; devices.public_key_spki,
  install_id; wallets.wallet_number; audit_log.data (holds merchant notes); alerts.details; merchant emails.
  Only SELECT / WITH ... SELECT; no data-changing CTE and no call to functions with side effects (cron.*, net.*,
  vault.*, private.*, set_config, pg_sleep).
- tests/e2e/E2E_CHECKLIST.txt - tests A-P word for word, a results table (id | operator | result PASS/FAIL/not
  tested | time | notes) left empty, the three summary lines (median time, phoneSilent count in P, failing
  items -> spec 14a/14b ...). Top of the file: how to write a real SMS sample (the format in section 4, the
  fake-number list of D185) and a warning line: "Notes: no phone numbers, emails, TrxIDs, tokens or keys" -
  the checklist is a repo file you fill by hand.

### Database
- supabase/migrations/<timestamp>_schedules.sql - pg_cron + pg_net jobs every 5 minutes for claims-expire,
  shopify-sync and alerts-check, through one guarded function (section 3). Created with
  `supabase migration new schedules` once the CLI exists (D180); never edits an older migration.
- supabase/migrations/<timestamp>_load_parser_rules.sql - [NEEDS YOUR YES, D183] one SQL function
  load_parser_rules(p_version int, p_rules jsonb) that refuses an existing version and, in one transaction,
  deactivates the old row and inserts the new active one (service_role only).
- supabase/tests/schedules_test.sql - pgTAP: the three jobs exist with "*/5 * * * *"; the call function with no
  Vault secrets returns false and queues no HTTP request; EXECUTE is not granted to anon/authenticated.
- supabase/tests/load_parser_rules_test.sql - pgTAP: new version -> only active; existing version -> error and
  nothing changed; not executable by anon/authenticated (only with D183).

### Scripts
- supabase/scripts/load_parser_rules.ts - reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from the terminal
  environment, reads supabase/functions/_shared/parser_rules.json, version = the file's version (D184), calls the
  rpc once; prints only "<version> loaded" or a fixed short error (never the URL, key or rules). Uses spec 12a's
  pinned supabase-js (no new package).
- supabase/functions/tests/load_parser_rules_test.ts - unit: argument/env checks and the printed text with a fake
  client (also: a failing call prints a fixed message, never the URL, key, rules or a database error text);
  integration (BDPAY_TEST_DB=1, assertLocal first, SUPABASE_URL set explicitly to local): runs the script with
  the version that is already loaded (seed version 1) -> refused, exit code 1, parser_rules unchanged. It never
  loads a new version: a loaded row can never be deleted (CLAUDE.md), and a new active version would change
  what the local server and phone use. The success path is tested by pgTAP inside a rolled-back transaction
  (load_parser_rules_test.sql).

### Real SMS samples and tests (section 4)
- tests/real_sms/<operator>_<nn>_<what>.sms + .expected.json - your samples (you add them; I never invent "real"
  ones). No other file in this folder (the format description lives at the top of E2E_CHECKLIST.txt, which is
  in Scope, instead of an extra FORMAT.txt).
- app/test/domain/real_sms_test.dart - Dart: every "keep" sample parses to the expected fields.
- app/android/app/src/test/kotlin/com/bdpay/verifier/RealSmsTest.kt - Kotlin: SmsFilter keeps or drops each sample
  as expected, with the expected operator.
- supabase/functions/tests/real_sms_test.ts - Deno: filterSms + parseSms give the expected keep/drop and fields.
- [CHANGED 06/08] app/android/app/src/main/res/raw/parser_rules.json and supabase/functions/_shared/parser_rules.json
  - rule fixes from your samples, same change in both (parser_rules_copy_test keeps them equal), version raised
  (D184). Rules of an operator you could not test keep their "SAMPLE" note.

### Repo scan
- supabase/functions/tests/repo_scan_test.ts - [NEEDS YOUR YES as a new test file, D191] searches every text file
  in the project (skipping build/, .dart_tool/, node_modules/, .git/, binary files, and the .env* files,
  keystores and key.properties, which are never opened) for JWT-shaped strings, "service_role" keys, Shopify
  token prefixes (shpat_, shpca_, shpss_), PEM private keys, long base64 strings next to SECRET/KEY/TOKEN names,
  and Bangladeshi phone numbers not on the fake-number list (D185). Prints only file path + kind, never the
  match. Also checks the ops files (D201): e2e_queries.sql follows the column and statement rules above; the
  runbook has steps 1-9 each ending with "check:", has no `secrets set NAME=<literal>`, no `--env-file`, no
  `-p ` on link, and its deploy list matches section 2 for every folder in supabase/functions/; the checklist
  has A-P and an empty results table; every rule in both parser_rules.json files has the same version (D184).

### Earlier files touched only if a sample needs it
- None planned. If a real SMS cannot be handled by a rules-only fix (for example a new amount layout the parser
  code does not support), I stop and ask: that is a parser code change, which belongs in a 14a spec.

## 2. Edge Functions and --no-verify-jwt

With verify_jwt on, Supabase's gateway rejects any request without a valid Supabase JWT before our code runs
(including CORS preflight OPTIONS). Functions that are called by something other than a signed-in app user must
turn it off; they check their own credential instead.

| Function | Caller | Own check | --no-verify-jwt |
|---|---|---|---|
| sms-ingest, device-heartbeat, device-deactivate, parser-rules, sms-status | the phone's background jobs | ECDSA device signature (spec 08) - no user token; works while the app is closed and signed-out tokens expire | yes |
| pay-session | customer's browser on the pay page | session token + rate limits; must answer CORS OPTIONS | yes |
| shopify-oauth-callback | Shopify redirect (GET in the merchant's browser) | Shopify query HMAC + single-use state | yes |
| shopify-webhooks | Shopify servers | X-Shopify-Hmac-Sha256 | yes |
| shopify-paylink | checkout extension | Shopify session token (a JWT signed by Shopify with SHOPIFY_API_SECRET, not a Supabase JWT - the gateway would reject it); must answer CORS OPTIONS | yes |
| claims-expire, shopify-sync, alerts-check | pg_cron through pg_net | X-Cron-Secret = CRON_SECRET | yes |
| device-register | the app, signed in | Supabase user token (checked by the handler too) | no |
| claim-review, shopify-connect-link, shopify-status, alerts-list | the app, signed in | Supabase user token | no |

Each "yes" function must also refuse when its own secret is missing (D202): an empty or unset CRON_SECRET,
SHOPIFY_API_SECRET or PAY_TOKEN_SECRET must never compare equal to an empty header or produce a computable HMAC
or token (fail closed, constant-time compare). This is code from specs 09-11; spec 14 adds no feature, so before
the runbook is used I check it with tests (table in section 5). A function that does not fail closed is written
up as spec 14a and the runbook says not to deploy until it is fixed.

Runbook step 4 deploys each function by name: `supabase functions deploy <name> --no-verify-jwt` for the 12 "yes"
rows, `supabase functions deploy <name>` for the 5 "no" rows (17 functions; the list is checked against the
folders in supabase/functions/ when the runbook is written, so a later function is not forgotten). No
supabase/config.toml [functions] entries are needed (D187).

## 3. Schedules migration: Vault read, safe when secrets are missing

```
create extension if not exists pg_cron;
create extension if not exists pg_net;

create schema if not exists private;          -- not exposed by the API
revoke all on schema private from public, anon, authenticated;

create or replace function private.call_cron_function(p_fn text) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_url text; v_secret text;
begin
  if p_fn not in ('claims-expire', 'shopify-sync', 'alerts-check') then return false; end if;
  select decrypted_secret into v_url    from vault.decrypted_secrets where name = 'functions_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'cron_secret';
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    return false;                              -- local / not set up: do nothing, no error
  end if;
  perform net.http_post(
    url := rtrim(v_url, '/') || '/' || p_fn,
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-Cron-Secret', v_secret),
    timeout_milliseconds := 10000);
  return true;
end $$;
revoke execute on function private.call_cron_function(text) from public, anon, authenticated;

select cron.schedule('bdpay-claims-expire', '*/5 * * * *', $$select private.call_cron_function('claims-expire')$$);
select cron.schedule('bdpay-shopify-sync',  '*/5 * * * *', $$select private.call_cron_function('shopify-sync')$$);
select cron.schedule('bdpay-alerts-check',  '*/5 * * * *', $$select private.call_cron_function('alerts-check')$$);
```

- No URL or secret is in the migration, in cron.job (the command is only the function name) or in
  cron.job_run_details. They are read from Vault at run time, inside the function.
- Missing Vault secrets (local) -> the function returns false: no HTTP request, no exception, the cron run is
  recorded as succeeded. A missing secret is never an error that fills the logs every 5 minutes.
- The allow-list of three names means the function cannot be used to send the cron secret anywhere else.
- cron.schedule with a job name replaces a job of the same name, so re-applying is safe; no unschedule/DROP.
- pg_net is asynchronous: the secret sits in net.http_request_queue until sent and the response (not the request
  headers) in net._http_response; both are readable only by postgres / supabase_admin, not by API roles. Noted in
  the runbook (D188).
- Spec 12 put schedules in spec 15; spec 14 brings them forward (the current spec wins, D182).
- Local check (once Docker exists, and after your yes - it changes the local database): `supabase migration up
  --local` (applies only new migrations - never `db reset`), then `supabase test db --local` (schedules_test.sql,
  inside a rolled-back transaction) and in Studio `select count(*) from net.http_request_queue` -> 0 after the
  jobs ran.

## 4. One folder of real SMS, three test suites

Folder tests/real_sms/ at the repo root, shared by all three languages:

```
tests/real_sms/
  bkash_01_received.sms           line 1: sender; lines 2..end: the body exactly as received
  bkash_01_received.expected.json
  bkash_05_otp.sms
  bkash_05_otp.expected.json
  ...
```

- .sms: UTF-8 without BOM; line 1 = sender exactly as shown by the phone; the rest = body. Line ends: CRLF is
  turned into LF (Windows editors), then exactly one final LF is removed; nothing else is trimmed (spaces and
  blank lines inside the body are kept, they are part of the layout).
- .expected.json: `{"keep": false}` or
  `{"keep": true, "operator": "bkash", "trxId": "9K48X7Z2", "amountPoisha": 125000, "payerNumber": "01700000001", "kind": "received"}`
  (payerNumber null when the SMS has none; kind = received | payment as the parser names it).
- Every .sms must have its .expected.json and the reverse; a missing partner fails all three suites. Any other
  file in the folder fails them too (so nothing else - notes, screenshots - can slip in).
- Every phone number in a sample or expected file must be on the fake list (D185); the repo scan fails otherwise.
- Test output never prints a sample's body or numbers: a failure message names the file and the field
  (for example "bkash_02_received: amountPoisha differs"), not the values.
- Readers (about 20 lines each, no package):
  - Dart (`flutter test`, cwd app/): `Directory('../tests/real_sms')`, rules from
    android/app/src/main/res/raw/parser_rules.json (as the other Dart parser tests do); each keep sample ->
    parseSms(sender, body, rules) == expected fields. Drop samples: Dart has no filter (the phone filters in
    Kotlin), so Dart checks only keep samples (D189).
  - Kotlin (`./gradlew :app:testDebugUnitTest`, cwd app/android/app): walks up to the folder that contains
    tests/real_sms (as AndroidSignatureFixtureTest does); SmsFilter with the bundled rules, monitoring on, all
    operators on, an in-memory InboxWriter: keep -> stored with the expected operator; drop -> any of
    senderNotTrusted / blocked / notIncoming. SmsFilter does not extract TrxID or amount, so Kotlin checks
    keep/drop + operator only (D189).
  - Deno (`deno test --allow-read`): path from import.meta.url (../../../tests/real_sms); filterSms + parseSms with
    _shared/parser_rules.json: keep -> "keep" and every field equal; drop -> not "keep". The server also needs
    the message to parse: a keep sample that filters "keep" but fails parseSms is a failure (the server would
    store it as parseFailed).
- One test per file in each suite (named after the file), so a failure names the sample. An empty folder ->
  every suite passes with a "0 samples" note, so the suites can exist before you collect anything.
- Every run tests every sample (edge case "a fix must not break an older sample").
- Order of work when a sample fails: add the sample first, see it fail in all suites, change both rules files,
  raise the version, all suites green - never edit a sample to fit the rules.

## 5. Acceptance criteria -> test or check

| Criterion | Test or check | Can run now? |
|---|---|---|
| flutter test passes (earlier tests too) | `cd app; flutter test` | yes |
| Kotlin tests pass | `cd app\android; .\gradlew.bat :app:testDebugUnitTest` | yes |
| deno test passes | `deno test --allow-read supabase/functions/tests` | yes |
| supabase test db passes | `supabase test db` (local) | no - needs spec 12 + Supabase CLI + Docker |
| Every tests/real_sms file gives its expected result in Dart, Kotlin and Deno | real_sms_test.dart, RealSmsTest.kt, real_sms_test.ts (+ pairing check) | yes once you add samples |
| parser_rules.json copies stay equal after fixes; version raised | parser_rules_copy_test.ts + repo_scan_test.ts (one version on every rule, D184) + the new version written in the checklist header and compared by review | yes |
| No-verify-jwt functions check their own credential | existing Deno tests per function (device signature, HMAC, session token, X-Cron-Secret) | after specs 09-11 |
| ... and fail closed when their secret is empty (D202) | a Deno test per function: CRON_SECRET / SHOPIFY_API_SECRET / PAY_TOKEN_SECRET set to "" -> refused even with an empty header | after specs 09-11 |
| Runbook lists exactly which functions need --no-verify-jwt | repo_scan_test.ts: the deploy lines match section 2 for every folder in supabase/functions/ | yes |
| Every runbook step ends with a "check" line | repo_scan_test.ts (D201) | yes |
| Checklist holds A-P and an empty results table | repo_scan_test.ts (D201) | yes |
| Schedules migration applies locally without errors | `supabase migration up` | no - blockers |
| ... and does nothing locally without the Vault secrets | schedules_test.sql (returns false, net.http_request_queue unchanged) + Studio check | no - blockers |
| No URL or secret in the migration | repo_scan_test.ts + a grep of the migration for "http" and "secret" values | yes |
| load_parser_rules.ts refuses an existing version (against local Supabase) | load_parser_rules_test.ts integration (BDPAY_TEST_DB=1, existing version only, nothing written) + load_parser_rules_test.sql (rolled back) | no - blockers (unit part yes) |
| load_parser_rules.ts prints only version and "loaded" | load_parser_rules_test.ts unit (captured output) | yes |
| e2e_queries.sql is SELECT only and shows no body/payer/token | repo_scan_test.ts (D200, D201): only SELECT / WITH ... SELECT; no INSERT/UPDATE/DELETE/MERGE/TRUNCATE/DROP/ALTER/CREATE/GRANT/COPY/CALL anywhere (also inside WITH); no cron./net./vault./private./set_config/pg_sleep calls; no `*`; none of the D200 columns | yes |
| Runbook never puts secrets in files (or the shell history) | repo_scan_test.ts over ops/ (no secret-shaped values; no `secrets set NAME=<literal>`, no `--env-file`, no `link -p`) + review of the hidden-prompt pattern (D198) | yes |
| A search shows no secret values, keys or real phone numbers in the repo | repo_scan_test.ts (D185, D191) | yes |
| Checklist A-P PASS or "not tested", median < 10 s, P has 0 false phoneSilent | you, on staging, with E2E_CHECKLIST.txt and e2e_queries.sql | after B (D180) |
| Claude Code runs nothing online | the command rules at the top of this plan (explicit --local, project-ref check, local SUPABASE_URL set per command, assertLocal) | always |
| CLAUDE.md "ask before changing data": local migration up, a local Docker/CLI install | I ask before each (section 7) | always |

## 6. Unclear or wrong in the spec

Blocking: D180 (everything spec 14 assumes is missing), D183 (load in one call needs a SQL function).

- D181. **"Specs 01 to 13a are done and pass locally" is not true** (section 0). 13a itself is built, but its
  manual checks never ran, for the same reasons.
- D182. **Schedules: spec 12 says "schedules with pg_cron (spec 15)"; spec 14 brings them here.** The current
  spec wins; noted so spec 15 does not add them again.
- D183. **"In one call: inserts the new version, makes it the only active one" cannot be done with plain
  supabase-js calls.** The partial unique index on is_active means the new row cannot be inserted active while
  the old one is active, and two separate calls are not one transaction (a failure in between leaves no active
  rules - the server would then reject every SMS). Proposal: a second new migration with
  load_parser_rules(p_version, p_rules) (plpgsql, security definer, fixed search_path, service_role only):
  refuse if the version exists; update the old active row to false; insert the new active row; one transaction.
  The script calls it with one rpc. The spec lists only the schedules migration -> needs your yes.
- D184. **Which "version" is loaded.** Each rule in parser_rules.json has its own "version"; the server's version
  is the highest one (plan 08 D70), and since plan 13a the phone compares the server's parser_rules row version.
  Proposal: every rules fix sets the SAME new number on every rule in both files (file version = max = the
  loaded row version), so the bundled app, the server and the phone agree. Not raising untouched operators would
  also work but makes the version harder to read.
- D185. **"Replace phone numbers with other numbers of the same format" may be someone else's real number.**
  Proposal: use only numbers from a fixed fake list written in FORMAT.txt - 01700000001 to 01700000099 (11 digits)
  and 017000000001 to 017000000099 (12 digits, Rocket) - so the repo scan can tell fakes from real numbers.
  Existing tests already use other made-up numbers (for example 017123456789, 01798765432); the scan keeps a
  short allow-list of those exact strings rather than changing old tests.
- D186. **TrxIDs and amounts stay real.** They come from your own small test payments, so they are not customer
  data; still, only samples from your own test payments go into the repo (FORMAT.txt says so). Names -> "X".
- D187. **Runbook step 4 deploys by name**, because there is no supabase/config.toml in the repo (section 0); if
  spec 12 later adds one with [functions.<name>] verify_jwt = false entries, the runbook can use a plain
  `supabase functions deploy`. Either way the 12 names in section 2 are the list.
- D188. **pg_net keeps the request (with X-Cron-Secret) in net.http_request_queue until it is sent** and logs
  responses in net._http_response. Both are private to the database owner roles, not to API users. Noted in the
  runbook; no change.
- D189. **Spec says each sample is tested in Dart, Kotlin (SmsFilter) and Deno, but the three do different
  jobs.** Kotlin SmsFilter only keeps or drops (it never extracts TrxID or amount); Dart only parses (the phone's
  filter is Kotlin). So: Kotlin = keep/drop + operator; Dart = fields of keep samples; Deno = both. Together every
  expected value is checked at least once and keep/drop twice.
- D190. **Runbook step 7 says to edit pay_page/config.js and the CSP for staging.** Doing that in the repo would
  break local development and put the staging URL in git. Proposal: the runbook copies pay_page/ to a folder
  outside the repo (for example %TEMP%\bdpay_pay_page_staging), edits config.js and the CSP there, and uploads that
  copy. The same for step 8: shopify.app.toml and src/config.ts are filled by `shopify app config link` (spec 10a
  placeholders); the staging FUNCTIONS_URL is not a secret, so committing it there is your choice - the runbook
  asks you, it does not decide.
- D191. **The repo scan is a new test file** not named in the spec (the spec only says "a search shows").
  Proposal: an automated Deno test, so the search is repeatable; it never opens .env* files (CLAUDE.md) and never
  prints a matched value. Without your yes I give you the search commands instead and report what they find.
- D192. **`supabase db push` and seed.sql.** db push does not run seed.sql unless --include-seed is given; the
  runbook says never to add it (seed has local test users). The staging parser_rules table is therefore empty
  until step 2's load_parser_rules.ts - the runbook orders it right after db push.
- D193. **load_parser_rules.ts has no local-only guard** (it is meant for staging). Claude Code runs it only
  against local Supabase (CLAUDE.md); it prints nothing that identifies the target, so the runbook shows you
  `echo $env:SUPABASE_URL` before running it.
- D194. **Release APK signing.** app/android/app/build.gradle.kts signs release builds with the debug key ("for
  now"). Fine for a sideloaded staging test; not for a store release (out of scope). The SUPABASE_ANON_KEY goes
  only on the build command line, never into a file.
- D195. **Test P will probably show false phoneSilent alerts.** The heartbeat is a WorkManager chain of 5-minute
  one-time jobs; under Doze on an idle phone Android runs them in maintenance windows that can be 1-2+ hours
  apart, while phoneSilent opens after 15 minutes. The spec already routes this to 14a; I note it so the result
  is not a surprise.
- D196. **e2e_queries.sql heartbeat gaps.** devices keeps only last_seen_at, but device-heartbeat writes an
  audit_log "device.heartbeat" row on every call (spec 08), so the history is kept: gaps = lag(created_at) over
  audit_log where action = 'device.heartbeat', per device, last 48 hours. Verification time uses
  sms_messages.server_received_at (the phone's received_at can be clamped or skewed) as well as received_at, and
  shows both.
- D197. **BDPAY_FAKE_MAILER=1 on staging** means no alert email is really sent; test P counts alert rows in the
  alerts table, not emails. Matches the spec (real email is spec 15).

- D198. **Secrets on the command line end up in the PowerShell history file** (PSReadLine saves every command
  line to ConsoleHost_history.txt), and Read-Host without -AsSecureString shows the value on screen. The runbook
  uses the hidden-prompt + variable pattern in section 1, so only variable names reach the history. Get-Random is
  not a crypto generator; new secrets use RandomNumberGenerator.
- D199. **`supabase link` (runbook step 2) writes supabase/.temp/ in this project folder** and from then on some
  CLI commands default to the linked staging project. The runbook adds step 4b `supabase unlink` after the last
  online command; my command rules (top of this plan) stop if a project ref is present.
- D200. **Columns e2e_queries.sql must never select**, beyond the spec's body/payer/tokens: trx_id and sender
  (payment details), token_hash, token_secret_id, public_key_spki, install_id, wallet_number, audit_log.data
  (merchant review notes), alerts.details, emails. Counts, ids, statuses, reasons and times only.
- D201. **Spec criteria "each runbook step ends with a check line", "list exactly which functions need
  --no-verify-jwt" and "checklist with an empty results table" had no check**; repo_scan_test.ts covers them.
- D202. **A --no-verify-jwt function with an empty secret is open to anyone.** If CRON_SECRET, SHOPIFY_API_SECRET
  or PAY_TOKEN_SECRET is unset on staging (a typo in step 3), a plain `header === env` compare or an HMAC with an
  empty key would let anyone call the cron functions, forge webhooks / OAuth callbacks / session tokens, or
  compute pay tokens. Specs 09-11 must fail closed; spec 14 only checks it (tests above) and the runbook's step 3
  "check:" line lists the secret names with `supabase secrets list` (names and digests only, no values).

## 7. Order of work (after your answers)

0. Ask before: installing the Supabase CLI and Docker (your machine), and each local `supabase migration up
   --local` (changes the local database).
1. The three suites (pass with 0 samples) and the format text at the top of E2E_CHECKLIST.txt. flutter analyze,
   flutter test, Kotlin tests, deno check/lint/test after this group.
2. ops/e2e_queries.sql, tests/e2e/E2E_CHECKLIST.txt, ops/staging_runbook.txt; repo_scan_test.ts (D191).
3. load_parser_rules.ts (+ unit test) and, with D183, its migration and pgTAP test.
4. Schedules migration + pgTAP test.
5. When you add samples: rules fixes (D184) until all three suites are green.
6. Steps 3-4's local database checks wait for the blockers; I report them as not run.

## 8. Review changes (2026-10-30)

- Online commands: command rules at the top (explicit --local, a fixed list of allowed supabase commands, stop if
  supabase/.temp/project-ref exists, SUPABASE_URL set to local per command + assertLocal); runbook step 4b
  `supabase unlink` (D199); the load_parser_rules integration test only checks the refusal and writes nothing.
- Secrets and numbers in files: hidden-prompt + variable pattern so no secret reaches the screen, the PowerShell
  history file or any file; crypto random for new secrets; clipboard cleared after the Vault paste; no
  --env-file, no `link -p` (D198); the checklist warns against numbers, emails, TrxIDs and tokens in notes; the
  real-SMS folder accepts only .sms/.expected.json pairs with fake-list numbers, and test failures never print
  sample contents; FORMAT.txt dropped (out of Scope) - the format is at the top of the checklist; the scan also
  skips keystores and key.properties.
- e2e_queries.sql: a full forbidden-column list (D200) and statement rules that also catch data-changing WITH
  clauses and side-effect functions; no `*`.
- --no-verify-jwt: every listed function checks its own credential, but an empty secret could open it; fail-closed
  tests added as checks (D202).
- Checks added: runbook "check:" lines, the no-verify-jwt list against the function folders, the checklist
  layout, one version on every rule, fail-closed secrets, CLAUDE.md "ask before changing data" for local
  migration runs.
