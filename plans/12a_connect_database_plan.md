# Plan 12a - Connect the Edge Functions to the database

Spec: specs/12a_connect_database.md. Written 2026-10-30.
Read with: CLAUDE.md, specs 08-12, supabase/functions/_shared/store.ts and fake_store.ts (spec 08, built), and
plans/12_database_plan.md (spec 12's migrations are planned, not written - see section 0).

Reviewed 2026-10-30 against the spec and CLAUDE.md (section 8 lists what the review changed).

Default rule: until you answer a decision below, the build follows the spec text; where the spec cannot work as
written (section 0, D114-D117) I stop and ask.

## 0. Blockers - what spec 12a assumes vs what exists today

| Spec 12a assumes | Today | Effect |
|---|---|---|
| Spec 12 done, "supabase test db" passes | No supabase/migrations at all. Spec 12 is waiting for a database connection (your choice of the bdpay_dev password file or a throwaway server on port 5433), the pgTAP download and D88 | No SQL functions to call; PgStore cannot be tested |
| Local Supabase running ("supabase start") | No Docker and no Supabase CLI ("next time Supabase"). Plain Postgres has no PostgREST and no auth server, and supabase-js talks only to those | PgStore and SupabaseUserVerifier cannot run against plain Postgres at all; contract tests on PgStore, integration tests and smoke tests all need real local Supabase |
| Specs 08-11 done (their Store methods, handlers, smoke scripts) | Spec 08 is fully built. Spec 09: only match_rules.ts. Spec 10: only the pure helpers. Spec 11: only alert_rules / alert_messages / mailer. store.ts and fake_store.ts have spec 08's 11 methods only; pay-session, claim-review, sms-status, claims-expire, all shopify-* functions, alerts-check, alerts-list, smoke_match.ts and smoke_shopify.ts do not exist | 39 of the 50 Store methods have no FakeStore to compare against; integration flows 1-5 need spec 09 handlers, flow 1 also spec 10's notifier, flow 6 spec 11's alerts-check |

- D114. **Build order.** Options: A (recommended) finish specs 09, 10 and 11 (their Store additions, FakeStore,
  handlers, smoke scripts), then spec 12 on real local Supabase, then 12a in full. B build 12a now for spec 08's 11
  methods only (PgStore part, contract suite, store_factory), untestable against a database until Supabase runs,
  and extend it as 09-11 land. C wait.
- D115. **What can be built and tested now without Supabase** (whatever D114 says): mappers.ts with unit tests,
  store_factory.ts with unit tests, the contract suite running against FakeStore, the local-only guard and
  test-merchant helpers (unit-tested with a fake admin client). PgStore and the user verifier can be written but not
  run.

## 1. Store methods -> PgStore -> contract test

"q" = supabase-js query builder on a table (always .eq("merchant_id", ...) where the method has a merchantId);
"rpc" = a spec 12 SQL function. Contract test names are in tests/store_contract/contract.ts. Methods marked
"no merchantId" cannot be filtered by merchant (D119).

### Spec 08 (built in FakeStore)

| Store method | PgStore | Contract test |
|---|---|---|
| findMerchantForUser(userId) | q merchants .eq(owner_id) .maybeSingle() | merchant: owner found; other user -> null |
| countActiveDevices(merchantId) | q devices count exact, head, .eq(merchant_id) .eq(status, active) | devices: count active only, per merchant |
| findDeviceByInstall(merchantId, installId) | q devices .eq(merchant_id) .eq(install_id) .maybeSingle() | devices: find by install; other merchant -> null |
| createDevice(fields) | q devices insert .select().single() | devices: create returns the full record |
| updateDevice(deviceId, fields) | q devices update .eq(id) .select().single() (no merchantId) | devices: update fields; unknown id -> StoreError notFound |
| getDevice(deviceId) | q devices .eq(id) .maybeSingle() (no merchantId) | devices: get; unknown -> null |
| getParserRules() | q parser_rules .eq(is_active, true) .single() | rules: version 1 from seed, rules is the array |
| listActiveWallets(merchantId) | q wallets .eq(merchant_id) .eq(is_active, true) | wallets: active only, own merchant only |
| findSmsByDedupe(merchantId, hash) | q sms_messages .eq(merchant_id) .eq(dedupe_hash) .maybeSingle() | sms: find by dedupe; other merchant -> null |
| insertSms(record) | rpc insert_sms | sms: new -> created true; same hash -> created false + same row; 5 parallel -> one row |
| writeAudit(entry) | q audit_log insert (no select) | audit: entry written with all fields (read back through the test admin client) |

### Spec 09 (not built in TS yet)

| Store method | PgStore | Contract test |
|---|---|---|
| createPaymentSession(fields) | q payment_sessions insert; on 23505 (store_id, external_order_id) -> select the existing row .eq(store_id) .eq(external_order_id) .eq(merchant_id) - no row for this merchant -> StoreError conflict (D128) | sessions: create; same store + order twice -> same session; another merchant's store id -> conflict |
| getSessionByTokenHash(hash) | q payment_sessions .eq(token_hash) .maybeSingle() (no merchantId) | sessions: by token hash; unknown -> null |
| getMerchantName(merchantId) | q merchants .eq(id) select business_name | merchant: name |
| hasDeviceSeenSince(merchantId, time) | q devices count, .eq(merchant_id) .eq(status, active) .gte(last_seen_at) | devices: seen since true / false; revoked ignored |
| findLiveClaimByTrx(m, op, trx) | q payment_claims .eq x3 .in(status, [pending, verified, mismatch]) .maybeSingle() | claims: live found; superseded / expired -> null |
| submitClaim({...}) | rpc submit_claim | claims: decrement 5 -> 4; supersede; alreadyUsed; noAttemptsLeft |
| findUnmatchedSms(m, op, trx) | q sms_messages .eq x3 .eq(status, unmatched) .maybeSingle() | sms: unmatched found; matched -> null |
| findPendingClaimByTrx(m, op, trx) | q payment_claims .eq x3 .eq(status, pending) .maybeSingle() | claims: pending found |
| recordVerified({...}) | rpc record_verified -> "ok" / "conflict" | match: ok sets all four rows; conflict (second SMS, second claim) and every row unchanged after it (maker.snapshot(merchantId) before and after) |
| recordMismatch({...}) | rpc record_mismatch | match: mismatch sets claim + candidate + session |
| recordRejected({...}) | rpc record_rejected | match: rejected only from mismatch |
| findMismatchClaimBySms(smsId) | q payment_claims .eq(candidate_sms_id) .eq(status, mismatch) .maybeSingle() (no merchantId) | match: found after mismatch |
| getSmsResults(merchantId, smsIds) | q sms_messages .eq(merchant_id) .in(id) with embedded payment_claims (candidate_sms_id) and matches -> payment_claims -> payment_sessions; each embedded table also filtered .eq(<embedded>.merchant_id, merchantId) | results: verified / mismatch / rejected / pending shapes; other merchant's ids left out |
| expireDue(now) | rpc expire_due(p_now) | expiry: counts; mismatch not expired |
| hitRateLimit(key, limit, window) | rpc hit_rate_limit | rate: up to limit; limit + 1 denied; 10 parallel with limit 5 -> exactly 5 |
| getClaim(id), getSession(id) | q .eq(id) .maybeSingle() (no merchantId) | claims / sessions: get; unknown -> null |

### Spec 10 (not built in TS yet)

| Store method | PgStore | Contract test |
|---|---|---|
| createInstallState(merchantId, shopDomain) | random state in TS, q shopify_install_states insert (state_hash, expires_at = now + 10 min) | install: create then consume ok |
| consumeInstallState(state) | rpc consume_install_state(sha256(state)) | install: second consume -> null; expired -> null |
| upsertShopifyStore({merchantId, shopDomain}) | q stores insert; on 23505 select by shop_domain: other merchant -> conflict, same -> update status active + connected_at | stores: create; reconnect same row; other merchant -> conflict |
| saveShopifyTokens / getShopifyTokens | rpc save_shopify_tokens / get_shopify_tokens | tokens: save, get, save again, row has no token text |
| removeShopifyTokens(storeId) - new Store name for spec 10's "remove its tokens" (plan 10 D40) | rpc delete_shopify_tokens | tokens: remove -> get null |
| getStoreByShopDomain(shop) | q stores .eq(shop_domain) .maybeSingle() (no merchantId) | stores: by domain |
| getStoreForMerchant(merchantId) | q stores .eq(merchant_id) .order(status) ("active" sorts before "uninstalled") .order(created_at, desc) .limit(1) | stores: active preferred; other merchant -> null |
| setStoreStatus(storeId, status, lastError) | q stores update .eq(id) | stores: status + lastError |
| markWebhookSeen(webhookId) | rpc mark_webhook_seen | webhooks: true then false |
| findSessionByExternalOrder(storeId, orderId) | q payment_sessions .eq(store_id) .eq(external_order_id) .maybeSingle() | sessions: by order |
| expireSessionForOrder(storeId, orderId) | q payment_sessions update status expired .eq(store_id) .eq(external_order_id) .in(status, [open, pending]) | sessions: open -> expired; verified untouched |
| enqueueOrderSync(sessionId) | read the session's merchant_id, q order_syncs insert (merchant_id from the session); on 23505 select .eq(session_id) | syncs: one per session; merchant_id = the session's |
| listDueOrderSyncs(now, limit) | q order_syncs .eq(status, pending) .lte(next_attempt_at, now) .order(next_attempt_at) .limit, joined to stores for reconnectNeeded (global: no merchantId) | syncs: due only; reconnectNeeded skipped - with the global-method rules of section 3 |
| updateOrderSync(id, fields) | q order_syncs update .eq(id) | syncs: update |

### Spec 11 (not built in TS yet)

| Store method | PgStore | Contract test |
|---|---|---|
| listAlertInputs(now) | rpc list_alert_inputs(p_now) (global) | alerts: the test's own merchant's input row has the expected fields; other rows ignored |
| listOpenAlerts(merchantId) | q alerts .eq(merchant_id) .eq(status, open) | alerts: open only, own merchant |
| openAlert(m, kind, details) | q alerts insert; on 23505 select .eq(merchant_id) .eq(kind) .eq(status, open) | alerts: second open of the same kind returns the existing one |
| markAlertSent(id, sentAt) | read send_count, then update .eq(id) .eq(send_count, n) (compare-and-set; retry once) | alerts: sendCount + 1 |
| resolveAlert(id, resolvedAt) | q alerts update .eq(id) | alerts: resolved |
| createEventAlert(m, kind, details) | q alerts insert; on 23505 select .eq(merchant_id) .eq(kind) .eq("details->>syncId", syncId) | alerts: same syncId twice -> one |
| listUnsentEventAlerts(limit) | q alerts .eq(kind, syncFailed) .is(last_sent_at, null) .order(opened_at) .limit (global) | alerts: unsent only - with the global-method rules of section 3 |
| getMerchantContact(merchantId) | **nothing yet** - needs spec 12's D88 (get_merchant_contact rpc, or an email column) | contact: email + businessName - BLOCKED (D88). The spec's contract list requires this test, so 12a cannot pass in full until D88 is answered |

Every method that has a merchantId filters by it in every query it makes - including the read after a unique
violation and every embedded table. Methods without a merchantId: D119.

## 2. Files

### New - supabase/functions/
- deno.json - imports map with "@supabase/supabase-js": "npm:@supabase/supabase-js@<exact version>" (D116; asked
  first); no other settings, so deno fmt / lint behave as today.
- _shared/pg_store.ts - PgStore implements Store with supabase-js (service role): query builder and rpc only.
- _shared/mappers.ts - one function per record type each way (rowToDevice, deviceToRow, ...); timestamps normalized
  to toISOString() (Postgres returns "+00:00", FakeStore ".000Z"); bigint money checked as safe integers.
- _shared/store_factory.ts - depsFor(env): BDPAY_FAKE_STORE=1 -> FakeStore; SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
  -> PgStore + SupabaseUserVerifier; else null (503 storeNotReady).
- _shared/supabase_user_verifier.ts - UserVerifier: auth.getUser(token) on the local auth server -> {userId} | null.
- tests/store_contract/contract.ts - runContract(maker): every contract test in section 1, taking a StoreMaker.
- tests/store_contract/makers.ts - StoreMaker interface (newStore, newMerchant, addWallet, addDevice, addStore,
  clock) and the two makers: fakeMaker (FakeStore) and pgMaker (PgStore + test admin client).
- tests/store_contract/fake_store_contract_test.ts - runContract(fakeMaker); always runs.
- tests/store_contract/pg_store_contract_test.ts - runContract(pgMaker); runs only with BDPAY_TEST_DB=1, else every
  test is reported "ignored".
- tests/integration/helpers.ts - assertLocal(url), admin client, newTestMerchant(), handler deps with PgStore,
  FakeMailer, FakeShopify.
- tests/integration/flows_test.ts - the 6 flows of the acceptance criteria.
- tests/integration/races_test.ts - the 3 race edge cases.
- tests/mappers_test.ts - each mapper both ways; time and bigint normalization (unit, no database).
- tests/store_factory_test.ts - the three env cases (unit, no database; PgStore built but not called).
- tests/pg_store_errors_test.ts - PgStore with supabase-js's custom fetch option pointed at a fake that returns
  PostgREST JSON (no database, no network): 23505 in each insert-then-read method -> the existing row; submit_claim
  conflict -> {conflict}; record_verified "conflict" -> "conflict"; any other error -> StoreError with a code and no
  row text; a merchant filter is present in every request URL of a merchantId method (checked from the fake's
  recorded URLs). Runs in the unit command.
- tests/local_guard_test.ts - assertLocal accepts localhost / 127.0.0.1 / [::1], refuses everything else.

### Changed
- _shared/store.ts - StoreError (code: notFound | conflict | db | ...); the spec 09-11 additions as they land;
  AuditEntry.merchantId nullable (spec 09 system entries); submitClaim result adds noAttemptsLeft;
  markWebhookSeen(webhookId, topic, shop) (D120).
- _shared/fake_store.ts - depsFromEnv moves to store_factory.ts; FakeStore gets the same small signature changes.
- _shared/http.ts - only if D117 = B ("internal" error code).
- device-register/index.ts, sms-ingest/index.ts, device-heartbeat/index.ts, device-deactivate/index.ts (and every
  later index.ts) - depsFor(...) from store_factory instead of depsFromEnv. Nothing else in handlers.
- tests/boundaries_test.ts - the index.ts line it checks; allowed supabase-js files: pg_store.ts,
  supabase_user_verifier.ts, tests/store_contract/makers.ts, tests/integration/helpers.ts.
- tests/serve_test.ts, tests/fake_store_test.ts - follow depsFromEnv's move.
- supabase/scripts/smoke_device.ts - a "served" mode (HTTP to supabase functions serve) next to the in-process mode
  (D80); it calls assertLocal first and prints only response JSON (never the magic-link token, the user token or
  the key); smoke_match.ts and smoke_shopify.ts get the same when specs 09 / 10 create them.

### Created by you (never read or written by me)
- supabase/functions/.env.local - the spec's dummy local values.
- supabase/functions/.env.test.local - SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY for deno test (D118). You make it
  with `supabase status -o env`; I never run that command (it prints the key).

## 3. Fresh merchants without deleting, and the local-only guard

Fresh data per test (nothing is ever deleted or truncated):
1. newTestMerchant() calls auth.admin.createUser({email: "t-<uuid>@bdpay.test", email_confirm: true}) - random
   address on a reserved test domain, no password (CLAUDE.md), so the user can never log in.
2. It inserts the merchants row (owner_id = the new user, business_name "Test <8 random chars>") with the admin
   client, plus whatever that test needs: wallets (random valid numbers: 01 + [3-9] + 8 random digits, retried on
   the rare unique clash), a device (fresh WebCrypto key), a store (shop "t-<uuid8>.myshopify.com").
3. Every id, TrxID ("T" + random), dedupe hash (from random text) and rate-limit key ("test:<64 random hex>") is
   new per test, so tests never see each other's rows and can run in any order or in parallel.
4. Assertions only look at rows of that test's merchant (or the ids it created).
5. Global methods see every merchant's rows, including rows left by earlier runs (they are never deleted):
   listAlertInputs, listDueOrderSyncs, listUnsentEventAlerts, expireDue, alerts-check and claims-expire. Rules:
   - assert only on the test's own ids (find them in the result), never on totals or on "the first row";
   - the list methods are called with a limit large enough to hold every leftover (1000) plus the own row, and the
     test fails with "too many leftovers - reset your local database" instead of a wrong result if the own row is
     not in it;
   - a test that leaves a due sync or an unsent event alert marks it done / sent at its end (an UPDATE, not a
     delete) so later runs see fewer leftovers;
   - flow 6 counts only mails whose `to` is the test's own merchant address (other leftover merchants may also get
     mails in the same alerts-check run);
   - test files run one after another (no --parallel) because expireDue / alerts-check act on all merchants; the
     race tests run their 20 rounds inside one file.
6. Shared global data: parser_rules (version 1 from seed) is read, never written, by tests.
7. The local database fills up with test merchants over time; that is expected. Cleaning it is yours to do
   (`supabase db reset`, asked first, per spec 12 D85).

FakeStore maker does the same through FakeStore.addOwner / addWallet etc., so runContract is identical for both.

Refusing a non-local database (tests/integration/helpers.ts, used by pgMaker and every integration and race test):
- Before any client is created: parse SUPABASE_URL with new URL(); hostname must be exactly "localhost",
  "127.0.0.1" or "[::1]" (no suffix tricks such as localhost.example.com), else throw "refusing: not a local
  database" and the test fails before any call. local_guard_test proves the rule.
- Also refused: BDPAY_TEST_DB unset (tests are ignored, not run), SUPABASE_URL missing.
- --allow-net on the command line is limited to 127.0.0.1:54321, localhost:54321 and [::1]:54321, so even a bug
  cannot reach another host (the second wall).
- The served smoke scripts call the same assertLocal on SUPABASE_URL and on their functions URL.
- The refusal message names the rule, not the URL value or any key.

## 4. Command lines

PowerShell (your shell), from D:\BDPay. 54321 is the local Supabase API port.

1. Unit tests (FakeStore; no database; also runs the FakeStore contract suite):
   `deno test --allow-read supabase/functions/tests`
   (BDPAY_TEST_DB is read with a permission check, so without --allow-env the PgStore tests are simply ignored.)

2. Contract tests on PgStore (local Supabase running, seed loaded):
   `$env:BDPAY_TEST_DB="1"; deno test --allow-read --allow-env --allow-net=127.0.0.1:54321,localhost:54321,[::1]:54321 --env-file=supabase/functions/.env.test.local supabase/functions/tests/store_contract`

3. Integration and race tests:
   `$env:BDPAY_TEST_DB="1"; deno test --allow-read --allow-env --allow-net=127.0.0.1:54321,localhost:54321,[::1]:54321 --env-file=supabase/functions/.env.test.local supabase/functions/tests/integration`

4. Smoke tests against served functions:
   terminal 1: `supabase functions serve --env-file supabase/functions/.env.local --no-verify-jwt` (D121)
   terminal 2:
   `deno run --allow-net=127.0.0.1:54321,localhost:54321,[::1]:54321 --allow-env --env-file=supabase/functions/.env.test.local supabase/scripts/smoke_device.ts --served`
   and the same for smoke_match.ts and smoke_shopify.ts once specs 09 / 10 create them.

After each: `$env:BDPAY_TEST_DB=$null`.

Commands 2-4 write test rows into your local database (a data change), so I ask before the first run of each.
`--allow-env` lets the tests read the key from the env file; no test, helper or error message ever prints an
environment value.

## 5. Acceptance criteria -> test or check

| Criterion | Test or check |
|---|---|
| deno test passes with FakeStore (specs 08-11 tests still pass) | command 1 |
| Contract suite passes on PgStore with the same results as FakeStore | command 2: the same runContract on both makers; same test names, same expected values; getMerchantContact blocked by D88 |
| Contract suite covers every Store method at least once | a coverage check in contract.ts: the list of Store method names (from a typed `satisfies Record<keyof Store, ...>` table) must each be called by at least one test, else the suite fails |
| Expected Postgres errors become Store results; unexpected ones become StoreError | pg_store_errors_test (unit, fake fetch) + contract tests on PgStore |
| Flow 1: register -> ingest bKash -> session -> submit -> verified -> order sync enqueued | flows_test (needs specs 09, 10) |
| Flow 2: submit first -> ingest -> verified | flows_test (needs spec 09) |
| Flow 3: mismatch -> approve -> verified (manual) -> sms-status verified | flows_test (needs spec 09) |
| Flow 4: mismatch -> reject -> session rejected | flows_test (needs spec 09) |
| Flow 5: pending claim past 24 h -> claims-expire -> expired | flows_test: claims-expire with an injected clock 25 h ahead (D122) |
| Flow 6: device silent 16 min -> alerts-check opens phoneSilent once, 1 FakeMailer mail | flows_test (needs spec 11 alerts-check); last_seen_at set 16 min back; counts only mails to the test's own address |
| Race: submit + onSmsStored together, 20 times -> exactly one match each time | races_test (D123 explains why this holds on Postgres) |
| Race: insertSms x5 parallel -> one row, four created:false | races_test + contract |
| Race: hitRateLimit x10 parallel, limit 5 -> exactly 5 allowed | races_test (one-hour window so a window edge cannot split the burst) |
| Another merchant's id returns nothing | contract: each method with a merchantId called with merchant B's id -> null / [] / 0 |
| Smoke scripts pass against functions serve without BDPAY_FAKE_STORE | command 4 (you run it); smoke_match / smoke_shopify need specs 09 / 10 |
| Tests refuse a non-local database | local_guard_test (unit) + every PgStore test goes through assertLocal |
| Tests never depend on other tests' rows | section 3 rules; fresh merchant per test; global-method tests assert own ids only |
| No supabase-js call or SQL text outside allowed files | boundaries_test (extended) + search |
| No .delete( on the five payment tables | search: no `.delete(` anywhere in pg_store.ts, mappers.ts, store_factory.ts, the tests or the smoke scripts (stricter than the spec: no delete at all) |
| No raw SQL strings | boundaries_test: no SELECT / INSERT / UPDATE / DELETE / TRUNCATE keywords (upper case, so supabase-js .select( does not count) and no .or( in pg_store.ts |
| No secret values in any file | search for JWT-shaped strings (eyJ...), "service_role" values, sk_ / shpat_ prefixes |
| Never log row contents; StoreError codes only | logging test: PgStore errors through serveFunction log only the code |
| deno check / lint / fmt --check | the three commands |
| Handlers unchanged except store_factory / user verifier | diff review: only index.ts lines change |

## 6. Unclear or wrong in the spec

Blocking: D114 (build order / missing specs 09-11), D116 (supabase-js version, asked first), D118 (who provides the
service role key to deno test), and spec 12 D88 (getMerchantContact).

- D116. **supabase-js version.** The spec says pin an exact version and ask first. Proposal:
  npm:@supabase/supabase-js@2.x.y with the newest 2.x release that is at least two weeks old on the day I add it;
  I tell you the number before writing deno.json. Downloading it is a package install -> your yes.
- D117. **500 error code.** Spec 12a: handlers return 500 {error: "internal"}. Spec 08 (built, tested) returns
  {error: "internalError"}. Options: A (recommended) keep "internalError" (no handler change, matches spec 08); B
  rename to "internal" (changes http.ts and spec 08 tests).
- D118. **The service role key for deno test.** `supabase functions serve` gives SUPABASE_URL / SERVICE_ROLE_KEY to
  served functions only; contract and integration tests run outside it and need them too. CLAUDE.md forbids me to
  read, print or write .env files and keys, and `supabase status` prints the key. Proposal: you create
  supabase/functions/.env.test.local yourself (`supabase status -o env` gives the values); I only pass its path with
  --env-file. Both .env files must be git-ignored (I check .gitignore covers them, without reading them).
- D119. **"Another merchant's id returns nothing" cannot apply to methods without a merchantId.** getDevice,
  updateDevice, getSession, getClaim, getSessionByTokenHash, findMismatchClaimBySms, getStoreByShopDomain,
  setStoreStatus, updateOrderSync, resolveAlert and markAlertSent take only an id. With the service role they read
  any merchant's row. Spec 08/09 handlers already check the merchant after these calls (device_auth, sms-status,
  claim-review); the contract suite tests the rule only for methods that have a merchantId. Noted.
- D120. **Store signatures differ between specs 09-11 and spec 12's functions** (submitClaim noAttemptsLeft,
  markWebhookSeen topic + shop, nullable audit merchantId, plan 12 D110-D113). "Handlers are not changed" cannot
  fully hold: the Store interface changes and the callers in specs 09-11 follow. Proposal: settle these while
  building specs 09-11 (D114 A), so 12a only adds PgStore.
- D121. **Gateway JWT check.** Device and public functions (sms-ingest, pay-session, shopify webhooks) are not
  called with a Supabase JWT, so `supabase functions serve` rejects them unless verify_jwt is off. Options: A
  --no-verify-jwt on the serve command (every handler checks its own auth already); B per-function
  verify_jwt = false in supabase/config.toml (needs `supabase init`). Recommended B for later production parity, A
  for now.
- D122. **Two clocks.** Handlers use the injected clock (deps.now) but Postgres stamps created_at, match_deadline
  (now() + 24 h in submit_claim) and rate-limit windows with its own now(). With a fake clock the two disagree
  (e.g. the 30-minute SMS rule compares an injected receivedAt with a database created_at). Proposal: integration
  tests use the real clock, and only expireDue / alerts-check get a time in the future (expire_due takes p_now;
  list_alert_inputs takes p_now). No migration change. The contract suite's time checks allow a few seconds of
  drift.
- D123. **The submit / SMS race really holds on Postgres** - noting why, since FakeStore cannot prove it: each side
  commits its own write (submit_claim, insert_sms) before it reads for the other (findUnmatchedSms,
  findPendingClaimByTrx). Whichever commits second must see the first, so at least one side tries
  record_verified, and its locks + unique match indexes let only one succeed. This needs every Store call to be its
  own transaction (true for supabase-js) - PgStore must never wrap the write and the read together.
- D124. **Smoke scripts against serve need a real user token.** smoke_device.ts registers with FakeStore's fixed
  token today. Served, it must create a test user with the admin API and sign in to get a token - but test users
  have no password (CLAUDE.md, section 3). Proposal: the served smoke uses auth.admin.generateLink (magic link,
  local only) to get a session token for its fresh user; no password anywhere.
- D125. **FakeMailer and FakeShopify inside served functions** cannot be inspected from the smoke script (separate
  process). Flow 6's "FakeMailer has 1 mail" is checked in the in-process integration test only; the served smoke
  only checks HTTP results.
- D126. **getParserRules "version 1 from seed"** only holds after `supabase db reset` loads seed.sql; production
  still has no rules (plan 12 D96).
- D127. **"No SQL strings"** - supabase-js filters such as .or("status.eq.open,...") are PostgREST filter text, not
  SQL. PgStore uses only typed builder calls (.eq / .in / .is / .gte); no .or() text and no .rpc to anything but the
  spec 12 functions. boundaries_test checks for SELECT / INSERT / UPDATE / DELETE keywords and .or( in pg_store.ts.

- D128. **A session can be created with another merchant's store id.** payment_sessions has merchant_id and store_id
  but nothing ties them together, and the service role bypasses RLS. A bug in spec 10 could create merchant A's
  session on merchant B's store. PgStore checks it (the conflict read filters by merchant), but the database does
  not. Proposal for a later migration (not 12a's scope - it would be new SQL): a composite FK (store_id,
  merchant_id) -> stores (id, merchant_id). Noted; no migration in 12a.
- D129. **The project is not a git repository**, so "git-ignore the .env files" has nothing to apply to yet. When you
  run git init, both .env files must go in .gitignore. Noted.

## 7. CLAUDE.md check

| Rule | How the plan keeps it |
|---|---|
| Never read / print / change .env files, keys, tokens | both .env files are yours; only their paths are passed; I never run `supabase status`; no key in any file; secret search in section 5; smoke scripts never print the magic-link or user token |
| Ask before any command that changes data | commands 2-4 write test rows into the local database: asked before the first run of each |
| Never delete or truncate | no .delete( in PgStore or tests; fresh merchants per test; cleanup only by your db reset |
| Work only on local Supabase; never link or push | assertLocal + --allow-net to 127.0.0.1:54321 only |
| Ask before installing packages / software | supabase-js pin asked first (D116) |
| Add no package the spec does not name | only supabase-js (named by the spec) |
| Edge Function logic talks only to the Store interface | handlers unchanged; supabase-js only in pg_store.ts and the user verifier (+ test helpers) |
| Money integer poisha | mappers check Number.isSafeInteger on every *_poisha |
| Times UTC ISO | mappers normalize to toISOString() |
| Never log SMS text, TrxID, tokens | StoreError carries a code only; no row contents in errors or logs |
| Do only what the spec says | D114 B/A scope; no new tables (would stop and ask) |
| UTF-8 without BOM | search |

## 8. Review changes (2026-10-30)

- Store coverage: removeShopifyTokens named (spec 10 only described it); getMerchantContact marked as blocking the
  spec's contract list (D88); a coverage check fails the suite if any Store method is never called.
- Merchant filters: written out for every insert-then-read (createPaymentSession, openAlert, createEventAlert,
  enqueueOrderSync), getSmsResults' embedded tables and getStoreForMerchant; D128 for sessions on another merchant's
  store.
- No delete / raw SQL / secrets: no .delete( anywhere (stricter than the spec); no SQL keywords or .or( text;
  `supabase status` never run by me; smoke scripts never print tokens; ask before commands that write test rows.
- Test isolation: rules for the six global methods that see leftover rows (own ids only, large limit, mark own rows
  done / sent, own-address mail count, no --parallel); [::1] added to the guard and --allow-net; smoke scripts
  guarded too.
- New unit test pg_store_errors_test.ts (fake fetch) so PgStore's error mapping and merchant filters are tested
  without a database.
