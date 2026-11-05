# 12a Connect the Edge Functions to the database

Purpose
Replace the in-memory FakeStore with the real Postgres database from spec 12 for every Edge Function,
and prove the two behave the same by running one shared test suite against both.

Scope
- supabase/functions/_shared/pg_store.ts: PgStore implements the full Store interface (specs 08-11)
  with supabase-js using the service role. Plain reads and writes use tables; every all-or-nothing
  method calls the spec 12 SQL function through rpc.
- supabase/functions/_shared/mappers.ts: snake_case rows <-> camelCase records, one function per record type.
- supabase/functions/_shared/store_factory.ts: picks the store for every index.ts:
  BDPAY_FAKE_STORE=1 -> FakeStore; otherwise SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY present -> PgStore;
  otherwise -> 503 storeNotReady (as before).
- supabase/functions/_shared/supabase_user_verifier.ts: the real UserVerifier (checks a Supabase user
  token with the auth server and returns the user id).
- supabase-js added to supabase/functions/deno.json with an exact pinned version (ask me first).
- A shared contract test suite in supabase/functions/tests/store_contract/: one function that takes a
  store maker and runs every test. It runs against FakeStore always and against PgStore when
  BDPAY_TEST_DB=1 (local Supabase running).
- Integration tests in supabase/functions/tests/integration/ that call the real handlers with PgStore.
- The three smoke scripts from specs 08-10 work against "supabase functions serve" with the real local
  database (FakeShopify and FakeMailer still used through BDPAY_FAKE_SHOPIFY=1 and BDPAY_FAKE_MAILER=1).
- Not in scope: new tables (if one is needed, stop and ask - it means a new migration), the real
  email provider and schedules (spec 15), Flutter and pay page changes (spec 13).

Contract
- Every Store method returns the same record shapes as FakeStore. Times are ISO strings in UTC.
  Money stays integer poisha (supabase-js returns BIGINT as a JSON number; values stay far below 2^53).
- Postgres errors are turned into Store results, never thrown to handlers for expected cases:
  unique violation in insertSms -> {created: false} with the existing row; in submitClaim ->
  {conflict: "alreadyUsed"}; record_verified "conflict" -> "conflict".
- Unexpected database errors are thrown as StoreError with a short code; handlers return 500
  {error: "internal"} and log only the code and request id.
- Shopify tokens are read and written only through save_shopify_tokens / get_shopify_tokens /
  delete_shopify_tokens.
- PgStore never deletes rows from sms_messages, payment_sessions, payment_claims, matches or audit_log,
  and never runs raw SQL strings; it uses the supabase-js query builder and rpc only.

Test data rules (because nothing may be deleted or truncated):
- Each contract and integration test creates its own new test user and merchant (supabase auth admin API,
  local only) with random names, and uses only that merchant's rows.
- Tests never depend on rows made by another test.
- Tests refuse to run if SUPABASE_URL is not a localhost or 127.0.0.1 address.

Local environment:
- I create the file supabase/functions/.env.local myself with: CRON_SECRET, PAY_TOKEN_SECRET,
  PAY_PAGE_URL, PAY_PAGE_ORIGIN, FUNCTIONS_URL, SHOPIFY_API_KEY, SHOPIFY_API_SECRET (dummy local values),
  SHOPIFY_SCOPES, SHOPIFY_API_VERSION, BDPAY_FAKE_SHOPIFY=1, BDPAY_FAKE_MAILER=1.
  Claude Code never reads or writes this file; it only passes its path to commands with --env-file.
  SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are given by "supabase functions serve" itself.

Functional rules
- Handlers are not changed except to get their store from store_factory and their UserVerifier from
  supabase_user_verifier (FakeUserVerifier stays for unit tests).
- The contract suite covers every Store method at least once, including these behaviours:
  createDevice/updateDevice/getDevice/findDeviceByInstall; insertSms new and duplicate; findSmsByDedupe;
  listActiveWallets; getParserRules (version 1 from seed); createPaymentSession idempotent on
  (storeId, externalOrderId); getSessionByTokenHash; submitClaim decrement, supersede, alreadyUsed,
  noAttemptsLeft; findUnmatchedSms; findPendingClaimByTrx; findLiveClaimByTrx; recordVerified ok and
  conflict (and nothing changed after conflict); recordMismatch; recordRejected; findMismatchClaimBySms;
  getSmsResults; expireDue; hitRateLimit; createInstallState / consumeInstallState; upsertShopifyStore;
  save/get Shopify tokens; markWebhookSeen; enqueueOrderSync / listDueOrderSyncs / updateOrderSync;
  listAlertInputs; openAlert (second open of the same kind fails or returns the existing one, same as
  FakeStore); markAlertSent; resolveAlert; createEventAlert idempotent per syncId; getMerchantContact;
  writeAudit.
- If FakeStore and PgStore disagree on any test, fix the one that differs from the spec; if the spec is
  unclear, stop and ask me.

Edge cases
- Race on PgStore: submitClaim and onSmsStored for the same TrxID started together, repeated 20 times
  with fresh data each time -> exactly one match every time.
- insertSms for the same dedupe hash from 5 parallel calls -> one row, four created:false.
- hitRateLimit from 10 parallel calls with limit 5 -> exactly 5 allowed.
- A store method called with another merchant's id returns nothing (service role bypasses RLS, so
  PgStore must always filter by merchantId where the Store method has one).

Non-functional rules
- No SQL strings or supabase-js calls outside pg_store.ts, supabase_user_verifier.ts and test helpers.
- No service role key or other secret in any file.
- Never log row contents; log StoreError codes only.
- deno check, deno lint and deno fmt --check pass.

Acceptance criteria
- deno test supabase/functions/tests passes with FakeStore (all spec 08-11 tests still pass).
- With local Supabase running and BDPAY_TEST_DB=1, the contract suite passes against PgStore with the
  same results as FakeStore.
- Integration tests with PgStore pass for these full flows:
  1. register device -> ingest a bKash SMS -> create session -> submit TrxID -> verified -> order sync enqueued;
  2. submit TrxID first -> ingest SMS -> verified;
  3. amount mismatch -> claim-review approve -> verified (manual) -> sms-status shows verified;
  4. mismatch -> reject -> session rejected;
  5. pending claim past 24 h (clock injected) -> claims-expire -> expired;
  6. device silent 16 minutes -> alerts-check opens phoneSilent once, FakeMailer has 1 mail.
- The three race edge cases pass on PgStore.
- Smoke scripts smoke_device.ts, smoke_match.ts and smoke_shopify.ts pass against
  "supabase functions serve --env-file supabase/functions/.env.local" with no BDPAY_FAKE_STORE.
- A search shows no supabase-js call or SQL text outside the allowed files, no .delete( on the five
  payment tables, and no secret values.
- deno check, deno lint and deno fmt --check pass.

Assumptions
- Spec 12 is done and "supabase test db" passes.
- Local Supabase is running ("supabase start").
- I have created supabase/functions/.env.local with dummy local values.
