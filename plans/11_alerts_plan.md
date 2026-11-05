# Plan 11 - Alerts

Spec: specs/11_alerts.md (changes spec 08's device-heartbeat and spec 10's shopify-sync / ShopifyNotifier)
Revised 2026-10-30 against the re-saved spec. Replaces the 2026-10-29 draft; its decisions D55-D61 are kept,
D62-D67 are new. Reviewed 2026-10-30 against the spec's Scope and CLAUDE.md (section 5).

Default rule for every decision below: until you say yes to a proposal, the build follows the spec text exactly.
Proposals marked [CONTRACT] change the spec's Store, AlertInput or decide() contract and are built only with your yes.

## 0. Blocker

- specs/08_device_and_sms_intake.md does not exist (no spec, no plan, no code). Of spec 09 only match_rules.ts is
  built; of spec 10 only the pure parts (money_text, shopify_auth, shopify_orders, shopify_client, fake_shopify).
  device-heartbeat, Store / FakeStore, shared types, shopify-sync, ShopifyNotifier and the spec 09 user-token check
  do not exist.
- The spec's assumption "Specs 08, 09 and 10 are done" is therefore false today.
- The pure parts of spec 11 (alert_rules, alert_messages, mailer) need nothing from 08/10 and can be built now.
  Everything else waits. Every [CHANGED 08] / [CHANGED 10] item below is inferred from the specs, not read from code.

## 1. Files

### New - supabase/functions/_shared/
- alert_rules.ts - pure: AlertKind, Alert, AlertInput, Action types; REMINDERS table (interval, max per kind);
  decide(input, openAlerts, now). No I/O, no Date.now. Ignores event alerts (syncFailed) in openAlerts and never
  emits two actions for the same kind.
- alert_messages.ts - pure: Bangla subject + text per kind and for phoneSilent fixed; title/hint for alerts-list;
  Dhaka time formatting. Inputs are only businessName, counts, a time and orderRef - there is no parameter through
  which a TrxID, amount, payer number, SMS text, token or email address could enter.
- mailer.ts - Mailer interface send({to, subject, text}) -> "sent" | "failed"; FakeMailer (in-memory, can be set
  to fail). The result carries no error detail, so no provider message (which may echo the address) reaches a log.
  No real provider (spec 15).

### New - Edge Functions (after specs 08/10)
- alerts-check/index.ts - Deno.serve entry; wires env, Store, Mailer (FakeMailer until spec 15).
- alerts-check/handler.ts - X-Cron-Secret check (constantTimeEqual from shopify_auth.ts); per merchant: decide,
  apply, send, with its own try/catch; then up to 50 unsent event alerts, each sent to the contact of that alert's
  own merchantId; returns the counts.
- alerts-list/index.ts - Deno.serve entry.
- alerts-list/handler.ts - user token (spec 09 D36 method), caller's merchant only; open condition alerts + event
  alerts of the last 7 days, newest first, with title and hint.

### New tests - supabase/functions/tests/
- alert_rules_test.ts - every rule, edge case, reminder timing/limit per kind, fixed-email rule, monitoringOff vs
  phoneSilent, retry of a failed email, no duplicate open action; fixed clock.
- alert_messages_test.ts - shape of every message, Dhaka time, the privacy scan (and a test that the scan catches
  injected TrxID / amount / phone).
- mailer_test.ts - FakeMailer records and fails on demand.
- alerts_check_test.ts - 401, counts, mail failure + retry, no email, one merchant throwing, no-log check, privacy
  scan over every mail in the FakeMailer outbox, two runs at once.
- alerts_list_test.ts - caller-only, newest first, 7-day window, Bangla title/hint.
- heartbeat_health_test.ts - [CHANGED 08] heartbeat saves the three health fields.
- shopify_sync_alert_test.ts - [CHANGED 10] one syncFailed per failed OrderSync.

### [CHANGED 08] spec 08 files (not built yet)
- _shared/types.ts - Device gets lastSmsPermission, lastMonitoring, lastBatteryOk (boolean | null).
- _shared/store.ts - Store interface gets exactly the 8 alert methods from the Contract (D59/D60 only with your yes).
- _shared/fake_store.ts - in-memory implementation of those methods:
  - openAlert for a condition kind returns the existing open alert when one exists (never a second row); it refuses
    the event kind syncFailed.
  - createEventAlert is idempotent on (merchantId, kind, details.syncId); it refuses condition kinds.
  - every method takes or checks merchantId; no method returns another merchant's alert.
- device-heartbeat/handler.ts - also saves smsPermission, monitoring, batteryOptimizationOff (D63).

### [CHANGED 10] spec 10 files (not built yet)
- _shared/shopify_notifier.ts - when an OrderSync turns failed (24th attempt), createEventAlert(merchantId,
  "syncFailed", {orderRef, syncId}).
- shopify-sync/handler.ts - same hook if the failed transition happens in the sync loop rather than the notifier
  (one shared function so it is raised in exactly one place).

### Not built in this step (Scope check)
- No real email provider, sender address or provider package (spec 15). FakeMailer only.
- No SMS or push alerts, no merchant alert settings.
- No SQL, migration, table, unique index or RLS policy (spec 12). Uniqueness lives in FakeStore for now; spec 12
  must add a partial unique index on (merchant_id, kind) where status = 'open' for condition kinds - noted for spec 12,
  not written here.
- No app or dashboard change; showing alerts is spec 13.
- No package added; no remote imports.

## 2. Order of work

0. You answer D55-D67 (unanswered = spec text).
1. alert_rules.ts + alert_rules_test.ts. Run deno test, check, lint, fmt --check.
2. alert_messages.ts + alert_messages_test.ts (with the privacy scan).
3. mailer.ts + mailer_test.ts.
   -- stop here until specs 08 and 10 are built (D55 = A) --
4. [CHANGED 08] types + Store/FakeStore additions; device-heartbeat change + heartbeat_health_test.
5. [CHANGED 10] notifier / shopify-sync hook + shopify_sync_alert_test.
6. alerts-check + alerts_check_test.
7. alerts-list + alerts_list_test.
8. Full deno test supabase/functions/tests (08-10 still green), deno check, deno lint, deno fmt --check;
   searches for logging, remote imports, BOM.

## 3. Acceptance criteria -> test or check

| Criterion | Test or check |
|---|---|
| deno test passes, specs 08-10 still pass | full `deno test supabase/functions/tests` (needs 08/10) |
| Silent 16 min, no pending -> opens, 1 email | alert_rules_test (open) + alerts_check_test (exactly 1 mail in FakeMailer) |
| Silent 6 min, 2 pending -> opens early | alert_rules_test at 6 min (spec value; also 4 min with pending -> nothing) |
| Back after 3 h -> resolved + one fixed email | alert_rules_test (sendFixed true) + alerts_check_test (1 fixed mail) |
| Flaps -> new alert each time, no duplicate open | alert_rules_test timeline + alerts_check_test timeline: 2 alerts total, never 2 open |
| 2 phones, one silent -> no phoneSilent | alert_rules_test (newestDeviceSeenAt recent) |
| Shopify 10 min, no phone -> nothing; 31 min -> noActiveDevice | alert_rules_test (also exactly 30 min -> nothing) |
| Mail down -> mailFailed, stays open, retried next run | alerts_check_test: failing FakeMailer, then working one |
| syncFailed twice for one OrderSync -> one event alert | shopify_sync_alert_test + FakeStore idempotency test |
| Reminder timing + limits per kind; phoneSilent 7th not sent | alert_rules_test for each of the 5 condition kinds: none before interval, one at it, none past the limit (D56) |
| monitoringOff does not open while phoneSilent open | alert_rules_test (+ D61 if answered) |
| Fixed email only after a sent phoneSilent email | alert_rules_test: sendCount 0 -> sendFixed false; >0 -> true; other kinds never |
| Heartbeat saves the three health fields | heartbeat_health_test (true, false and missing -> null) |
| shopify-sync raises one syncFailed on failed | shopify_sync_alert_test (23 failures -> none; 24th -> one; a later run -> still one) |
| alerts-check wrong secret -> 401 | alerts_check_test (missing and wrong header) |
| One merchant throwing does not stop the next | alerts_check_test with a FakeStore that throws for merchant A; B still gets its mail |
| alerts-list: caller only, newest first, Bangla title + hint | alerts_list_test (2 merchants; 8-day-old event and resolved alert left out; exact title/hint strings) |
| Privacy scan of every generated email | alert_messages_test over every kind + fixed mail, AND alerts_check_test over every mail in the FakeMailer outbox (pattern per D64) |
| deno check / lint / fmt --check | the three commands |

Other spec rules

| Rule | Test or check |
|---|---|
| Subject starts "BDPay: ", text starts "{businessName}," ends "— BDPay" | alert_messages_test, every kind |
| Times in Asia/Dhaka | alert_messages_test (UTC 12:00 shown as 06:00 PM) |
| No email address -> skip, lastSentAt null, no crash | alerts_check_test (D58) |
| Failed email retried, not counted as reminder | alert_rules_test + alerts_check_test (D57) |
| At most one open alert per merchant + condition kind | fake_store test (openAlert twice -> same id); alert_rules_test (no double open action); alerts_check_test (two runs at once -> one open alert) |
| Never log email addresses or bodies | alerts_check_test with a recording logger: no fixture address, subject or body text in any line, including in the per-merchant catch; search of console calls in the new files |
| details never hold TrxID, amounts, payer numbers, SMS text | types: details typed per kind ({} or {orderRef, syncId}); review |
| alert_rules.ts pure, fully unit-tested | review (no imports beyond types, clock is a parameter) + `deno test --coverage` shows every branch of alert_rules.ts hit |
| Merchant isolation | alerts_list_test (other merchant's alerts never returned); alerts_check_test (event alert mail goes to its own merchant's contact) |
| Files UTF-8 without BOM, no remote imports | searches |

## 4. Unclear or wrong in the spec

Decisions kept from the 10-29 draft
- D55. Build order: A (recommended) build steps 1-3 now, the rest after specs 08/10; B wait for everything.
- D56. "At most 6 emails" vs "phoneSilent 7th reminder not sent". 6 emails = first + 5 reminders, so the "7th
  reminder" never comes up. Proposal: the limit counts all emails (sendCount); the test checks the 7th email is not
  sent. Same for 4 and 7.
- D57. [CONTRACT] decide() has no action for re-sending a failed first email. Proposal: add {retry, alertId};
  counted in neither opened nor reminded. Without it: the retry is a remind action that the handler does not count as
  a reminder.
- D58. No email address: retried every 5 minutes forever. Proposal: skip, not counted as mailFailed, log
  "merchantId, kind, noEmail".
- D59. [CONTRACT] Two overlapping alerts-check runs. openAlert keeps the alert itself unique (it returns the existing
  one), but both runs may then send the first email or the same reminder. Proposal: markAlertSent becomes
  compare-and-set on the old lastSentAt (claim, then send, roll back on failure). Without it: a rare double email,
  never a double alert.
- D60. syncFailed details: "only orderRef" vs "orderRef + syncId, unique". Proposal: {orderRef, syncId}; syncId only
  for uniqueness, never in an email or alerts-list.
- D61. monitoringOff already open when phoneSilent opens. Proposal: it stays open, no reminders while phoneSilent is
  open, resolves normally.

New in this revision
- D62. phoneSilent may fire falsely when claims are pending. Heartbeats come every 5 minutes, and the early rule opens
  at "older than 5 minutes", so a normal delay (network, Doze) of a few seconds can send a false "phone offline"
  email. The plan builds and tests the spec's 5 minutes. Recommendation for you: change the spec to 10 minutes (two
  missed heartbeats) and the edge case to about 11 minutes; I change nothing unless you edit the spec.
- D63. Health field names don't match. Heartbeat sends batteryOptimizationOff, the device record stores
  lastBatteryOk. Proposal: lastBatteryOk = batteryOptimizationOff (off = OK). No rule uses it, it's only saved.
- D64. The "01" phone check would fail on normal text. "01" matches times ("01:05 PM") and dates. Proposal: scan for
  01[3-9] + 8 digits (Bangla digits converted first), TrxID-like tokens (8-14 upper-case letters/digits with at least
  one digit), "৳" followed by a digit, and "@" (email address); the test also proves the scan catches injected samples.
- D65. [CONTRACT] Alerts can stay open forever. listAlertInputs only returns merchants with an active device or store.
  A merchant who revokes the last phone and has no store, or whose store is uninstalled, drops out, so an open
  phoneSilent / shopifyReconnect never resolves and stays in alerts-list. Proposal: listAlertInputs also returns
  merchants that have an open alert, so the normal rules resolve them. Without it: built as the spec says, noted.
- D66. Gaps in the spec's wording:
  (a) activeDeviceCount > 0 with newestDeviceSeenAt null (paired, never sent a heartbeat). Without a decision: no
      phoneSilent (nothing to compare). [CONTRACT] Proposal: add pairedAt to AlertInput and treat it as last seen.
  (b) The fixed email's body text is not given. Proposal: "{businessName}," + phone reconnected, BDPay is checking
      payments again + "— BDPay".
  (c) A failed event alert is retried every 5 minutes with no limit. Without a decision: retried as the spec says.
      [CONTRACT] Proposal: stop after 7 failed tries.
  (d) Event alert status: nothing resolves syncFailed. Proposal: it stays open, is never reminded, is ignored by
      decide() and by the one-open-per-kind rule, and alerts-list shows it for 7 days by openedAt.
- D67. businessName can carry a phone number. It is merchant-typed and goes into the first line of every email. A name
  like "Rahim Store 01712345678" would make a real email fail the outbox scan, and puts a phone number in the email
  (the merchant's own, not a payer's). Proposal: the scan checks the generated part of the email, skipping only
  the exact businessName first line; tests use a clean name plus one with a number to show the skip.

Notes (no decision needed)
- One silent phone among several is never alerted (spec's choice); payments to that SIM can't be verified then.
- reviewWaiting's {n} is counted at send time, so a reminder can show a different n.
- Email time format: "29 Oct 2026, 06:25 PM" (fixed UTC+6, Latin digits, same as the app).
- orderRef is Shopify's order name ("#1045"); a merchant-set prefix/suffix could contain digits. It is covered by the
  outbox scan; it is never a TrxID, amount or payer number.

## 5. Review against CLAUDE.md

| Rule | How the plan keeps it |
|---|---|
| Do only what the current step spec says | default = spec text; contract changes marked [CONTRACT] and only with your yes; Scope section lists what is not built |
| Add no package the spec does not name | no package, no remote import; FakeMailer only |
| merchant_id on every merchant table, merchant sees only its own rows | every alert has merchantId; FakeStore filters by it; alerts-list tested with 2 merchants; SQL/RLS is spec 12 |
| Times stored UTC, shown Asia/Dhaka | ISO UTC in records; Dhaka only in email text |
| Fixed values as enums / unions / CHECK lists | AlertKind and alert status as TypeScript string unions with the spec's wire names (CLAUDE.md's list doesn't have them yet; add when spec 12 writes the CHECK) |
| Never log secrets / tokens | CRON_SECRET compared, never logged; logs are merchantId, kind, action only |
| Never read .env | handler reads env at runtime only; tests pass fake values; I don't open .env |
| All user-facing text from ARB files (frontend rule) | conflict noted: alerts-list returns Bangla title/hint from the server (spec says so). The rule is for Flutter code; spec 13 can map kind -> ARB text and ignore the server title. To decide in spec 13. |
| Plain UTF-8, no BOM | search in step 8 |
| No DB change except a new migration | no SQL in this step |
| Ask before commands that change data or installed software | only deno check / lint / fmt --check / test, which change nothing; anything else asked first |
