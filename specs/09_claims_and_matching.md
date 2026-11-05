# 09 Payment claims and matching engine

Purpose
Connect the two halves of every payment: the customer's TrxID (from the pay page) and the
merchant phone's SMS (from spec 08). Decide verified, mismatch, pending, rejected or expired by
fixed rules, never twice for the same money, and let the merchant decide mismatches by hand.

Scope
- Edge Functions (TypeScript, Deno) in supabase/functions/:
  - pay-session: the public API for the pay page (GET session/status, POST TrxID).
  - claim-review: the merchant's approve / reject (Supabase user token).
  - sms-status: the phone asks for the latest result of its SMS (signed device request).
  - claims-expire: expires old sessions and claims (called by a schedule, protected by a secret header).
- Shared code in supabase/functions/_shared/:
  - match_rules.ts: pure functions for the rules below.
  - matcher.ts: the real Matcher (replaces NoopMatcher from spec 08).
  - notifier.ts: OrderNotifier interface and NoopNotifier (spec 10 adds Shopify).
  - rate_limit.ts, cors.ts, token.ts (make and hash session tokens), session_view.ts
    (turn store records into the spec 07 Session JSON).
  - Additions to store.ts and fake_store.ts listed in Contract.
- Deno tests in supabase/functions/tests/.
- Not in scope: SQL and tables (spec 12), Shopify and creating sessions from orders (spec 10),
  alerts (spec 11), Flutter or pay page code changes (spec 13).

Contract
Records (types.ts additions; wire names match future SQL CHECK values):
- SessionStatus: open | pending | verified | mismatch | expired | rejected.
- ClaimStatus: pending | verified | mismatch | rejected | expired | superseded.
- MatchMethod: auto | manual.
- PaymentSession: id, merchantId, storeId, tokenHash, orderRef, externalOrderId (or null), amountPoisha,
  status, submitDeadline, attemptsLeft (starts 5), returnUrl, activeClaimId (or null), createdAt,
  verifiedAt (or null).
- PaymentClaim: id, merchantId, sessionId, operator, trxId (upper case), status, reason (or null),
  candidateSmsId (or null), matchDeadline (createdAt + 24 h), createdAt.
- Match: id, claimId, smsId, method, userId (or null), note (or null), createdAt.

Store additions (spec 12 builds tables and one-transaction functions from these):
  createPaymentSession(fields) -> PaymentSession          (used by spec 10 and tests)
  getSessionByTokenHash(hash) -> PaymentSession | null
  getMerchantName(merchantId) -> string
  hasDeviceSeenSince(merchantId, time) -> boolean
  findLiveClaimByTrx(merchantId, operator, trxId) -> PaymentClaim | null   (status pending, verified or mismatch)
  submitClaim({sessionId, operator, trxId}) -> {claim} | {conflict: "alreadyUsed"}
      ONE transaction: mark the session's current active claim superseded, create the new claim,
      lower attemptsLeft by 1, set session status pending and activeClaimId.
  findUnmatchedSms(merchantId, operator, trxId) -> SmsRecord | null
  findPendingClaimByTrx(merchantId, operator, trxId) -> PaymentClaim | null
  recordVerified({claimId, smsId, method, userId, note}) -> "ok" | "conflict"
      ONE transaction: create the match (claimId and smsId each unique), claim verified,
      session verified with verifiedAt, sms matched. If any part is already taken -> conflict, nothing changes.
  recordMismatch({claimId, smsId, reason}) -> void   (claim mismatch, candidateSmsId, session mismatch)
  recordRejected({claimId, userId, note}) -> void    (claim rejected, session rejected)
  findMismatchClaimBySms(smsId) -> PaymentClaim | null
  getSmsResults(merchantId, smsIds) -> [{sms, claim (or null), session (or null)}]
  expireDue(now) -> {sessions: number, claims: number}
      open sessions past submitDeadline -> expired; pending claims past matchDeadline -> claim expired
      and its session expired. Mismatch claims never expire (they wait for the merchant).
  hitRateLimit(key, limit, windowSeconds) -> boolean (true = allowed)
  getClaim(id), getSession(id) -> record | null

OrderNotifier (notifier.ts): onSessionVerified(session) -> void. NoopNotifier does nothing.
It is called AFTER recordVerified succeeds. If it throws, the payment stays verified
(spec 10 retries Shopify separately).

Match rules (match_rules.ts, pure):
evaluate(session, claim, sms) -> "verified" | "mismatch" | "noMatch", with a reason.
An SMS is a candidate for a claim only when ALL are true:
  1. same merchantId; 2. same operator; 3. same trxId (both upper case, trimmed);
  4. sms.status is unmatched; 5. sms.receivedAt is not earlier than session.createdAt minus 30 minutes;
  6. sms.receivedAt is not later than claim.matchDeadline.
Then: amounts equal -> verified. Amounts differ -> mismatch, reason "amount".
Not a candidate -> noMatch (the claim stays pending).

Session JSON for the pay page (session_view.ts) is exactly the spec 07 Session, plus:
- status may be rejected (spec 07a).
- expiresAt = submitDeadline while open; = the active claim's matchDeadline while pending;
  = null for verified, mismatch, expired and rejected.
- operators = one entry per operator from the merchant's active wallets (prefer accountType merchant,
  then the oldest wallet).
- deviceOnline = any active device seen in the last 10 minutes.
- submittedOperator / submittedTrxId come from the active claim.
The token is never stored; only its SHA-256 hash.

Function contracts (JSON; errors are {ok: false, error, message}):

1. pay-session (public; CORS allowed only for the origin in env PAY_PAGE_ORIGIN; OPTIONS answered)
   GET ?t=TOKEN -> 200 Session, or 404 {error: "notFound"}.
     Rate limit: 60 per minute per token, else 429 rateLimited.
   POST {token, operator, trxId} -> 200 {result, session} with result:
     accepted | invalidFormat | alreadyUsed | noAttemptsLeft | expired | notFound | rateLimited.
     Steps:
     a. Rate limit 20 per 10 minutes per client IP (stored as a SHA-256 hash, never the raw IP) ->
        rateLimited.
     b. Session missing -> notFound. Status expired or now past submitDeadline while open -> expired.
        Status verified, mismatch or rejected -> accepted with the current session (no change).
     c. Normalize trxId (Bangla digits, spaces, upper case) and check the spec 07 format for that operator
        -> invalidFormat (no attempt used). Operator not in the session's operators -> invalidFormat.
     d. Same operator and trxId as the active claim -> accepted, no attempt used.
     e. attemptsLeft is 0 -> noAttemptsLeft.
     f. findLiveClaimByTrx finds a claim of ANOTHER session -> alreadyUsed (one attempt used).
     g. submitClaim. A conflict -> alreadyUsed.
     h. findUnmatchedSms, then evaluate: verified -> recordVerified then notifier;
        mismatch -> recordMismatch; noMatch -> stays pending.
     i. Return accepted with the fresh session.

2. Matcher.onSmsStored(sms) (called by sms-ingest from spec 08)
   - sms.status not unmatched -> {verifyStatus: "rejected", ...} unchanged behaviour from spec 08.
   - findPendingClaimByTrx; none -> {pending, null}.
   - evaluate with that claim's session: verified -> recordVerified + notifier -> {verified, "অর্ডারের সাথে মিলেছে"};
     mismatch -> recordMismatch -> {mismatch, "অর্ডারের টাকার সাথে মেলেনি"}; noMatch -> {pending, null}.
   - recordVerified conflict -> read the current state and return it.

3. claim-review (Supabase user token; the user must own the claim's merchant)
   POST {smsId, decision: approve | reject, note (optional, max 200)}
   -> 200 {ok: true, result: done | notAllowed | notFound}
   - findMismatchClaimBySms; none -> notFound if the sms does not belong to the user's merchant,
     else notAllowed.
   - approve -> recordVerified(method manual, userId, note) then notifier. Conflict -> notAllowed.
   - reject -> recordRejected.
   - Audit "claim.approve" or "claim.reject" with old and new status and the note.

4. sms-status (signed device request, same check as spec 08)
   POST {smsIds: [...]} (1 to 100, only the device's own merchant) ->
   200 {ok: true, results: [{smsId, verifyStatus, serverMessage, claim: {claimId, orderRef,
   expectedAmountPoisha} or null}]}
   verifyStatus: sms rejected -> rejected; sms matched -> verified; a claim with candidateSmsId = this sms
   and status mismatch -> mismatch; that claim rejected -> rejected; otherwise pending.
   serverMessage: verified "অর্ডারের সাথে মিলেছে" (manual: "ম্যানুয়ালি অনুমোদিত"), mismatch "অর্ডারের টাকার সাথে মেলেনি",
   rejected by merchant "ম্যানুয়ালি বাতিল", pending null.
   SMS ids of another merchant are left out of the results.

5. claims-expire (header X-Cron-Secret must equal env CRON_SECRET, else 401)
   POST {} -> expireDue(now) -> 200 {ok: true, sessions, claims}. Audit one "claims.expire" entry with the counts.

Functional rules
- One SMS pays at most one claim, and one claim is paid by at most one SMS (store-level guarantee).
- A TrxID can be live on only one claim per merchant + operator.
- Verified, mismatch-decided and rejected results are final for the customer; the only change after
  mismatch is the merchant's decision.
- Session creation (for tests and spec 10): token = 32 random bytes, base64url; submitDeadline =
  createdAt + 60 minutes; attemptsLeft 5.
- All money compared as integer poisha.

Edge cases
- SMS first, TrxID later -> verified at submit.
- TrxID first, SMS later (within 24 h) -> verified when the SMS arrives.
- TrxID and SMS at the same moment from two requests -> exactly one match; both callers end up
  reporting verified.
- Customer submits a wrong TrxID, then changes it while pending -> old claim superseded, new claim
  checked; attempts go 5 -> 4 -> 3.
- Customer submits the same TrxID twice -> no attempt used the second time.
- Customer reuses a TrxID that verified another order -> alreadyUsed.
- SMS amount 43000, order 45000 -> mismatch; merchant approves -> verified (manual) and the SMS shows
  verified; merchant rejects -> session rejected, SMS shows rejected.
- An SMS received 2 hours before the order was created -> not a candidate (rule 5).
- An SMS from another merchant's phone with the same TrxID -> never a candidate.
- Pending claim with no SMS for 24 h -> claims-expire marks it and its session expired.
- Approving a claim that is not mismatch -> notAllowed.
- notifier throws -> the session stays verified and the error is logged without payment details.

Non-functional rules
- Never log TrxID, payer number, SMS text, tokens or IPs. Log function, request id, result and ids only.
- match_rules.ts is pure and fully unit-tested.
- deno check, deno lint and deno fmt --check pass on supabase/functions.

Acceptance criteria
- deno test supabase/functions/tests passes (spec 08 tests still pass), covering:
  - match_rules: each of the 6 candidate rules failing on its own; verified; mismatch reason amount;
    the 30-minute boundary (exactly 30 min before = candidate, 30 min 1 s = not).
  - pay-session GET: Session JSON fields and expiresAt per status; notFound; rate limit at the 61st GET.
  - pay-session POST: every result value; SMS-first verified; claim-first then onSmsStored verified;
    change TrxID supersedes; same TrxID twice uses no attempt; attempts to 0 -> noAttemptsLeft;
    alreadyUsed across sessions; operator not offered -> invalidFormat; 21st POST from one IP -> rateLimited;
    CORS headers only for PAY_PAGE_ORIGIN.
  - race: two parallel calls (submit and onSmsStored) on FakeStore produce one match.
  - claim-review: approve, reject, notAllowed, notFound, another merchant's sms -> notFound, audit written.
  - sms-status: verified, mismatch with claim info, rejected by merchant, pending, other merchant's ids left out.
  - claims-expire: wrong secret 401; open session past deadline expired; pending claim past 24 h expired;
    mismatch claim not expired.
  - notifier called once per verification; a throwing notifier leaves the session verified.
- deno check, deno lint and deno fmt --check pass.
- Local smoke test (I run it; Claude Code gives me the commands): with BDPAY_FAKE_STORE=1,
  supabase/scripts/smoke_match.ts creates a session, prints the pay page link
  (pay_page/index.html?t=TOKEN with config pointing at the local function), registers a device,
  sends a bKash SMS, submits the TrxID through pay-session and prints "verified".

Assumptions
- Specs 01 to 08 and 07a are done.
- The 60-minute submit time and 24-hour match time are fixed for v1 (per-merchant settings later).
- FakeStore must imitate the one-transaction rules (submitClaim, recordVerified) so the race test is real.
