# Plan 08 - Device registration and SMS intake

Spec: specs/08_device_and_sms_intake.md (server side of spec 06). Written 2026-10-30.
Read with: CLAUDE.md (incl. the new Backend rules), specs/06_sms_receiver.md, and spec 06's real code
(app/android/.../SmsFilter.kt, ParserRules.kt, app/lib/domain/parser/parse_sms.dart, res/raw/parser_rules.json).

Default rule: until you answer a decision below, the build follows the spec text. Where the spec text would
break spec 06's existing app (D68), CLAUDE.md (D69) or cannot work (D80, D82), I stop and ask instead of guessing.
Proposals marked [CONTRACT] add or change a wire value, a Store method or spec behaviour; they are built only
with your yes.

Reviewed 2026-10-30 against the spec's Scope and CLAUDE.md: logging (section 7), Store-only handlers
(section 8), CLAUDE.md (section 6).

## 1. Files

All new. Nothing outside supabase/ changes; no app file changes (spec 13).

### supabase/functions/_shared/
- http.ts - json(status, body), error(status, code) -> {ok: false, error, message} where message is a fixed
  text per code (never built from input); 405 helper; readBody(req, maxBytes) that stops reading at 256 KB
  (no trust in Content-Length); serveSafely(functionName, handler) - the top-level try/catch used by every
  index.ts (section 7).
- types.ts - DeviceStatus, SmsStatus, RejectReason, VerifyStatus, SimSlot, Operator, AccountType
  (merchant | agent, CLAUDE.md) unions; Device, Wallet, SmsRecord, AuditEntry records (wire names = future CHECK
  values).
- crypto.ts - sha256Hex(bytes | string), base64 decode, derToRaw(der) -> 64 bytes (strict DER parser),
  importP256Spki(base64) -> CryptoKey | null, verifyP256(key, signature, data) (DER or 64-byte raw).
- device_auth.ts - checkDeviceRequest(functionName, headers, rawBody, store, now) -> {device} | {status, code};
  the 5 checks in the spec's order.
- user_auth.ts - UserVerifier interface verify(token) -> {userId} | null; FakeUserVerifier (fixed tokens) for
  tests and BDPAY_FAKE_STORE runs. No real verifier yet (spec 09 D36 / spec 12).
- parser.ts - port of spec 06: normalizeSender, normalizeSmsBody (Bangla digits + Unicode spaces, same list as
  Kotlin/Dart), loadRules(json), ruleForSender, filter (sender -> blocked -> incoming), parseSms,
  amountTextToPoisha (whole-number math). Same function names as the Dart code.
- parser_rules.json - byte-for-byte copy of app/android/app/src/main/res/raw/parser_rules.json.
- wallet_resolve.ts - resolveWallet(wallets, operator, simSlot) -> Wallet | null (pure).
- store.ts - Store interface: exactly the 12 methods in the spec Contract.
- fake_store.ts - FakeStore (in memory; insertSms atomic per merchantId + dedupeHash; never deletes) with seed()
  for tests and local runs; fakeStoreFromEnv() -> FakeStore when BDPAY_FAKE_STORE=1, else null. It is the only
  non-test file that imports parser_rules.json (getParserRules); handlers get rules only through the Store.
- matcher.ts - Matcher interface onSmsStored(sms) -> {verifyStatus, serverMessage}; NoopMatcher.
- register.ts - handle(req, deps) for device-register.
- ingest.ts - handle(req, deps) for sms-ingest (steps a-f per item).
- heartbeat.ts - handle(req, deps) for device-heartbeat.
- deactivate.ts - handle(req, deps) for device-deactivate.
  (deps = {store, users, matcher, now, log}; the clock and logger are injected so tests can fix them.
  Core files import only types, interfaces and pure helpers: no Deno.env, no fetch, no supabase-js, no SQL.)

### supabase/functions/<name>/index.ts (4 files)
- device-register/index.ts, sms-ingest/index.ts, device-heartbeat/index.ts, device-deactivate/index.ts -
  Deno.serve(serveSafely(...)): build deps (FakeStore + FakeUserVerifier if BDPAY_FAKE_STORE=1, else
  503 {ok: false, error: "storeNotReady"}), call handle, return the response. No logic, no Supabase client.

### supabase/functions/tests/
- helpers/device_signer.ts - test helper: P-256 key pair via WebCrypto, SPKI export, Android-style DER
  signing, and signedRequest(functionName, body, opts) that builds the three headers (section 4).
- fixtures/openssl_p256.json - one public SPKI, message and DER signature made once with OpenSSL (an
  independent DER producer, like Android). Test-only key: the private key is made in the session scratchpad
  (outside the project), never copied into the repo and never printed; the fixture holds only public data.
- crypto_test.ts - sha256Hex vectors; derToRaw (padding, short r/s, malformed DER refused); SPKI import ok/bad;
  verify with DER, raw and the OpenSSL fixture.
- device_auth_test.ts - valid DER and raw pass; each error in check order (each of the 3 headers missing
  separately); heartbeat signature on sms-ingest; body changed; 5 min 1 s old / 5 min 1 s ahead; exactly 5 min
  ok; phone clock 10 min fast -> staleTimestamp.
- parser_test.ts - the 4 operator samples, Bangla sample, amount cases, filter results, " BKASH " trusted,
  dedupe hash equal to Kotlin's for the same input.
- parser_rules_copy_test.ts - _shared/parser_rules.json equals the app's copy byte for byte.
- wallet_resolve_test.ts - by simSlot, by single wallet, null (two wallets, none on the slot), inactive ignored.
- fake_store_test.ts - insertSms race (two parallel inserts -> one created), merchant scoping, no delete method.
- register_test.ts, ingest_test.ts, heartbeat_test.ts, deactivate_test.ts - the function contracts and edge
  cases through handle(req, deps) with FakeStore, FakeUserVerifier, a fixed clock and a recording logger.
- logging_test.ts - every handler and serveSafely with a recording logger and a store that throws, invalid
  JSON bodies containing SMS text, bad keys and tokens: no secret or SMS fixture string appears in any log
  line (section 7).
- boundaries_test.ts - reads the source of the core files and index.ts files and fails on SQL keywords,
  supabase-js / postgres imports, fetch(, Deno.env in core files, or a parser_rules.json import outside
  fake_store.ts (section 8). (Needs read permission, D77.)
- serve_test.ts - serveSafely + fakeStoreFromEnv with an injected env reader (importing an index.ts would start
  Deno.serve): without BDPAY_FAKE_STORE -> 503 storeNotReady; non-POST -> 405; a throwing handler -> 500
  internalError with a fixed message.

### supabase/scripts/
- smoke_device.ts - the spec's smoke test (register a fake device, send one signed bKash SMS, print the result);
  see D80 for how it reaches the functions. It prints only the response JSON (result, reason, verifyStatus,
  serverMessage, smsId) - never the key pair, the signature, the fake token or the SMS text.

## 2. Order of work

0. You answer D68-D82 (D68, D69, D77, D80 and D82 at least: they block steps 5, 1, the test command, 11 and 5).
1. types.ts, http.ts (with serveSafely) + serve_test.ts. deno check + lint.
2. crypto.ts + crypto_test.ts; tests/helpers/device_signer.ts + the OpenSSL fixture (I show you the openssl
   command before running it; it writes one file in tests/fixtures). Run tests, check, lint.
3. store.ts, fake_store.ts + fake_store_test.ts (device_auth needs getDevice).
4. device_auth.ts + device_auth_test.ts. Run tests, check, lint.
5. parser_rules.json (copied from the app with a byte copy, after your yes) + parser_rules_copy_test.ts;
   run deno fmt --check on it at once (D82); parser.ts + parser_test.ts. Run tests, check, lint.
6. wallet_resolve.ts + test; matcher.ts.
7. register.ts + device-register/index.ts + register_test.ts.
8. ingest.ts + sms-ingest/index.ts + ingest_test.ts.
9. heartbeat.ts + device-heartbeat/index.ts + heartbeat_test.ts.
10. deactivate.ts + device-deactivate/index.ts + deactivate_test.ts.
11. logging_test.ts + boundaries_test.ts.
12. smoke_device.ts; the commands for you to run (I don't run supabase init, start or serve myself).
13. Full deno test supabase/functions/tests (specs 09-11 tests still green), deno check, deno lint,
    deno fmt --check; searches (console., remote imports, BOM).
deno check and deno lint run after every step; nothing moves on with a failure.

## 3. Acceptance criteria -> test or check

| Criterion | Test or check |
|---|---|
| deno test supabase/functions/tests passes | the full run in step 13 (with the D77 read flag); specs 09-11 tests included |
| device_auth: valid DER signature passes | device_auth_test (WebCrypto key, DER from helper) + crypto_test (OpenSSL fixture) |
| device_auth: valid raw 64-byte signature passes | device_auth_test |
| device_auth: each error code, in the check order | device_auth_test: one case per code, plus combined cases proving order (missing header beats unknown device; revoked beats stale; stale beats bad signature) |
| heartbeat signature rejected on sms-ingest | device_auth_test -> badSignature |
| body changed -> badSignature | device_auth_test (one byte changed after signing) |
| timestamp 5 min 1 s old -> staleTimestamp | device_auth_test (also 5 min 1 s ahead -> stale; exactly 5 min -> ok) |
| register: badUserToken | register_test (missing and unknown token) |
| register: noMerchant | register_test (valid user without a merchant) |
| register: new device | register_test: 200 shape, device active, audit device.register |
| register: same installId rotates key, keeps deviceId | register_test: new key works for signing, old key -> badSignature, same deviceId |
| register: 4th device -> deviceLimit | register_test (3 active + new installId -> 409; a revoked one does not count) |
| register: bad key -> badPublicKey | register_test (garbage, P-384 key, RSA key) |
| register: revoked then re-register -> active | register_test (deactivate, register same installId, signed request works) |
| ingest: 4 operator samples accepted, right trxId and amountPoisha | ingest_test with the spec 06 sample texts |
| ingest: hashMismatch | ingest_test (not stored, smsId null, Bangla message) |
| ingest: duplicate on resend, same smsId | ingest_test (whole batch twice; store count unchanged) |
| ingest: two equal items in one batch | ingest_test (accepted, then duplicate with the same smsId) |
| ingest: senderNotTrusted, blocked (body null), notIncoming, parseFailed, tooOld | ingest_test, one per reason, with stored status/reason/body checked |
| ingest: future receivedAt clamped | ingest_test (receivedAt +1 h -> stored as server time, accepted) |
| ingest: wallet by simSlot, by single wallet, null | wallet_resolve_test + ingest_test (walletId on the stored row) |
| ingest: 51 items -> 400 | ingest_test (also 0 items -> 400) |
| ingest: body over 256 KB -> 413 | ingest_test (256 KB + 1 byte, no Content-Length) |
| ingest: one bad item does not fail the others | ingest_test (batch of accepted + hashMismatch + blocked + accepted) |
| heartbeat updates lastSeenAt | heartbeat_test (fixed clock, appVersion too) |
| deactivate then ingest -> deviceRevoked | deactivate_test (also the replayed old request within 5 min -> 403) |
| parser_rules.json equals the app copy byte for byte | parser_rules_copy_test (D77 for how it reads files) |
| Tests use WebCrypto P-256, SPKI export, DER signing | tests/helpers/device_signer.ts used by every signed test |
| deno check / lint / fmt --check pass | the three commands on supabase/functions (D82 for the rules copy) |
| Local smoke test | smoke_device.ts; you run it with the commands I give you (D80). I report it as "not run by me" |

Other spec rules

| Rule | Test or check |
|---|---|
| Methods other than POST -> 405 | serve_test + each handler test |
| Without BDPAY_FAKE_STORE -> 503 storeNotReady | serve_test |
| Every device write is audited | register_test, deactivate_test (heartbeat per D75); audit data checked to hold no key, token or SMS text |
| Never log body, sender, TrxID, payer, keys, tokens | logging_test (all handlers, error paths, throwing store, invalid JSON with SMS text) + search: console. only inside the injected logger |
| Log only function name, request id, result code, merchantId | logging_test: every log line has exactly these keys |
| Handlers use only the Store interface | boundaries_test + the same search by hand in step 13 |
| Error messages never echo input | logging_test / handler tests: every error body's message is the fixed text for its code |
| Phone clock 10 min fast -> staleTimestamp | device_auth_test |
| OTP from a buggy app -> body null | ingest_test (blocked case) |
| Blocked SMS stored with body null | ingest_test |
| Untrusted sender never matched | ingest_test: matcher spy not called for rejected items |
| parser follows spec 06 | parser_test uses the same samples and expected values as app/test/domain/parser/parse_sms_test.dart |

## 4. Android-style DER signatures in tests

Android's Keystore (Signature "SHA256withECDSA") returns an ASN.1 DER signature:
`30 len 02 lenR R 02 lenS S`, where R and S are big-endian, minimal length, with a 0x00 byte in front when the
top bit is set. WebCrypto's ECDSA sign returns raw r||s (2 x 32 bytes). The test helper turns raw into DER:

1. generateKey({name: "ECDSA", namedCurve: "P-256"}, true, ["sign", "verify"]).
2. exportKey("spki", publicKey) -> base64. This is the same X.509 SubjectPublicKeyInfo DER that Android's
   publicKey.encoded gives, so device-register gets exactly what the phone will send.
3. sign({name: "ECDSA", hash: "SHA-256"}, privateKey, utf8(functionName + "\n" + ts + "\n" + sha256Hex(body)))
   -> 64 raw bytes.
4. rawToDer: for r and s, strip leading 0x00 bytes (keep one byte), add 0x00 if the top bit is set, wrap as
   INTEGER (0x02, len); wrap both as SEQUENCE (0x30, len; always under 128 bytes for P-256).
5. base64 -> X-Signature.

Cases the DER tests force:
- r or s with the top bit set (needs the 0x00 pad) - found by signing in a loop until it happens (about 1 in 2).
- r or s shorter than 32 bytes (a leading zero byte) - signing in a loop until it happens (about 1 in 128 per
  signature; capped at 5000 tries, deterministic enough in practice; fails loudly if not found).
- An independent producer: one fixed signature made with OpenSSL (`openssl dgst -sha256 -sign`, which outputs
  DER like Java), stored in tests/fixtures/openssl_p256.json with its public key and message. This catches a
  helper bug that matches a parser bug.
- Malformed DER refused (badSignature, never a crash): wrong tag, wrong lengths, trailing bytes, negative
  integer, non-minimal padding, r or s longer than 32 bytes, r or s = 0.
- Raw 64 bytes accepted. A 64-byte value is DER only if it parses as a full DER sequence; otherwise raw (D78).

## 5. Unclear or wrong in the spec

Blocking
- D68. **The dedupe hash does not match spec 06's real app.** Spec 08 step a: SHA-256 of sender + "|" + body.
  The app (SmsFilter.dedupeHash) hashes the trimmed, lower-case sender: SHA-256(lower(trim(sender)) + "|" + body),
  hex. Built as written, every SMS from "bKash" or "NAGAD" would be rejected as hashMismatch. Proposal: the server
  uses the app's formula (normalizeSender, body exactly as received, UTF-8, lower-case hex); parser_test checks a
  known input against the hash value Kotlin produces. Needs your yes (it changes the spec's wording).
- D69. **SmsStatus differs from CLAUDE.md.** Spec 08: unmatched | matched | rejected. CLAUDE.md fixed values:
  received, unmatched, matched, rejected (and spec 09's match_rules.ts already has all four). Proposal: types.ts
  uses CLAUDE.md's four values (spec 08 never writes "received"). Otherwise CLAUDE.md must change.

Contract gaps
- D70. **Rules version.** The rules file is an array with a version per operator; getParserRules returns one
  {version, rules}. Proposal: version = the highest rule version; parserVersion on SmsRecord = that number.
- D71. **Nullable fields for rejected rows.** SmsRecord lists trxId, amountPoisha, payerNumber without "(or null)",
  but rejected rows have none. Proposal: trxId, amountPoisha, payerNumber are null on rejected rows (and payer may be
  null on accepted rows, since spec 06's payer is optional).
- D72. **Duplicate result's verifyStatus.** "Return that row's current result": spec 08 has no claim data, so
  verifyStatus comes from the SMS status: unmatched -> pending, matched -> verified, rejected -> rejected (with its
  reason and Bangla message). "mismatch" cannot be known until spec 09.
- D73. [CONTRACT] **Privacy of rejected SMS bodies.** Spec 06 says the phone never keeps personal SMS or outgoing-payment
  SMS, but spec 08 stores the body for senderNotTrusted and notIncoming (only blocked gets null). A tampered app
  could upload personal SMS and the server would keep them. Proposal: body null for senderNotTrusted, notIncoming
  and tooOld too; keep the body only for parseFailed (needed to re-parse) and accepted rows. Needs your yes.
- D74. **tooOld stored or not?** hashMismatch says "not stored"; tooOld doesn't say. Proposal: stored as rejected
  tooOld (so a resend returns duplicate instead of re-checking), body null per D73.
- D75. **Heartbeat and audit.** "Every successful write that changes a device writes an audit entry", and the
  heartbeat updates lastSeenAt every 5 minutes. Proposal: heartbeat writes no audit (it is a status touch, not a
  change); only register and deactivate audit. Otherwise the audit log gets 288 rows per phone per day.
- D76. [CONTRACT] **Batch shape vs one bad item.** "Bad shape 400" vs "one bad item never fails the whole batch". A single
  item with a wrong type (receivedAt not a date) would make the app's queue resend that batch forever. Proposal:
  400 only when the body itself is wrong (not JSON, items missing or not an array, 0 or > 50 items, an item not
  an object). An item whose fields are wrong is rejected on its own with a new RejectReason badItem
  ("ডেটা ঠিক নেই") and is not stored. Needs your yes (new wire value); without it, any bad item -> 400 for the
  batch, as written.
- D77. **Reading files in tests.** The byte-for-byte test must read two files; `deno test` without flags has no
  read permission, so "deno test supabase/functions/tests" would fail. Options: A run tests as
  `deno test --allow-read supabase/functions/tests` (I give you that as the test command); B add
  supabase/functions/deno.json with test read permission for just those two paths (a new config file).
  Recommended A. Note: FakeStore reads _shared/parser_rules.json with a JSON import, which needs no permission.
- D78. **Raw vs DER detection.** "Also accept 64 raw bytes": a DER signature of exactly 64 bytes is possible but
  very rare. Proposal: try DER first (strict parse of the whole input); if that fails and the length is 64, raw.
- D79. **Register details not given.** deviceName length 1-30 counted in characters (code points) after trim;
  installId must be a UUID; missing/wrong fields -> 400 badRequest; serverTime = ISO 8601 UTC string. The device
  limit also applies when a revoked device re-registers (otherwise re-registering a revoked 4th phone gives 4
  active). Audit data holds name and versions, never the key.
- D80. [CONTRACT] **The smoke test can't work through `supabase functions serve` as written.**
  (a) Each function runs in its own worker with its own in-memory FakeStore, so a device registered through
  device-register is unknown to sms-ingest (unknownDevice).
  (b) `supabase functions serve` needs `supabase init` (config.toml - none exists) and the local stack running
  (Docker), so "no database is needed" isn't quite true.
  (c) The gateway checks a Supabase JWT by default; signed device requests have none -> need --no-verify-jwt.
  (d) BDPAY_FAKE_STORE=1 would go in an env file, and CLAUDE.md forbids me to read or change .env files.
  Proposal: smoke_device.ts runs the four handlers in one Deno process with one FakeStore (like plan 10's
  smoke_shopify.ts), so you run `deno run --allow-read supabase/scripts/smoke_device.ts`. A served version waits
  for spec 12 (real Store). Needs your yes.
- D81. **Replay inside the 5-minute window.** There is no nonce, so a captured signed request can be replayed for
  5 minutes. sms-ingest is idempotent and heartbeat harmless, so the risk is small (and TLS protects transit).
  Noted only; a nonce store would be a new Store method (outside Scope, not planned).
- D82. **deno fmt --check vs the byte-for-byte rules copy.** deno fmt also checks .json files. If it wants to
  reformat the app's parser_rules.json (long lines, inline arrays), "fmt --check passes" and "byte for byte equal"
  cannot both hold, and the copy must not be reformatted. Proposal: if fmt --check flags it, exclude only that one
  file from fmt (`deno fmt --check --ignore=supabase/functions/_shared/parser_rules.json`, or a fmt exclude in a
  deno.json per D77 B). I check this first in step 5 and ask before choosing.
- D83. **Fixed values not in CLAUDE.md.** RejectReason, VerifyStatus and SimSlot are new wire values; CLAUDE.md's
  fixed-values list doesn't have them. VerifyStatus (pending, verified, mismatch, rejected) also differs from claim
  status (adds no "expired"). Proposal: use the spec's lists exactly; add them to CLAUDE.md's list when spec 12 writes
  the CHECKs. Wallet.accountType uses CLAUDE.md's merchant | agent.

Notes (no decision needed)
- Check order puts unknownDevice before staleTimestamp, so an unsigned guess can learn whether a device id
  exists. Device ids are random UUIDs, so this is fine.
- Request order: 405 -> read body with the 256 KB cap (413) -> signature check over the raw bytes -> JSON shape
  (400). The size cap comes before the signature so a huge body is never hashed.
- Wallet resolution with simSlot "unknown" never matches by slot; it falls through to "the only active wallet of
  that operator".
- Case-insensitive matching: Kotlin folds only ASCII, JavaScript's "i" flag also folds some non-ASCII letters.
  The rules are ASCII + Bangla (no case), so results are the same; parser_test runs every spec 06 sample.
- "request id" for logs: the platform's request id header if present, else crypto.randomUUID().
- receivedAt exactly 7 days old is accepted; older is tooOld (after the future clamp).
- The heartbeat's smsPermission, batteryOptimizationOff, monitoring and queueCount are checked for type but
  not saved in spec 08 (spec 11 adds saving three of them).
- Not in this step (Scope check): no SQL, migration, table, RLS or real Store (spec 12); no matching beyond
  NoopMatcher (spec 09); no Shopify or alerts code; no Flutter, Kotlin or app file change - the app's
  parser_rules.json is only read; no supabase init / config.toml; no real UserVerifier (spec 09 D36 / spec 12).
- Specs 09-11 were planned against an imagined spec 08; after this is built, their plans need a pass
  (Store names like getMerchantIdForUser vs findMerchantForUser, appendAudit vs writeAudit, matcher wiring).

## 6. Review against CLAUDE.md

| Rule | How the plan keeps it |
|---|---|
| Server decides paid; never trust the device's parsed values | the server re-parses from raw sender + body with its own rules; the app's parse is never read |
| Sender whitelist on the server | parser.filter step 1 with the server rules |
| Each phone has its own P-256 key; server stores only the public key | Device.publicKeySpki only; no private key anywhere on the server |
| Signed over function name, timestamp, body hash; 5-minute window | device_auth.ts, tested both directions |
| Edge Function logic talks only to Store; no SQL / Supabase calls in handlers | section 8 + boundaries_test |
| merchant_id on everything, a merchant sees only its own rows | every record has merchantId; dedupe and wallet lookups are per merchant; FakeStore test |
| Money as whole poisha, no float | amountTextToPoisha with integer math; test cases from spec 06 |
| Times UTC ISO | receivedAt / serverReceivedAt / lastSeenAt as ISO UTC |
| Wallet and phone numbers are strings; TrxID trimmed upper case | types + parser |
| Fixed values | D69 |
| SMS text untrusted, never logged | section 7 + logging_test |
| SMS records never deleted | Store and FakeStore have no delete |
| No new packages | Web Crypto and Deno only; no imports from the network |
| Never read .env / keys / device secrets | test keys are generated in memory; the OpenSSL private key lives only in the scratchpad and is never printed or read back into the repo; no env file is written (D80(d)) |
| Ask before commands that change files outside the project or installed software | openssl fixture command and the rules-file copy shown first; no installs; supabase init / start / serve are yours to run |
| UTF-8 without BOM | search in step 13 (the app's rules file has no BOM, LF endings - checked) |
| Fixed values from CLAUDE.md | D69 (SmsStatus), AccountType merchant/agent, Operator; D83 for the new lists |
| Do only what the current spec says | Scope check in section 5; [CONTRACT] items only with your yes |

## 7. Logging - where secrets could leak, and the fix

| Risk | Fix |
|---|---|
| Uncaught exception: Deno.serve's default handler logs the error message and stack | serveSafely wraps every handler: catches everything, logs {fn, requestId, code: "internalError"}, returns 500 with a fixed message |
| JSON.parse errors quote part of the body ("Unexpected token ... \"You have r...\"") | parse errors become 400 badRequest; the error object is dropped, never logged or returned |
| Error response messages built from input | error(status, code) takes no free text; message = fixed text per code |
| Thrown errors with values in the message (RangeError etc.) | own code throws only fixed messages; catch blocks never log err.message or err.stack |
| WebCrypto import/verify errors | caught; mapped to badPublicKey / badSignature; error object dropped |
| Logging deviceId, headers, Authorization, X-Signature, the SPKI | the logger takes only {fn, requestId, code, merchantId}; anything else is a type error |
| Audit data | register: name, appVersion, androidVersion, installId; deactivate: nothing extra; never the key, token, signature or SMS fields |
| FakeStore / FakeUserVerifier debug output | none; no console calls outside the logger |
| Smoke script output | prints only the response JSON (no key, signature, token, SMS text) |
| Test output | fixture data only (fake SMS, test keys); no real data in the repo |

## 8. Store-only handlers - checked per file

| File | Talks to |
|---|---|
| register.ts | Store (findMerchantForUser, findDeviceByInstall, countActiveDevices, createDevice, updateDevice, getParserRules, writeAudit), UserVerifier, crypto.ts |
| ingest.ts | Store (getDevice via device_auth, getParserRules, findSmsByDedupe, listActiveWallets, insertSms), parser.ts, wallet_resolve.ts, Matcher |
| heartbeat.ts | Store (getDevice via device_auth, updateDevice, getParserRules) |
| deactivate.ts | Store (getDevice via device_auth, updateDevice, writeAudit) |
| device_auth.ts | Store.getDevice, crypto.ts |
| index.ts (x4) | serveSafely, fakeStoreFromEnv, FakeUserVerifier, NoopMatcher; reads BDPAY_FAKE_STORE only |
| user_auth.ts | interface + FakeUserVerifier only; the real one (it will call Supabase Auth) is not in this step and will live outside the handlers |

No handler creates a Supabase client, runs SQL, calls fetch or reads parser_rules.json directly. boundaries_test
fails the build if one does.


## 9. Build results (2026-10-30)

Answered: D68 app's hash formula; D69 CLAUDE.md's 4 SmsStatus values; D77 `deno test --allow-read`; D80 in-process
smoke script. D82 resolved itself: deno fmt --check accepts the byte copy as it is (no exclusion needed).

Unanswered, built per the spec text (or the plan's proposal where the spec is silent):
- D73 body kept for senderNotTrusted / notIncoming / parseFailed / tooOld; null only for blocked (spec).
- D74 tooOld stored as rejected (spec silent -> proposal). D71 trxId/amount/payer null on every rejected row.
- D75 heartbeat writes an audit entry "device.heartbeat" (spec: every device write is audited).
- D76 any bad item -> 400 for the batch (spec).
- D79 re-registering a revoked installId reactivates it without the 3-device check (spec: "set active").
- Register sets lastSeenAt to the register time (Device.lastSeenAt is not nullable in the spec).

Changed from the plan:
- The OpenSSL fixture was dropped: Windows OpenSSL can't read a key through a pipe, and writing the private key to
  a file outside the project needs your yes. crypto_test uses node:crypto (built into Deno, an independent DER
  encoder like Java's) at test time instead. No fixture file, no key on disk.
- One DER test was flaky (wrong assertion about a "short" r); fixed, 20/20 runs green.
- Store / UserVerifier / Matcher interfaces were written in step 1 because http.ts' Deps type uses them.
