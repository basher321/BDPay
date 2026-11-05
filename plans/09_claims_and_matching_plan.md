# Plan 09 - Payment claims and matching engine

Spec: specs/09_claims_and_matching.md (builds on 07, 07a and 08)

## 0. Blocker: spec 08 does not exist

- There is no specs/08_device_and_sms_intake.md and no supabase/ folder: spec 08 was never written or built.
- Spec 09 extends spec 08's code: types.ts, store.ts, fake_store.ts, sms-ingest, NoopMatcher / the Matcher interface,
  the signed device request check, the audit log and spec 08's tests ("spec 08 tests still pass").
- So every "[CHANGED 08]" file below is **inferred from how spec 09 talks about it**, not read from real code. Their
  exact shape (names, function signatures, file layout) can only be fixed once spec 08 exists.
- D26 (blocker). Options: A (recommended) you give me spec 08 and we plan + build it first, then revisit this plan;
  B I build spec 09 together with the minimum of spec 08 that it needs (types, Store interface, FakeStore, device
  signature check, Matcher interface, sms-ingest) - that is building an unwritten spec, so I would not do it
  without your explicit yes and a spec text.

Other decisions needed before execution
- D27. **Step f uses an attempt, but the Store has no way to do that.** alreadyUsed in step f happens before
  submitClaim, and no listed store method lowers attemptsLeft on its own. Proposal: add
  `spendAttempt(sessionId) -> attemptsLeft` (one atomic decrement, never below 0).
- D28. **Store methods spec 09 needs but does not list** (unless spec 08 already has them):
  `listActiveWallets(merchantId)` (session operators), `getSms(smsId)` (claim-review notFound vs notAllowed),
  `getMerchantIdForUser(userId)` (claim-review owner check), `appendAudit(entry)` (if spec 08 has no audit), and
  getSmsResults must also return the **match** (its method decides "ম্যানুয়ালি অনুমোদিত" vs "অর্ডারের সাথে মিলেছে").
- D29. **A plain SHA-256 of an IP is not private.** There are only 2^32 IPv4 addresses, so the hash can be reversed by
  trying them all. Proposal: HMAC-SHA-256 with a secret env RATE_LIMIT_PEPPER (still "a SHA-256 hash, never the raw
  IP"). Same for the GET key: use the token hash, never the token.
- D30. **The smoke test can't use the real pay page yet.** Spec 09 forbids pay page changes (spec 13), the page's
  api.js only knows the mock, and its CSP is connect-src 'self'. Also a FakeStore lives in one process, so a script
  can't seed a session into a separately running function server. Proposal: smoke_match.ts runs all handlers in one
  process on one FakeStore (no Supabase CLI, no Docker), prints the pay page link for information only, and does the
  TrxID submit through the pay-session handler. Wiring the page to the real function is spec 13.
- D31. **"superseded" is not in CLAUDE.md's fixed claim status list** (pending, verified, mismatch, expired, rejected).
  Spec 09 adds it. Either CLAUDE.md is updated, or superseded claims use another value. Recommended: update CLAUDE.md.
- D32. **What happens to the SMS after the merchant rejects?** recordRejected marks claim and session rejected but
  leaves the SMS unmatched, and a rejected claim is not "live", so the same TrxID could later be claimed by another
  order with the matching amount and verify against that SMS. Is that wanted (the money did arrive), or should a
  rejected SMS be closed for good (e.g. sms status rejected)?
- D33. **recordMismatch and recordRejected return nothing, so they can't refuse a stale write.** Example: the matcher
  sees a pending claim and a wrong-amount SMS, but before it writes, another SMS with the same TrxID verifies the
  claim; a blind recordMismatch would then turn a verified session into mismatch. Same for reject racing approve
  (two browser tabs). Proposal: both become guarded one-block writes that return "ok" | "conflict" (mismatch only on
  the session's active pending claim with an unmatched SMS; reject only on an active mismatch claim). On conflict the
  caller re-reads and reports the current state; claim-review answers notAllowed.
- D34. **GET ?t=TOKEN puts the token in request URLs**, and URLs end up in proxy / platform access logs that our code
  does not control - a plain-token log path. Proposal: pay-session also accepts the token in a header
  (X-Pay-Token) and spec 13 makes the page use the header; ?t= stays supported for the spec contract. (The page's own
  address keeps ?t=, as spec 07 says.)
- D35. **Match has no merchantId.** CLAUDE.md: every merchant-owned table has a NOT NULL merchant_id (and RLS on it,
  spec 12). Proposal: add merchantId to Match in types.ts.
- D36. **Checking the Supabase user token needs a decision.** Options: A verify the JWT with Web Crypto against env
  SUPABASE_JWT_SECRET (no library, no download); B use supabase-js auth.getUser (an npm/jsr download - I would ask
  before fetching it). Either way the handler takes an injected verifier, so tests need neither.

## 1. Files

### New (supabase/functions/)
_shared/
- match_rules.ts - pure `evaluate(session, claim, sms)` -> {result: verified | mismatch | noMatch, reason}; the 6
  candidate rules as small exported predicates so each can be tested alone; integer poisha compare only.
- trx_format.ts - normalizeTrxId + isValidTrxId, a copy of pay_page/logic.js rules (the Edge bundle can't import
  files outside supabase/functions); a test checks both give the same answers.
- matcher.ts - the real Matcher: onSmsStored(sms) per contract 2; takes store, notifier, clock, logger.
- notifier.ts - OrderNotifier interface + NoopNotifier; `notifySafely()` that catches and logs (ids only).
- rate_limit.ts - key builders (token hash, HMAC'd IP, D29) and `checkRate(store, key, limit, window)`.
- cors.ts - headers only when Origin == env PAY_PAGE_ORIGIN; OPTIONS preflight answer.
- token.ts - newSessionToken() (32 random bytes, base64url), hashToken() (SHA-256 hex).
- session_view.ts - store records -> spec 07 Session JSON (+ rejected, expiresAt per status, operators from active
  wallets: merchant type first, then oldest; deviceOnline = seen in the last 10 minutes; echoes the request token).
- http.ts - json() / error() helpers in the {ok:false, error, message} shape, request-id, ids-only logger (only if
  spec 08 has none).
pay-session/handler.ts + index.ts - GET / POST / OPTIONS (handler takes deps so tests call it directly; index.ts
  wires Deno.serve with env and the store).
claim-review/handler.ts + index.ts - user-token auth (injected verifier), approve / reject, audit.
sms-status/handler.ts + index.ts - device-signed (spec 08 check), 1-100 ids, results per contract 4.
claims-expire/handler.ts + index.ts - X-Cron-Secret check (constant-time compare), expireDue, one audit entry.

### New tests (supabase/functions/tests/)
match_rules_test.ts, trx_format_test.ts, token_test.ts, session_view_test.ts, cors_test.ts, rate_limit_test.ts,
fake_store_claims_test.ts (all-or-nothing), matcher_test.ts, pay_session_get_test.ts, pay_session_post_test.ts,
race_test.ts, claim_review_test.ts, sms_status_test.ts, claims_expire_test.ts, notifier_test.ts,
helpers.ts (fixtures: merchant, wallets, device, session, SMS; fixed clock; recording notifier and logger).

### New script
supabase/scripts/smoke_match.ts - D30: in-process FakeStore run that prints the link and "verified".

### [CHANGED 08] (inferred - see section 0)
- _shared/types.ts - SessionStatus, ClaimStatus, MatchMethod, PaymentSession, PaymentClaim, Match.
- _shared/store.ts - the Store interface gets every method in the Contract (+ D27, D28).
- _shared/fake_store.ts - maps for sessions, claims, matches, rate counters; the new methods; transaction rules (section 3).
- sms-ingest (its wiring file) - NoopMatcher replaced by the real Matcher.
- The NoopMatcher itself stays (or is removed) depending on how spec 08 wires it.
- No spec 08 test file changes; they must still pass.

## 2. Order of work

0. D26 resolved (spec 08 exists and is green), D27-D36 answered.
1. match_rules.ts + match_rules_test.ts; trx_format.ts + parity test. `deno test`.
2. types.ts additions; store.ts interface; FakeStore methods + fake_store_claims_test.ts (all-or-nothing, uniqueness).
3. token, cors, rate_limit, session_view, notifier + their tests.
4. matcher.ts + matcher_test.ts; sms-ingest wiring; spec 08 tests still green.
5. pay-session GET, then POST (steps a-i) + tests; race_test.ts.
6. claim-review, sms-status, claims-expire + tests.
7. smoke_match.ts.
8. `deno test supabase/functions/tests`, `deno check`, `deno lint`, `deno fmt --check` on supabase/functions.

## 3. FakeStore: all-or-nothing, and the race test

How FakeStore makes a "transaction":
- JavaScript runs one piece of code at a time; other async work only gets in at an `await`. So submitClaim and
  recordVerified each do **all their checks and all their writes in one synchronous block with no await inside**.
  Nothing else can run in the middle.
- Inside that block: (1) read and check every precondition, (2) build the new records as copies, (3) only then write
  them all into the maps. If any check fails, the method returns "conflict" before step 3, so nothing changes.
- submitClaim re-checks inside the block, not only in the caller: session still open/pending, attemptsLeft > 0, and
  no live claim (pending/verified/mismatch) with the same merchant + operator + trxId -> else {conflict: "alreadyUsed"}.
  (The caller's step f check alone is racy: two sessions could both pass it.)
- submitClaim also re-checks the deadline inside the block (open session: now < submitDeadline) and, when it
  supersedes, only touches the session's own active claim if that claim is still pending.
- recordVerified re-checks inside the block, everything at once, else "conflict" and nothing changes:
  - the claim is the session's activeClaimId, and the session is pending (auto) or mismatch (manual);
  - auto: the claim is pending; manual: the claim is mismatch AND smsId equals its candidateSmsId;
  - the SMS is unmatched and belongs to the same merchant and operator, with the same trxId;
  - no match exists yet for this claimId, and none for this smsId.
  So a superseded, expired, rejected or already-verified claim can never be paid, and a matched SMS can never pay again.
- recordMismatch and recordRejected (D33) and expireDue use the same pattern: check, build, write, in one block;
  expireDue only expires a pending claim that is still its session's active claim, and only expires sessions whose
  status is open (past submitDeadline) or pending (active claim expired).
- The Store has no delete method at all (CLAUDE.md: claims, SMS records and matches are never deleted).
- Fault test: a test-only hook throws between "build" and "write"; the test shows the maps are unchanged.

Where the race can happen: between a caller's reads (findUnmatchedSms / findPendingClaimByTrx) and its write
(recordVerified). To make that window real in tests, FakeStore has a test-only `gate` option: read methods await
the gate, so a test can hold both callers after their reads and release them together.

race_test.ts:
- Setup: one open session (amount 125000) and one bKash SMS with the same TrxID and amount, stored as unmatched.
- In parallel: POST pay-session with that TrxID (submitClaim, then findUnmatchedSms -> evaluate -> recordVerified) and
  Matcher.onSmsStored(sms) (findPendingClaimByTrx -> evaluate -> recordVerified). The gate lets submitClaim finish,
  then holds both callers right after their reads, so both see "unmatched SMS + pending claim".
- Gate holds both after their reads, then releases; Promise.all.
- Checks: exactly 1 match in the store; claim verified; SMS matched; session verified; one caller got "ok", the other
  "conflict"; both responses still say verified (the loser re-reads, contract 2 last bullet); notifier called once.
- Plus a loop of 200 runs with random small delays in the gate, all must give one match.
- Plus two sessions submitting the same TrxID at once: exactly one gets accepted, the other alreadyUsed.
- Plus the stale-write races (D33): a gated recordMismatch after the claim was verified -> conflict, session stays
  verified; a customer changing the TrxID while the matcher holds the old claim -> recordVerified on the superseded
  claim -> conflict; approve and reject at once -> one wins; expireDue during a verify -> never both.

### Every path to "two payments" and what blocks it
| Path | Blocked by |
|---|---|
| Same SMS matched by two claims | recordVerified: SMS must be unmatched + no match for this smsId (one block) |
| Same claim paid by two SMS | recordVerified: claim must be pending/mismatch + no match for this claimId |
| Two sessions claim the same TrxID at once | submitClaim re-checks the live TrxID rule inside its block |
| Two SMS rows with the same TrxID (e.g. sent twice) | the first verified claim stays live for ever, so the TrxID is alreadyUsed for every later claim |
| Customer changes TrxID while the old claim is being matched | recordVerified requires the claim to be the session's activeClaimId and pending |
| Mismatch approved after another SMS already verified | manual approve requires smsId == candidateSmsId, claim mismatch, SMS unmatched |
| Expire and verify at the same time | both are guarded one-block writes; whichever runs second sees the new status and refuses |

## 4. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| deno test supabase/functions/tests passes, spec 08 tests too | full `deno test supabase/functions/tests` (needs D26) |
| match_rules: each of the 6 rules failing alone | match_rules_test (6 cases, everything else valid) |
| match_rules: verified; mismatch reason amount | match_rules_test (45000 vs 45000; 43000 vs 45000) |
| 30-minute boundary: exactly 30 min before = candidate, 30 min 1 s = not | match_rules_test |
| GET: Session JSON fields; expiresAt per status | pay_session_get_test (open, pending, verified, mismatch, expired, rejected) |
| GET: notFound | pay_session_get_test (404) |
| GET: rate limit at the 61st call | pay_session_get_test (60 x 200, 61st 429) |
| POST: every result value | pay_session_post_test (accepted, invalidFormat, alreadyUsed, noAttemptsLeft, expired, notFound, rateLimited) |
| POST: SMS first -> verified at submit | pay_session_post_test |
| POST: claim first, then onSmsStored -> verified | pay_session_post_test + matcher_test |
| POST: change TrxID supersedes (5 -> 4 -> 3) | pay_session_post_test (old claim superseded) |
| POST: same TrxID twice uses no attempt | pay_session_post_test |
| POST: attempts to 0 -> noAttemptsLeft | pay_session_post_test |
| POST: alreadyUsed across sessions | pay_session_post_test (verified elsewhere; live elsewhere) |
| POST: operator not offered -> invalidFormat | pay_session_post_test |
| POST: 21st POST from one IP -> rateLimited | pay_session_post_test |
| CORS only for PAY_PAGE_ORIGIN | cors_test + pay_session tests (other origin: no Access-Control-Allow-Origin; OPTIONS) |
| race: submit and onSmsStored in parallel -> one match | race_test (section 3) |
| claim-review: approve, reject, notAllowed, notFound, other merchant's sms -> notFound, audit written | claim_review_test |
| sms-status: verified, mismatch with claim info, rejected by merchant, pending, other merchant's ids left out | sms_status_test (+ manual-approval message) |
| claims-expire: wrong secret 401; open past deadline expired; pending claim past 24 h expired; mismatch not expired | claims_expire_test (+ one audit entry with counts) |
| notifier once per verification; throwing notifier leaves verified | notifier_test (auto, manual, race) |
| deno check / lint / fmt --check pass | the three commands on supabase/functions |
| Local smoke test prints "verified" | you run `deno run ... supabase/scripts/smoke_match.ts` with BDPAY_FAKE_STORE=1 (D30) |

Other rules checked too

| Rule | Check |
|---|---|
| Token never stored, only its hash | fake_store_claims_test: no raw token in any record; search |
| Never log TrxID, payer, SMS text, tokens, IPs | recording logger in every test asserts none of the fixture values appear; search for console.* in _shared and functions |
| Money compared as integer poisha | match_rules_test with non-integer input rejected; search: no parseFloat / Number( on amounts |
| Mismatch claims never expire | claims_expire_test |
| Verified / rejected final; step b returns current session | pay_session_post_test |
| SMS 2 h before the order -> not a candidate; another merchant's SMS -> never | match_rules_test + pay_session_post_test |
| Session creation: 32-byte base64url token, deadline +60 min, 5 attempts | token_test + fake_store_claims_test |
| Normalization matches the pay page | trx_format_test imports pay_page/logic.js and compares on a list of inputs |
| Edge case 43000 vs 45000: approve -> session verified (manual) and sms-status says verified "ম্যানুয়ালি অনুমোদিত"; reject -> session rejected and sms-status says rejected "ম্যানুয়ালি বাতিল" | claim_review_test + sms_status_test (one flow each) |
| Stale writes refused (D33) | race_test + fake_store_claims_test |
| Merchant scoping: every lookup uses the merchant from the session, the device or the user | tests with two merchants sharing a TrxID: no cross-merchant match, result or review |
| Store has no delete | search: no delete method in store.ts / fake_store.ts |
| Logs and error bodies never echo input | recording logger + error-body checks in every handler test (the fixture TrxID, token, IP, payer and SMS text never appear) |
| No remote imports (nothing downloaded) | search: no https:, npm: or jsr: imports in supabase/functions (unless D36 = B, asked first) |
| New files UTF-8 without BOM | search |

## 5. Unclear or wrong in the spec

1. **Spec 08 is missing** -> D26.
2. **Step f spends an attempt without a store method** -> D27.
3. **Missing store methods** (wallets, sms by id, user -> merchant, audit, match in getSmsResults) -> D28.
4. **IP hash reversible** -> D29. **Client IP source**: the first x-forwarded-for entry is only trustworthy behind
   Supabase's proxy; tests inject the IP.
5. **Smoke test vs "no pay page changes"** -> D30.
6. **"superseded" vs CLAUDE.md** -> D31.
7. **SMS after a rejected claim** -> D32.
8. **Open session past submitDeadline before the cron runs.** GET would still say open with a negative countdown.
   Plan: session_view reports expired (and expiresAt null) when status is open and now is past submitDeadline; the
   stored status changes when claims-expire runs. POST step b already treats it as expired.
9. **sms.receivedAt is the phone's time** (spec 06: the SMS timestamp). Rules 5 and 6 trust it. A wrong phone clock
   could push a real payment out of the window. Noted; using the server's arrival time is the alternative.
10. **Expired claims have no manual path.** If the SMS arrives after 24 h (phone offline a day), the claim is expired
    and claim-review only handles mismatch. The money arrived but nothing can verify it. Noted for a later spec.
11. **Session JSON needs the token** (spec 07 has a token field). It is not stored, so GET/POST echo the token from
    the request.
12. **mismatch_reason duplicate_trxid** (CLAUDE.md) is never produced: alreadyUsed is answered before a claim
    exists. Fine, noted.
13. **Matcher conflict "read the current state and return it"**: plan returns the SMS's current result through the same
    logic as sms-status, so both callers report verified in the race.
14. **claims-expire secret compare** should be constant-time (timingSafeEqual on hashes) - planned.
15. **Pay page CSP / connect-src** must list the function origin in spec 13; CORS here allows PAY_PAGE_ORIGIN only.
16. **recordMismatch / recordRejected can't refuse** -> D33. **Token in the GET URL** -> D34. **Match without
    merchantId** -> D35. **User-token check** -> D36.

## 6. Where TrxID, tokens, IPs and SMS text go

| Value | Stored | Logged | Guard |
|---|---|---|---|
| Session token | never; only SHA-256 hash (tokenHash) | never | token.ts hashes on arrival; rate-limit key uses the hash; D34 keeps it out of URLs; the smoke script prints the pay link once, by spec, on your own machine |
| Client IP | never; only HMAC-SHA-256 with a secret pepper (D29), inside the rate-limit key | never | read from the header in memory only |
| TrxID | yes, in the claim (needed to match; CLAUDE.md: trimmed, upper case) | never | logger takes ids only; error bodies use fixed messages |
| SMS text / payer number | not by spec 09 (spec 08 stores SMS) | never | matcher reads amounts and TrxID only |
| Audit entries | old/new status, note, ids | - | no TrxID, token, IP or SMS text in audit data |
| Errors | - | name + request id only | exception messages are never logged or returned (they can contain input) |

## 7. Review log

Review 1 against spec 09 and CLAUDE.md:
- Scope: no SQL, Shopify, Flutter or pay page change. trx_format_test only reads pay_page/logic.js. D26 option B
  (building spec 08) and D36 option B (a download) stay decisions.
- Two payments: the plan already had uniqueness checks in recordVerified and submitClaim. Found and fixed: the claim
  must also be the session's active claim and pending (auto) or mismatch with the same candidate SMS (manual); the
  submit deadline is re-checked inside submitClaim; recordMismatch / recordRejected / expireDue must be guarded too
  (D33) or a verified session could flip to mismatch. Added the "every path" table and stale-write race tests.
- Plain values: added section 6. Found: the token in GET URLs reaches access logs (D34); exception messages could
  carry input -> never logged or returned; audit data holds no TrxID/token/IP/SMS text.
- Criteria: all had a check. Added rows for the 43000/45000 approve/reject flow through sms-status, merchant scoping
  with two merchants, stale writes, no delete, logs/error bodies, no remote imports, BOM.
- CLAUDE.md: Match lacks merchant_id (D35); "superseded" (D31); never delete -> Store has no delete; RLS-like
  scoping enforced in every lookup until spec 12; downloads only with your yes (D36).


## 8. Execution log (2026-10-29)

- D26 answered "only match_rules now": spec 08 still does not exist, so only the pure match_rules.ts and its tests
  were built. No store, functions, matcher, notifier or smoke script yet; no spec 08 file was created or changed.
- match_rules.ts declares its own minimal input types (only the fields the rules read) so it depends on nothing;
  spec 08's records can be passed in once they exist. evaluate() returns the first failed rule as the noMatch reason.
- Results: deno test 13 passed; deno check, deno lint, deno fmt --check clean; no console.*, no remote imports.
