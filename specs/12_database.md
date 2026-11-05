# 12 Database

Purpose
Build the real Postgres database in Supabase from the Store methods of specs 08 to 11, with
security rules so each merchant sees only their own data, and with all-or-nothing SQL functions
so one payment can never be counted twice. Connecting the Edge Functions to it is spec 12a.

Scope
- SQL migrations in supabase/migrations/ (created with "supabase migration new", one file per area,
  in this order): helpers, merchants and wallets, devices and parser rules, sms, stores and Shopify,
  sessions claims matches, order syncs, alerts, audit, rate limits, security (RLS and grants),
  transactional functions, vault functions.
- supabase/seed.sql for local development only: 2 test users and merchants (A and B), wallets,
  one device each, one store each, and the parser rules from
  supabase/functions/_shared/parser_rules.json (version 1).
- pgTAP tests in supabase/tests/ (run with "supabase test db").
- Generated TypeScript types: supabase/functions/_shared/db_types.ts.
- Not in scope: the Postgres Store in TypeScript (spec 12a), schedules with pg_cron (spec 15),
  production data, any Flutter or pay page change.

Contract
General (from CLAUDE.md): uuid id default gen_random_uuid(); created_at timestamptz not null default now();
updated_at on tables that change (trigger); money BIGINT *_poisha; fixed values TEXT + CHECK with the exact
wire names below; every foreign key declared and indexed; ON DELETE RESTRICT; RLS enabled AND forced on
every table with merchant_id.

Tables:
1. merchants: owner_id uuid not null unique -> auth.users, business_name text (2-60 chars).
   (No merchant_id; this is the parent table.)
2. wallets: merchant_id, operator (bkash|nagad|rocket|upay), wallet_number, account_type (merchant|agent),
   label (max 30), sim_slot (sim1|sim2|unknown), is_active bool default true.
   CHECK wallet_number: '^01[3-9][0-9]{8}$', or '^01[3-9][0-9]{9}$' only when operator = rocket.
   UNIQUE (operator, wallet_number) across all merchants (one wallet belongs to one merchant).
   Partial UNIQUE (merchant_id, operator, sim_slot) WHERE is_active AND sim_slot <> 'unknown'.
3. devices: merchant_id, name (1-30), install_id uuid, public_key_spki text, status (active|revoked),
   app_version, android_version, last_seen_at, last_sms_permission, last_monitoring, last_battery_ok.
   UNIQUE (merchant_id, install_id).
4. parser_rules: version int unique, rules jsonb not null, is_active bool. Partial UNIQUE on is_active WHERE is_active.
   (No merchant_id; global.)
5. sms_messages: merchant_id, device_id, wallet_id (nullable), sender, body (nullable), received_at,
   server_received_at default now(), sim_slot, dedupe_hash, operator (nullable, operator list), trx_id (nullable),
   amount_poisha bigint (>= 0, nullable), payer_number (nullable), status (unmatched|matched|rejected),
   reject_reason (nullable; senderNotTrusted|blocked|notIncoming|parseFailed|tooOld), parser_version int.
   UNIQUE (merchant_id, dedupe_hash). CHECK: status = rejected exactly when reject_reason is not null.
   Index (merchant_id, operator, trx_id) WHERE status = 'unmatched'.
6. stores: merchant_id, platform (shopify), shop_domain (CHECK '^[a-z0-9][a-z0-9-]*\.myshopify\.com$') UNIQUE,
   status (active|uninstalled), last_error (nullable), connected_at, token_secret_id uuid (nullable; a Vault secret id).
   Partial UNIQUE (merchant_id) WHERE status = 'active'.
7. shopify_install_states: merchant_id, state_hash text unique, shop_domain, expires_at, used_at (nullable).
8. shopify_webhook_events: webhook_id text unique, topic, shop_domain. (No merchant_id; the merchant may be unknown.)
9. payment_sessions: merchant_id, store_id, token_hash text unique, order_ref, external_order_id (nullable),
   amount_poisha bigint (> 0), status (open|pending|verified|mismatch|expired|rejected), submit_deadline,
   attempts_left int (0-5) default 5, return_url, active_claim_id (nullable -> payment_claims, deferrable),
   verified_at (nullable). UNIQUE (store_id, external_order_id).
10. payment_claims: merchant_id, session_id, operator, trx_id, status
    (pending|verified|mismatch|rejected|expired|superseded), reason (nullable), candidate_sms_id
    (nullable -> sms_messages), match_deadline.
    Partial UNIQUE (merchant_id, operator, trx_id) WHERE status IN ('pending','verified','mismatch').
11. matches: merchant_id, claim_id UNIQUE, sms_id UNIQUE, method (auto|manual), user_id (nullable), note (max 200).
12. order_syncs: merchant_id, session_id UNIQUE, status (pending|done|failed), attempts int, next_attempt_at,
    last_error (nullable).
13. alerts: merchant_id, kind (phoneSilent|monitoringOff|noActiveDevice|shopifyReconnect|reviewWaiting|syncFailed),
    status (open|resolved), opened_at, last_sent_at, send_count int, resolved_at, details jsonb.
    Partial UNIQUE (merchant_id, kind) WHERE status = 'open' AND kind <> 'syncFailed'.
    Partial UNIQUE (merchant_id, (details->>'syncId')) WHERE kind = 'syncFailed'.
14. audit_log: merchant_id (NULLABLE only for system-wide entries such as the expiry job), actor_type
    (user|device|system), actor_id (nullable), action, entity, entity_id (nullable), data jsonb.
15. rate_limits: key text, window_start timestamptz, count int; PRIMARY KEY (key, window_start).
    (No uuid id and no merchant_id; it is a counter table.)

Triggers:
- set_updated_at on every table that has updated_at.
- trx_id = upper(trim(trx_id)) on sms_messages and payment_claims.
- Block DELETE (raise exception, for every role) on sms_messages, payment_sessions, payment_claims,
  matches, audit_log.
- Block UPDATE of sender, body, received_at and dedupe_hash on sms_messages; block every UPDATE on
  matches and audit_log.
- payment_sessions status change -> one audit_log row (actor system, action "session.status",
  data {from, to}).

Security (RLS and grants):
- Helper: is_owner(merchant_id) = the merchant's owner_id = auth.uid() (security definer, stable,
  fixed search_path).
- merchants: owner can select and update business_name; an authenticated user can insert one row with
  owner_id = auth.uid(). No delete.
- wallets: owner can select, insert and update. No delete.
- devices, stores, sms_messages, payment_sessions, payment_claims, matches, order_syncs, alerts, audit_log:
  owner can select only. No client insert, update or delete.
- stores.token_secret_id is not selectable by authenticated users (column privileges).
- parser_rules: any authenticated user can select active rules.
- shopify_install_states, shopify_webhook_events, rate_limits: no client access at all.
- anon has no access to any table.
- Every function in the next section: EXECUTE revoked from public, anon and authenticated; granted to
  service_role only.

Transactional SQL functions (plpgsql, security definer, fixed search_path; these back the Store methods):
- insert_sms(p jsonb) -> jsonb {sms, created}: insert, ON CONFLICT (merchant_id, dedupe_hash) do nothing,
  then return the existing row with created false.
- submit_claim(p_session_id, p_operator, p_trx_id) -> jsonb {claim} or {conflict: "alreadyUsed"}:
  lock the session (FOR UPDATE); attempts_left must be > 0 (else {conflict: "noAttemptsLeft"});
  mark the active claim superseded; insert the new claim with match_deadline now()+24h (unique violation ->
  alreadyUsed, nothing changed); attempts_left - 1; status pending; active_claim_id.
- record_verified(p_claim_id, p_sms_id, p_method, p_user_id, p_note) -> text ok | conflict:
  lock the claim, then the sms (always this order); claim must be pending or mismatch and sms unmatched,
  same merchant; insert match; claim verified; session verified with verified_at; sms matched.
  Any failure -> conflict and nothing changed.
- record_mismatch(p_claim_id, p_sms_id, p_reason) -> void.
- record_rejected(p_claim_id, p_user_id, p_note) -> void (only from mismatch).
- expire_due(p_now) -> jsonb {sessions, claims}: rules from spec 09 (mismatch never expires).
- hit_rate_limit(p_key, p_limit, p_window_seconds) -> boolean: one atomic upsert per window.
- consume_install_state(p_state_hash) -> jsonb or null: single use and not expired.
- mark_webhook_seen(p_webhook_id, p_topic, p_shop) -> boolean (true the first time).
- list_alert_inputs(p_now) -> setof jsonb with the fields from spec 11.
- save_shopify_tokens(p_store_id, p_tokens jsonb) and get_shopify_tokens(p_store_id) -> jsonb:
  tokens live only in Supabase Vault (create or update a secret, store its id in stores.token_secret_id);
  delete_shopify_tokens(p_store_id) removes the secret and clears the id.

Functional rules
- No table stores a Shopify token, a device private key, a pay token or a raw IP.
- No sample data in migrations; sample data only in seed.sql.
- Migrations run from empty with "supabase db reset" without errors.

Edge cases
- Two wallets with the same number for two merchants -> second insert fails.
- Two active bkash wallets on sim1 for one merchant -> fails; one on sim1 and one inactive on sim1 -> ok.
- A superseded or expired claim does not block a new claim with the same TrxID.
- record_verified called twice for the same claim with two different SMS -> second returns conflict.
- record_verified for two claims with the same SMS -> second returns conflict.
- A conflict leaves every row exactly as before.
- delete from sms_messages as service_role -> raises an exception.
- An authenticated user of merchant A selecting B's rows -> zero rows; inserting into A's sms_messages -> denied.

Non-functional rules
- Every foreign key has an index.
- Functions use fixed search_path (public, pg_temp) or schema-qualified names.
- Migrations and seed are UTF-8 without byte-order mark.

Acceptance criteria
- "supabase db reset" runs clean; "supabase test db" passes, covering at least:
  - RLS: for every table with merchant_id, user A sees only A's rows and user B only B's; anon sees nothing.
  - clients cannot insert into devices, stores, sms_messages, payment_sessions, payment_claims, matches,
    order_syncs, alerts, audit_log; can insert a merchant (only one per user) and wallets.
  - authenticated cannot select stores.token_secret_id; cannot execute any transactional function.
  - DELETE blocked on the five payment tables (also for service_role); sms immutable columns; matches and
    audit_log not updatable.
  - every unique and CHECK rule in Contract, including the wallet number patterns and the partial uniques.
  - submit_claim: decrement, supersede, alreadyUsed, noAttemptsLeft.
  - record_verified: ok; conflict cases; conflict changes nothing (compare rows before and after).
  - record_rejected only from mismatch; expire_due counts; mismatch not expired.
  - hit_rate_limit: allowed up to the limit, denied at limit + 1, allowed again in a new window.
  - insert_sms idempotent; consume_install_state single use and expiry; mark_webhook_seen true then false.
  - vault: save, get, update, delete tokens; the stores row never holds the token text.
  - set_updated_at works; trx_id upper-cased; session status change writes audit.
- "supabase db lint" reports no errors (if available in the installed CLI; otherwise say so).
- db_types.ts generated with "supabase gen types typescript --local".

Assumptions
- Specs 08 to 11 are done; their Store methods are the source for this schema.
- Supabase CLI with local Docker is installed. Supabase Vault and pgTAP are available locally.
- If a Store method from specs 08-11 cannot be backed by this schema, stop and tell me before adding anything.
