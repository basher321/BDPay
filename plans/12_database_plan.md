# Plan 12 - Database

Spec: specs/12_database.md. Written 2026-10-30.
Read with: CLAUDE.md, specs 08-11, supabase/functions/_shared/store.ts (spec 08, built), and the Store additions
listed in specs 09, 10 and 11 (not built in TypeScript yet: of spec 09 only match_rules.ts exists, of spec 10 only
its pure helpers, of spec 11 only alert_rules / alert_messages / mailer).

Reviewed 2026-10-30 against the spec, the Store interface and CLAUDE.md: Store coverage (section 1), RLS and client
writes (section 2a), secrets in plain columns (section 2b), all-or-nothing and lock order (section 2c), tests and
CLAUDE.md (sections 4 and 7). Second review the same day: fixed counts, added D110-D113, tightened grants.

Default rule: until you answer a decision below, the build follows the spec text. Where the spec conflicts with
CLAUDE.md's safety rules (D84, D85) or a Store method has no backing (D88), I stop and ask - the spec itself says
"stop and tell me before adding anything".

## 0. Blockers

- D84. **The Supabase CLI and Docker are not installed on this machine** (`supabase` and `docker` are not on
  PATH). The spec assumes both. Without them nothing in this spec can run: `supabase migration new`, `db reset`,
  `test db`, `db lint`, `gen types`. Installing them is "installed software" (CLAUDE.md: explain and wait for
  your yes) and `supabase start` downloads several GB of Docker images. Options:
  A (recommended) you install Docker Desktop and the Supabase CLI yourself; I write the files now and you run
  the commands; B I write the files only and they stay untested until you install; C I install them after your yes.
- D85. **`supabase db reset` is forbidden by CLAUDE.md** ("Never run supabase db reset"), but the spec's
  acceptance criteria and functional rules need it ("runs from empty with supabase db reset"). Options:
  A (recommended) you run `supabase db reset` yourself (I give the exact command and never run it);
  B you give a one-time written exception in CLAUDE.md for the local database only.
- D86. **No supabase/config.toml.** `supabase migration new`, `test db` and `gen types --local` need a project
  made with `supabase init` (creates supabase/config.toml and supabase/.gitignore; it does not touch
  supabase/functions). Needs your yes (it creates project config). Without the CLI (D84 B) I name the migration
  files by hand in the CLI's format (YYYYMMDDHHMMSS_name.sql), one second apart, in the spec's order.

## 1. Store methods -> backing

"Table" = a plain select / insert / update through the service role in spec 12a. "Function" = a SQL function from
the spec. Methods marked FLAG have no backing, or the backing has a hole.

### Spec 08 (store.ts)

| Store method | Backed by | Note |
|---|---|---|
| findMerchantForUser(userId) | merchants (owner_id unique) | |
| countActiveDevices(merchantId) | devices (status) | |
| findDeviceByInstall(merchantId, installId) | devices UNIQUE (merchant_id, install_id) | |
| createDevice(fields) | devices | |
| updateDevice(deviceId, fields) | devices | |
| getDevice(deviceId) | devices | |
| getParserRules() | parser_rules WHERE is_active | production gets no rules (D96) |
| listActiveWallets(merchantId) | wallets WHERE is_active | |
| findSmsByDedupe(merchantId, hash) | sms_messages UNIQUE (merchant_id, dedupe_hash) | |
| insertSms(record) | function insert_sms | FLAG D87: status list has no "received" |
| writeAudit(entry) | audit_log | spec 09's claims-expire writes a system entry with no merchant; AuditEntry.merchantId must become nullable in 12a |

### Spec 09

| Store method | Backed by | Note |
|---|---|---|
| createPaymentSession(fields) | payment_sessions; idempotent via UNIQUE (store_id, external_order_id): insert, on unique violation read the existing row | |
| getSessionByTokenHash(hash) | payment_sessions.token_hash unique | |
| getMerchantName(merchantId) | merchants.business_name | |
| hasDeviceSeenSince(merchantId, time) | devices (status active, last_seen_at) | |
| findLiveClaimByTrx(merchantId, operator, trxId) | payment_claims partial unique (live statuses) | |
| submitClaim({sessionId, operator, trxId}) | function submit_claim | FLAG D90 (lock order), D91 (session state not re-checked); returns a new conflict "noAttemptsLeft" (TS type changes in 12a) |
| findUnmatchedSms(merchantId, operator, trxId) | sms_messages + partial index WHERE status = 'unmatched' | |
| findPendingClaimByTrx(merchantId, operator, trxId) | payment_claims | |
| recordVerified({...}) | function record_verified | FLAG D89 (cancelled session can be verified), D90 (lock order) |
| recordMismatch({...}) | function record_mismatch | guarded: no-op unless the claim is still pending |
| recordRejected({...}) | function record_rejected | |
| findMismatchClaimBySms(smsId) | payment_claims.candidate_sms_id (FK index) WHERE status = 'mismatch' | |
| getSmsResults(merchantId, smsIds) | sms_messages + payment_claims (candidate_sms_id) + matches + payment_sessions: several selects or one embedded PostgREST query | no SQL function needed |
| expireDue(now) | function expire_due | |
| hitRateLimit(key, limit, windowSeconds) | function hit_rate_limit | rows never cleaned up (D99) |
| getClaim(id), getSession(id) | payment_claims, payment_sessions | |

### Spec 10

| Store method | Backed by | Note |
|---|---|---|
| createInstallState(merchantId, shopDomain) | shopify_install_states (state made in TS, only its hash stored) | |
| consumeInstallState(state) | function consume_install_state | TS hashes the state first; the SQL only ever sees the hash |
| upsertShopifyStore({merchantId, shopDomain}) | stores UNIQUE (shop_domain) + partial UNIQUE (merchant_id) WHERE active: insert; on unique violation read the row, refuse if another merchant owns it, else set active + connected_at | FLAG D93 (second shop for one merchant) |
| saveShopifyTokens(storeId, tokens) | function save_shopify_tokens (Vault) | |
| getShopifyTokens(storeId) | function get_shopify_tokens (Vault) | |
| (remove tokens: app/uninstalled, shop/redact; plan 10 D40) | function delete_shopify_tokens | |
| (swapShopifyTokens, plan 10 D39 - concurrent refresh) | nothing | FLAG D94 (only if you said yes to D39) |
| getStoreByShopDomain(shopDomain) | stores.shop_domain unique | |
| getStoreForMerchant(merchantId) | stores (the active one, else the newest) | |
| setStoreStatus(storeId, status, lastError) | stores | FLAG D111 - uninstall = status + token delete in two calls |
| markWebhookSeen(webhookId) | function mark_webhook_seen | the SQL also takes topic and shop (TS signature grows in 12a) |
| findSessionByExternalOrder(storeId, externalOrderId) | payment_sessions UNIQUE (store_id, external_order_id) | |
| expireSessionForOrder(storeId, externalOrderId) | payment_sessions (WHERE status IN open, pending) | FLAG D89 - leaves the pending claim live |
| enqueueOrderSync(sessionId) | order_syncs UNIQUE (session_id): insert, on violation read | |
| listDueOrderSyncs(now, limit) | order_syncs (status pending, next_attempt_at <= now) + index, joined to stores to skip stores with last_error reconnectNeeded (spec 10: those syncs wait) | FLAG D110 - two runs at once can pick the same sync |
| updateOrderSync(id, fields) | order_syncs | |

### Spec 11

| Store method | Backed by | Note |
|---|---|---|
| listAlertInputs(now) | function list_alert_inputs | |
| listOpenAlerts(merchantId) | alerts WHERE status = 'open' | |
| openAlert(merchantId, kind, details) | alerts partial UNIQUE (merchant_id, kind) WHERE open: insert; on unique violation read the open row | PostgREST upsert cannot target a partial index, so it is insert + catch |
| markAlertSent(id, sentAt) (sendCount + 1) | alerts: conditional update `SET send_count = n + 1 ... WHERE id = $id AND send_count = n` (compare-and-set) | no function needed; also gives plan 11 D59 |
| resolveAlert(id, resolvedAt) | alerts | |
| createEventAlert(merchantId, kind, details) | alerts partial UNIQUE (merchant_id, details->>'syncId'): insert + catch | |
| listUnsentEventAlerts(limit) | alerts WHERE kind = 'syncFailed' AND last_sent_at IS NULL | |
| getMerchantContact(merchantId) -> {email, businessName} | merchants.business_name; **email is in auth.users** | **FLAG D88: no backing.** auth.users is not reachable through the service role's REST API and the spec lists no function for it |
| (device health fields, spec 11) | devices.last_sms_permission, last_monitoring, last_battery_ok | |

Result (checked again against every Store addition in specs 08-11: 11 + 17 + 14 + 8 = 50 methods): one method has no
backing at all (getMerchantContact, D88); D94 only if plan 10 D39 was a yes. Everything else is backed, with the
holes in D89-D93, D105 and D110-D112. The insert-then-read methods (createPaymentSession, enqueueOrderSync, openAlert,
createEventAlert, upsertShopifyStore) are race-safe because the unique index decides; the losing insert reads the
winner's row.

## 2. Migration files (in the spec's order)

Names are what `supabase migration new <name>` produces: supabase/migrations/<timestamp>_<name>.sql. Every file is
plain SQL, UTF-8 without BOM, creates only (no DROP, no TRUNCATE, no DELETE, no sample data).

| # | File (name part) | Creates |
|---|---|---|
| 1 | helpers | set_updated_at() trigger function (attached in each later file to: merchants, wallets, devices, parser_rules, sms_messages, stores, shopify_install_states, payment_sessions, payment_claims, order_syncs, alerts - not matches, audit_log, shopify_webhook_events, rate_limits, which never change or have no updated_at); upper_trx_id() trigger function; block_delete() and block_update() trigger functions (raise for every role); extension pgcrypto check (gen_random_uuid is built in) |
| 2 | merchants_and_wallets | merchants (owner_id unique FK auth.users, business_name 2-60); wallets (operator, wallet_number pattern CHECK incl. rocket 12 digits, account_type, label max 30, sim_slot, is_active); UNIQUE (operator, wallet_number); partial UNIQUE (merchant_id, operator, sim_slot) WHERE is_active AND sim_slot <> 'unknown'; FK indexes; updated_at triggers |
| 3 | devices_and_parser_rules | devices (name 1-30, install_id uuid, public_key_spki, status, versions, last_seen_at, 3 health booleans nullable), UNIQUE (merchant_id, install_id); parser_rules (version unique, rules jsonb, is_active, partial UNIQUE WHERE is_active); triggers |
| 4 | sms | sms_messages with all columns and CHECKs (status/reject_reason pairing, amount >= 0, operator list, sim_slot list), UNIQUE (merchant_id, dedupe_hash), partial index (merchant_id, operator, trx_id) WHERE unmatched, FK indexes (device_id, wallet_id); trx_id upper trigger; delete block; immutable-column update block |
| 5 | stores_and_shopify | stores (platform, shop_domain pattern + unique, status, last_error, connected_at, token_secret_id uuid null), partial UNIQUE (merchant_id) WHERE active; shopify_install_states (state_hash unique, expires_at, used_at); shopify_webhook_events (webhook_id unique, topic, shop_domain) |
| 6 | sessions_claims_matches | payment_sessions (amount > 0, status list, attempts_left 0-5 default 5, UNIQUE (store_id, external_order_id), token_hash unique); payment_claims (status list incl. superseded, reason, candidate_sms_id FK, match_deadline), partial UNIQUE (merchant_id, operator, trx_id) WHERE pending/verified/mismatch; then ALTER payment_sessions ADD active_claim_id FK DEFERRABLE INITIALLY DEFERRED (circular); matches (claim_id unique, sms_id unique, method, user_id null, note max 200); all FK indexes; trx upper trigger; delete blocks; matches update block |
| 7 | order_syncs | order_syncs (session_id unique, status, attempts default 0, next_attempt_at, last_error), index (status, next_attempt_at) |
| 8 | alerts | alerts (kind list, status, opened_at, last_sent_at null, send_count default 0, resolved_at null, details jsonb not null default '{}'); partial UNIQUE (merchant_id, kind) WHERE open AND kind <> 'syncFailed'; partial UNIQUE (merchant_id, (details->>'syncId')) WHERE kind = 'syncFailed' |
| 9 | audit | audit_log (merchant_id nullable FK, actor_type, actor_id null, action, entity, entity_id null, data jsonb); delete and update blocks; the payment_sessions status-change trigger (written here so audit_log exists first) |
| 10 | rate_limits | rate_limits (key, window_start, count; PRIMARY KEY (key, window_start)) |
| 11 | security | is_owner(merchant_id); RLS per section 2a (ENABLE + FORCE on the 11 merchant_id tables and on merchants; ENABLE on the 3 others); REVOKE ALL on every table and function from public, anon and authenticated (Supabase grants them by default - D97); then exactly the grants and policies in section 2a; ALTER DEFAULT PRIVILEGES so later tables and functions are not granted to anon/authenticated |
| 12 | transactional_functions | insert_sms, submit_claim, record_verified, record_mismatch, record_rejected, expire_due, hit_rate_limit, consume_install_state, mark_webhook_seen, list_alert_inputs (+ get_merchant_contact only with D88 = A); all SECURITY DEFINER, SET search_path = public, pg_temp; EXECUTE revoked from public/anon/authenticated, granted to service_role; write pattern and lock order per section 2c |
| 13 | vault_functions | save_shopify_tokens, get_shopify_tokens, delete_shopify_tokens using vault.create_secret / vault.update_secret / vault.decrypted_secrets / delete from vault.secrets WHERE id = ...; each locks the stores row FOR UPDATE first (two saves at once cannot create two secrets); secret name "shopify_store_<store id>", description empty (never the token); same security settings and grants |

Also: supabase/seed.sql (2 auth users without passwords - D98, merchants A and B, wallets, one device and one store
each, parser_rules version 1 with the JSON from _shared/parser_rules.json embedded), and
supabase/functions/_shared/db_types.ts generated by `supabase gen types typescript --local` (D100).

Lock order everywhere (D90): payment_sessions -> payment_claims -> sms_messages. Claim before SMS always holds
(the spec's rule); the session is taken first, in front of it.

## 2a. RLS and client writes - per table

| Table | merchant_id | RLS | anon | authenticated (owner) |
|---|---|---|---|---|
| merchants | (the parent; owner_id) | ENABLE + FORCE | none | SELECT own; INSERT (owner_id, business_name) only - column grant - WITH CHECK owner_id = auth.uid(), one row (owner_id unique); UPDATE (business_name) only, USING and WITH CHECK own row |
| wallets | yes | ENABLE + FORCE | none | SELECT own; INSERT (merchant_id, operator, wallet_number, account_type, label, sim_slot, is_active) only - column grant, so id / created_at / updated_at cannot be set - WITH CHECK is_owner(merchant_id); UPDATE USING and WITH CHECK is_owner(merchant_id). Spec: any column. Proposal D113: UPDATE only label, sim_slot, is_active, account_type, wallet_number (not merchant_id, operator) |
| devices | yes | ENABLE + FORCE | none | SELECT own (public_key_spki is a public key) |
| sms_messages | yes | ENABLE + FORCE | none | SELECT own |
| stores | yes | ENABLE + FORCE | none | SELECT own, every column except token_secret_id (column grant) |
| shopify_install_states | yes | ENABLE + FORCE | none | none (spec: no client access) |
| payment_sessions | yes | ENABLE + FORCE | none | SELECT own |
| payment_claims | yes | ENABLE + FORCE | none | SELECT own |
| matches | yes | ENABLE + FORCE | none | SELECT own |
| order_syncs | yes | ENABLE + FORCE | none | SELECT own |
| alerts | yes | ENABLE + FORCE | none | SELECT own |
| audit_log | yes (nullable) | ENABLE + FORCE | none | SELECT own (rows with merchant_id null: nobody) |
| parser_rules | no (global) | ENABLE | none | SELECT WHERE is_active |
| shopify_webhook_events | no | ENABLE | none | none |
| rate_limits | no | ENABLE | none | none |

Every policy is written per command (SELECT / INSERT / UPDATE), never FOR ALL, so no DELETE policy exists.
No client DELETE on any table; no client INSERT or UPDATE anywhere else. service_role keeps full access (it
bypasses RLS) and is the only role that may call the functions. is_owner is executable by authenticated (the
policies need it); it only answers "is this my merchant", so it reveals nothing.

## 2b. Secrets in plain columns - checked per column

| Column | Holds | Fix |
|---|---|---|
| stores.token_secret_id | a Vault secret id (uuid), never the token | 08_vault_test |
| payment_sessions.token_hash, shopify_install_states.state_hash | SHA-256 hashes only | CHECK ~ '^[0-9a-f]{64}$' (proposal D106) |
| devices.public_key_spki | the public key (allowed); no private-key column exists | 00_schema_test: no column named like private / secret / ip |
| rate_limits.key | spec 09/10 keys: token hash, IP hash, shop domain - a raw IP would fit in free text | CHECK key ~ '^[a-z-]+:([0-9a-f]{64}|[a-z0-9][a-z0-9-]*\.myshopify\.com)$' (proposal D106), so a raw IP or raw token cannot be stored |
| payment_sessions.return_url | Shopify's order status page URL, which carries Shopify's own key for that page | D107 |
| audit_log.data, alerts.details | free jsonb | D108 |
| stores.last_error, order_syncs.last_error | free text; spec 10 writes codes (reconnectNeeded, alreadyPaid, cancelled) but an error message could carry response text | CHECK short code-like text, length <= 100 (proposal D106) |
| Vault secret name / description | name "shopify_store_<id>", empty description | 08_vault_test checks the description is empty |
| Error and notice texts from our functions | RAISE messages are fixed text; no RAISE / NOTICE ever includes a parameter value (a token in p_tokens, a hash, a TrxID) | review + search of the migrations for RAISE ... % |
| Column names | 00_schema_test matches whole snake_case words: (^|_)(token|secret|private|password|ip)(_|$), allowing only token_hash and token_secret_id | 00_schema_test |

## 2c. All-or-nothing and lock order - per function

Every function runs in one transaction. A "conflict" result must leave nothing changed, so each function checks
every condition under its locks BEFORE its first write, and the writes that can still hit a unique index run
inside one BEGIN ... EXCEPTION WHEN unique_violation block (a subtransaction: all its writes roll back together).

| Function | Locks (in order) | Writes | Half-done risk and fix |
|---|---|---|---|
| insert_sms | none (unique index) | 1 insert ON CONFLICT DO NOTHING, then select | none: one statement; a racing insert waits and the select sees the winner |
| submit_claim | session FOR UPDATE -> its active claim FOR UPDATE | supersede old claim, insert new claim, update session | the supersede happens before the insert that may hit the live-TrxID index -> all three writes in one exception block; on violation everything rolls back and it returns alreadyUsed |
| record_verified | read the claim's session_id (no lock; it never changes), then session -> claim -> sms, all FOR UPDATE | insert match, update claim, session, sms | all conditions checked under the locks before any write (claim pending or mismatch, sms unmatched, same merchant; D89 session state; D112 candidate / operator / TrxID); the 4 writes in one exception block (match unique index) -> conflict leaves nothing |
| record_mismatch | session -> claim FOR UPDATE -> sms FOR SHARE | claim, session | no-op unless the claim is still pending and the sms unmatched |
| record_rejected | session -> claim FOR UPDATE | claim, session | no-op unless the claim is mismatch |
| expire_due | sessions FOR UPDATE SKIP LOCKED -> their active claims FOR UPDATE SKIP LOCKED | sessions, claims | session first (not claim first); rows busy in another call are skipped and expired on the next run instead of blocking or deadlocking |
| hit_rate_limit | none | 1 upsert RETURNING count | one statement |
| consume_install_state | none | 1 UPDATE ... WHERE used_at IS NULL AND expires_at > now() RETURNING | one statement; two calls cannot both succeed |
| mark_webhook_seen | none | 1 INSERT ON CONFLICT DO NOTHING RETURNING | one statement |
| list_alert_inputs, get_shopify_tokens | none | read only | - |
| save / delete_shopify_tokens | stores row FOR UPDATE | vault secret + stores.token_secret_id | lock first, so two calls cannot create two secrets or leave an orphan; both writes in the same transaction |

Not SQL functions, but multi-call Store sequences that could stop half-way (for spec 12a): uninstall (setStoreStatus
then delete_shopify_tokens, D111) and listDueOrderSyncs + updateOrderSync (D110). Every other Store write is a
single statement.

## 3. pgTAP test files (supabase/tests/)

Each file: BEGIN; plan(n); its own fixtures (auth users, merchants A and B, rows) made as postgres; tests;
finish(); ROLLBACK. They do not depend on seed.sql. User context: SET LOCAL ROLE authenticated +
set_config('request.jwt.claims', '{"sub": "...", "role": "authenticated"}', true).

| File | Covers |
|---|---|
| 00_schema_test.sql | every table and column exists with the right type and nullability; money columns are bigint; every FK has an index (catalog query: each pg_constraint FK has a pg_index whose leading columns match); RLS enabled and forced on the 12 tables in section 2a (by name, plus a catalog query that every table with a merchant_id column is forced), enabled on the other 3; the function owner bypasses RLS (D95); no column whose name looks like a token, private key or IP (token, secret, private, ip) except token_hash / token_secret_id; every function has a fixed search_path (pg_proc.proconfig) |
| 01_constraints_test.sql | every CHECK and UNIQUE in the Contract: wallet number patterns (11 digits; rocket 12; rocket-only 12; bad prefix), cross-merchant wallet number, partial unique on active sim_slot (inactive ok, unknown ok), business_name, device name, wallet label (max 30) and match note (max 200) lengths, parser_rules one active, sms status/reject_reason pairing, amount >= 0, shop_domain pattern, one active store per merchant, session amount > 0 and attempts 0-5, claim live-TrxID partial unique (superseded/expired/rejected do not block), matches claim_id and sms_id unique, order_syncs session unique, alert partial uniques, every fixed-value list (one bad value per CHECK) |
| 02_triggers_test.sql | updated_at changes on update (each table that has it); trx_id upper(trim) on sms and claims; DELETE raises on the 5 payment tables for postgres, service_role and authenticated; UPDATE of sender/body/received_at/dedupe_hash raises, status update allowed; matches and audit_log updates raise; session status change writes exactly one audit row {from, to}, a non-status update writes none |
| 03_rls_test.sql | one block per row of section 2a (incl. clients cannot set id / created_at on merchants and wallets) with the expected rights for anon, user A and user B; for every table with merchant_id: user A sees only A's rows, B only B's, anon sees nothing (zero rows or permission denied); clients cannot insert into devices, stores, sms_messages, payment_sessions, payment_claims, matches, order_syncs, alerts, audit_log (incl. A inserting into A's sms); merchants: insert own row once, second insert fails, cannot insert with another owner_id, can update business_name only; wallets: A can insert/update own, cannot insert for B, cannot update merchant_id or operator; no client delete anywhere; stores.token_secret_id not selectable; parser_rules: authenticated sees active rules only; shopify_install_states, shopify_webhook_events, rate_limits: no access for anon or authenticated |
| 04_function_grants_test.sql | for each of the 13 transactional and vault functions: anon and authenticated get permission denied; service_role can execute; is_owner is the only helper authenticated may execute |
| 05_insert_sms_test.sql | insert_sms creates, second call returns the same row with created false; per merchant |
| 06_claims_test.sql | submit_claim (incl. the supersede rolled back when the insert hits alreadyUsed): attempts 5 -> 4, active claim superseded, session pending + active_claim_id, alreadyUsed (another session's live TrxID) leaves everything unchanged, noAttemptsLeft at 0, superseded/expired TrxID reusable; record_verified: ok sets match + claim verified + session verified + verified_at + sms matched; conflict cases (same claim with a second SMS, second claim with the same SMS, claim not pending/mismatch, sms not unmatched, merchant differs) and each conflict leaves all rows identical (snapshot of the 4 tables as jsonb before and after); record_mismatch; record_mismatch on a non-pending claim changes nothing; record_rejected only from mismatch (from pending: no change); record_verified on an expired (cancelled) session -> conflict (D89); with D112: approving a mismatch claim with an SMS other than its candidate -> conflict; expire_due: counts for open-past-deadline sessions and pending-past-24h claims, mismatch never expired, returns {sessions, claims} |
| 07_misc_functions_test.sql | hit_rate_limit allowed up to the limit, denied at limit + 1, allowed again in a new window (window passed in via the key's window_start - D99); consume_install_state single use, expired -> null, unknown -> null; mark_webhook_seen true then false; list_alert_inputs fields for a fixture merchant (counts, newest seen, anyDeviceProblem, storeReconnectNeeded) and merchants with no device and no store left out |
| 08_vault_test.sql | save -> stores.token_secret_id set and the token text found in no public table (search every text/jsonb column of stores); get returns the JSON; save again updates the same secret id; delete removes the secret and clears the id; get after delete -> null; the vault secret's description is empty |
| 09_secret_columns_test.sql | only with D106: a raw IPv4 / IPv6 or raw token refused in rate_limits.key; non-hex token_hash refused; long or free-text last_error refused |

Plus (proposal, D101): supabase/functions/tests/seed_rules_test.ts - the JSON embedded in seed.sql equals
_shared/parser_rules.json, so the seed cannot drift (like spec 08's copy test).

## 4. Acceptance criteria -> test or check

| Criterion | Test or check |
|---|---|
| supabase db reset runs clean | you run it (D85); I report the output you paste |
| supabase test db passes | you run it (D84/D85); the 10 files above (09 only with D106) |
| RLS: A sees only A's rows, B only B's, anon nothing (every merchant_id table) | 03_rls_test |
| Clients cannot insert into the 9 tables; can insert one merchant per user and wallets | 03_rls_test |
| authenticated cannot select stores.token_secret_id | 03_rls_test |
| authenticated cannot execute any transactional function | 04_function_grants_test |
| DELETE blocked on the 5 payment tables, also for service_role | 02_triggers_test |
| sms immutable columns; matches and audit_log not updatable | 02_triggers_test |
| Every unique and CHECK rule incl. wallet patterns and partial uniques | 01_constraints_test |
| submit_claim: decrement, supersede, alreadyUsed, noAttemptsLeft | 06_claims_test |
| record_verified ok; conflict cases; conflict changes nothing | 06_claims_test (before/after snapshots) |
| record_rejected only from mismatch; expire_due counts; mismatch not expired | 06_claims_test |
| hit_rate_limit up to limit, denied at limit + 1, new window ok | 07_misc_functions_test |
| insert_sms idempotent; consume_install_state single use + expiry; mark_webhook_seen true then false | 05_insert_sms_test, 07_misc_functions_test |
| Vault save/get/update/delete; stores row never holds the token text | 08_vault_test |
| set_updated_at; trx_id upper-cased; session status change writes audit | 02_triggers_test |
| supabase db lint no errors | you run it (or I do after D84); "not available" reported if the CLI lacks it |
| db_types.ts generated with gen types --local | you run it (it needs the running local stack); then deno check / fmt / lint (D100) |
| Every FK has an index | 00_schema_test (catalog query) |
| Functions use a fixed search_path | 00_schema_test (pg_proc.proconfig) |
| No table stores a Shopify token, private key, pay token or raw IP | section 2b; 00_schema_test (column names) + 08_vault_test (token text search) + 09_secret_columns_test (D106) |
| RLS enabled AND forced on every table with merchant_id | 00_schema_test (by name and by catalog query) |
| A conflict leaves every row exactly as before (edge case) | 06_claims_test snapshots, for submit_claim and record_verified |
| No sample data in migrations | search: no INSERT in supabase/migrations |
| Migrations and seed UTF-8 without BOM | search |
| Edge cases (8) | 01 (wallets, sim1), 06 (superseded/expired reuse, record_verified twice, same SMS twice, conflict unchanged), 02 (delete as service_role), 03 (A reads B, A inserts sms) |

## 5. Unclear or wrong in the spec

Blocking: D84 (no CLI / Docker), D85 (db reset forbidden), D86 (supabase init), D88 (getMerchantContact).

- D87. **sms status list vs CLAUDE.md.** Spec 12: unmatched | matched | rejected. CLAUDE.md and spec 08's types.ts
  (your D69 answer): received | unmatched | matched | rejected. Proposal: the CHECK uses CLAUDE.md's four values
  (spec 08 never writes "received"). Same question for claim status: spec 12 adds "superseded", which CLAUDE.md's
  list lacks (spec 09 has it) - proposal: keep superseded and add it to CLAUDE.md's list. And CLAUDE.md lists
  claim mismatch_reason amount | duplicate_trxid; spec 12's payment_claims.reason has no CHECK - proposal: CHECK
  reason IN ('amount', 'duplicate_trxid').
- D88. **getMerchantContact has no backing.** The email is in auth.users. Options: A (recommended) a function
  get_merchant_contact(p_merchant_id) -> {email, businessName} (security definer, service_role only) in the
  transactional functions file; B an email column on merchants (copied at sign-up; can go stale). Needs your yes
  either way (the spec says stop before adding).
- D89. **A cancelled order can still be marked paid.** expireSessionForOrder (Shopify orders/cancelled) expires
  the session but leaves its pending claim live; a later SMS finds the pending claim and record_verified marks
  claim, session (back to verified) and SMS - the cancelled order gets paid. Proposal: record_verified also
  requires the session to be pending or mismatch (else conflict). Needs your yes (changes the function's rule).
- D90. **Deadlock between submit_claim and record_verified.** submit_claim locks session then claim;
  record_verified locks claim then session (and sms). Two such calls at once can deadlock; Postgres aborts one with
  an error, not a "conflict". Proposal: one lock order everywhere - session, then claim, then sms (record_verified
  reads the claim's session id, locks the session first). This changes the spec's "claim, then the sms" wording
  only by adding the session in front. Needs your yes.
- D91. **submit_claim does not re-check the session under the lock.** Spec 09 checks expired / verified in
  TypeScript before calling it; between that check and the lock, expire_due or a verify can change the session.
  Proposal: under the lock, refuse unless status is open or pending and (open) now <= submit_deadline, returning
  {conflict: "expired"} or {conflict: "closed"}. New conflict values -> needs your yes; without it: as written.
- D92. **Nullability not stated.** alerts.last_sent_at / resolved_at must be nullable (spec 11 has null);
  devices.last_sms_permission / last_monitoring / last_battery_ok nullable; stores.connected_at not null;
  wallets.label nullable; payment_claims.reason nullable. Proposal: as listed, everything else NOT NULL.
- D93. **Second Shopify shop for one merchant.** Partial UNIQUE (merchant_id) WHERE active blocks it; spec 10
  doesn't say what the merchant sees. Proposal: upsertShopifyStore returns a conflict that spec 12a maps to an error
  (spec 10's shopTaken?) - noted for spec 12a; no schema change.
- D94. **Concurrent token refresh (plan 10 D39).** Only matters if you said yes to D39: save_shopify_tokens would
  need a compare-and-swap form. Noted.
- D95. **Row locks and FORCE RLS.** With RLS forced, security definer functions owned by postgres see rows only if
  postgres bypasses RLS. In Supabase postgres has BYPASSRLS, but if it does not in your local version, every
  function would see nothing. The first migration run checks this (00_schema_test asserts rolbypassrls for the
  function owner); if it fails I stop and ask.
- D96. **Production has no parser rules.** "No sample data in migrations" puts rules version 1 only in seed.sql,
  which never runs in production. Production sms-ingest would then find no rules -> every SMS senderNotTrusted.
  Proposal: rules are configuration, not sample data - load version 1 in a migration (or in spec 15's deploy
  steps). Needs your decision; without it, seed only, as written.
- D97. **Supabase grants every new public table and function to anon and authenticated by default.** The
  security migration revokes those grants explicitly and changes the default privileges, otherwise "anon has no
  access" and "EXECUTE revoked" would silently fail. Also: with column grants on stores, `select *` by
  authenticated fails; the app must name columns (note for spec 13).
- D98. **Seed users and passwords.** CLAUDE.md: never write passwords. The two seed users get no password (they
  cannot log in; pgTAP sets the user id directly). A local login for spec 13 is a later decision.
- D99. **rate_limits grows forever.** One row per key per window, never removed (CLAUDE.md forbids deletes without
  your yes, and pg_cron is spec 15). Noted for spec 15. hit_rate_limit uses now(); to test "a new window" without
  waiting, the test inserts the old window's row with an earlier window_start (no clock parameter needed).
- D100. **db_types.ts and deno fmt / lint.** Generated code may not pass spec 08's "deno fmt --check / lint pass
  on supabase/functions". Proposal: run deno fmt on it after generating; if lint still complains, add a
  `// deno-lint-ignore-file` header line (the only hand edit). Generating needs the running stack (D84).
- D101. **Seed rules can drift** from _shared/parser_rules.json (SQL cannot read the file). Proposal: the small
  Deno test in section 3. It is outside the spec's "pgTAP tests" scope, so it needs your yes.
- D102. **Races are not testable in pgTAP** (one session per test). The guarantees come from the unique indexes
  and row locks; 06_claims_test proves the unique rules, not the timing. Noted.
- D103. **"Delete blocked for every role"** also stops cleaning up test rows; pgTAP files use ROLLBACK, so nothing
  needs deleting. `supabase db reset` (D85) drops the whole local database anyway.
- D105. **alreadyUsed costs an attempt in one path but not the other.** Spec 09 step f (TS sees another session's
  live claim) uses an attempt; submit_claim's own unique-violation alreadyUsed (the race) changes nothing,
  attempts included. Noted; the SQL follows spec 12 (nothing changed).
- D106. **Plain-column guards (new CHECKs, not in the spec):** token_hash / state_hash 64 hex; rate_limits.key only
  "<kind>:<64 hex>" or "<kind>:<shop>.myshopify.com" (no raw IP or raw token can be stored); stores.last_error and
  order_syncs.last_error short codes only. Needs your yes; without it, plain text as the spec says.
- D107. **return_url carries a Shopify key.** Shopify's order status page URL includes that page's own access key.
  It is not an Admin API token and the customer already has it, but it is a link with a key in a plain column,
  readable by the merchant. Options: A keep it (spec 09 needs it to send the customer back); B store only the shop
  and order id and rebuild the link. Recommended A; noted.
- D108. **audit_log.data and alerts.details are free jsonb.** The database cannot stop a caller writing a token or
  IP there. Kept free (spec); spec 08's logging_test already checks audit data, and spec 12a must do the same for
  every writeAudit / details caller.
- D109. **Wallet number squatting.** UNIQUE (operator, wallet_number) across merchants plus client INSERT lets a
  merchant register another business's number first and block it. It cannot verify that number's money (the SMS
  come from the real owner's phone), but the real owner gets a unique violation. Noted for support (Studio).
- D110. **Two shopify-sync runs at once can pick the same OrderSync** (listDueOrderSyncs is a plain select), so
  one order can be marked paid twice and attempts counted twice. Shopify answers the second mark-paid with an
  "already paid" user error (spec 10 -> done), so no money is wrong, but attempts can skip ahead. Options: A note
  only (the cron runs every 5 minutes, overlap is rare); B a claim_due_order_syncs(p_now, p_limit) function with
  FOR UPDATE SKIP LOCKED that pushes next_attempt_at forward as it picks (new function -> needs your yes).
  Recommended A for v1.
- D111. **Uninstall can stop half-way, and then never finish.** spec 10's app/uninstalled does markWebhookSeen,
  then setStoreStatus, then remove tokens - three calls. If the token delete fails, Shopify retries the webhook but
  markWebhookSeen now says "seen" and the retry is skipped: the token stays in Vault for good. Options: A
  (recommended) delete_shopify_tokens also sets the store's status in the same transaction (one call), and spec
  12a marks the webhook seen only after handling succeeds; B note only. Needs your yes (changes spec 10's order and
  this function's job).
- D112. **record_verified does not check which SMS it is given.** For a manual approve the claim is mismatch and
  the SMS should be its candidate_sms_id; the spec only asks for "same merchant", so a wrong p_sms_id would pay the
  claim with an unrelated SMS. Proposal: also require sms.operator = claim.operator and sms.trx_id = claim.trx_id,
  and for a mismatch claim p_sms_id = candidate_sms_id; else conflict. Defence in depth (TypeScript already
  checks); needs your yes.
- D113. **Wallet updates.** The spec lets the owner update any wallet column. Changing merchant_id is already
  blocked by WITH CHECK (only to a merchant you own - you own one), but changing operator turns a bKash wallet into
  a Nagad one under the same id and old SMS rows. Proposal: column-level UPDATE grant without merchant_id and
  operator (deactivate and add a new wallet instead). Stricter than the spec -> needs your yes; without it, every
  column except id / created_at.
- D104. **Store methods built in TypeScript differ from specs 09-11 in small ways** (submitClaim adds
  noAttemptsLeft, markWebhookSeen takes topic and shop, plan 09 called findMerchantForUser getMerchantIdForUser).
  These are spec 12a's to reconcile; the SQL follows spec 12.

## 6. Commands (none run by me without your yes)

- You (D84 A): install Docker Desktop and the Supabase CLI, then `supabase init` (D86) and `supabase start`.
  `supabase start` prints local keys; per CLAUDE.md I never read or print them.
- Me, after your yes: `supabase migration new <name>` x 13 (creates empty files only).
- You (D85 A): `supabase db reset`, then `supabase test db`, `supabase db lint`,
  `supabase gen types typescript --local > supabase/functions/_shared/db_types.ts`.
- Me: deno check / lint / fmt --check on supabase/functions after db_types.ts lands; BOM and "no INSERT in
  migrations" searches.

## 7. CLAUDE.md check

| Rule | How the plan keeps it |
|---|---|
| Never run supabase db reset / DROP / TRUNCATE / DELETE without WHERE | D85; migrations only create; vault delete has WHERE id = ...; tests roll back |
| A database change is only a new numbered migration; never edit an old one | 13 new files; none exist yet |
| Work only on the local Supabase; never db push or link | only local commands; no link |
| Ask before installing software or changing data | D84, D86; section 6 |
| Never read or print .env, keys, passwords, tokens | no .env; seed users without passwords (D98); `supabase start` keys stay on your screen |
| A merchant sees only its own rows | RLS forced on every merchant table (section 2a); 03_rls_test |
| Money BIGINT *_poisha | amount_poisha bigint; 00_schema_test |
| Times timestamptz UTC | all time columns timestamptz |
| Fixed values as CHECK lists | D87; the new lists (session, claim incl. superseded, store, order sync, alert kind and status, actor type) go into CLAUDE.md's list once you approve D87 |
| merchant_id NOT NULL on every merchant-owned table | all NOT NULL except audit_log (the spec's one exception, for system entries such as claims-expire) - a small conflict with CLAUDE.md's wording, noted |
| Wallet and phone numbers are digit strings | text columns; wallet_number CHECK; payer_number text |
| DELETE never without WHERE | the delete-block tests use DELETE ... WHERE id = <fixture id> inside a rolled-back transaction |
| Claims, SMS, matches never deleted | delete-block triggers + no delete grants |
| Server decides paid | only service_role can call record_verified |
| UTF-8 without BOM | search |
| No feature outside Scope | no pg_cron, no TS Store (12a); every addition (D88, D96, D101, D106, D110 B, D111, D112, D113) only with your yes |
