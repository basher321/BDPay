# 08 Device registration and SMS intake (Edge Functions)

Purpose
Let a merchant's phone register itself securely, then send the SMS it caught to the server,
where they are checked again, parsed again and stored once. This is the server side of
spec 06. Matching to orders comes in spec 09.

Scope
- Four Edge Functions (TypeScript, Deno) in supabase/functions/:
  device-register, sms-ingest, device-heartbeat, device-deactivate.
- Shared code in supabase/functions/_shared/:
  http.ts (JSON responses and errors), types.ts (enums and records), crypto.ts (SHA-256,
  ECDSA verify, DER to raw signature), device_auth.ts (signed-request check), user_auth.ts
  (UserVerifier interface for Supabase user tokens), parser.ts (TypeScript port of the spec 06
  filter and parser), parser_rules.json, wallet_resolve.ts, store.ts (Store interface),
  fake_store.ts (in-memory Store for tests and local runs), matcher.ts (Matcher interface and
  NoopMatcher), and one core file per function (register.ts, ingest.ts, heartbeat.ts, deactivate.ts).
- Each function's index.ts only reads the request, calls its core file and writes the response.
  Each core file exports handle(req, deps) so tests can pass a fake Store, a fake UserVerifier and a fixed clock.
- Deno tests in supabase/functions/tests/.
- Local runs: when the environment variable BDPAY_FAKE_STORE=1 is set, index.ts uses FakeStore.
  Without it, index.ts returns 503 {error: "storeNotReady"} until spec 12.
- Not in scope: database tables and SQL (spec 12), matching (spec 09), Shopify (spec 10),
  alerts (spec 11), changes to the Flutter app (spec 13).

Contract
Record types (types.ts), wire names match future SQL CHECK values:
- DeviceStatus: active | revoked.
- SmsStatus: unmatched | matched | rejected.
- RejectReason: senderNotTrusted | blocked | notIncoming | parseFailed | hashMismatch | tooOld.
- VerifyStatus: pending | verified | mismatch | rejected.
- Device: id, merchantId, name, installId, publicKeySpki (base64), status, appVersion,
  androidVersion, lastSeenAt, createdAt.
- Wallet: id, merchantId, operator, walletNumber, accountType, simSlot (sim1|sim2|unknown), isActive.
- SmsRecord: id, merchantId, deviceId, walletId (or null), sender, body (or null when blocked),
  receivedAt, serverReceivedAt, simSlot, dedupeHash, operator (or null), trxId, amountPoisha,
  payerNumber, status, rejectReason (or null), parserVersion.

Store interface (store.ts). Spec 12 builds the tables from this list:
  findMerchantForUser(userId) -> {merchantId} | null   (user must be the owner)
  countActiveDevices(merchantId) -> number
  findDeviceByInstall(merchantId, installId) -> Device | null
  createDevice(fields) -> Device
  updateDevice(deviceId, fields) -> Device
  getDevice(deviceId) -> Device | null
  getParserRules() -> {version, rules}
  listActiveWallets(merchantId) -> Wallet[]
  findSmsByDedupe(merchantId, dedupeHash) -> SmsRecord | null
  insertSms(record) -> {sms: SmsRecord, created: boolean}
      (if the same merchantId + dedupeHash exists, return the existing row with created false;
       must be safe when two requests race)
  writeAudit({merchantId, actorType: user|device|system, actorId, action, entity, entityId, data})

Matcher interface (matcher.ts):
  onSmsStored(sms) -> {verifyStatus, serverMessage}
  NoopMatcher returns {verifyStatus: "pending", serverMessage: null}. Spec 09 replaces it.

Signed device requests (device_auth.ts):
- Headers: X-Device-Id, X-Timestamp (milliseconds since epoch, UTC), X-Signature (base64).
- Signed text: functionName + "\n" + timestamp + "\n" + hex SHA-256 of the exact raw body bytes.
  functionName is the plain name (for example "sms-ingest"), not the URL path.
- Signature: ECDSA P-256 with SHA-256. Android sends DER format; convert DER to raw (r||s, 64 bytes)
  before WebCrypto verify. Also accept a signature that is already 64 raw bytes.
- Check order and errors (HTTP status, error code):
  missing header 401 missingSignature; device not found 401 unknownDevice;
  device revoked 403 deviceRevoked; timestamp more than 5 minutes from server time 401 staleTimestamp;
  signature wrong 401 badSignature.

Function contracts (all JSON; errors are {ok: false, error, message}):

1. POST device-register (Supabase user token in Authorization: Bearer)
   Body: {installId (UUID made once per app install), deviceName (1-30), publicKeySpki (base64),
          appVersion, androidVersion}
   - Token invalid -> 401 badUserToken. User owns no merchant -> 403 noMerchant.
   - Same merchant + installId exists -> update its key, name and versions, set active, return it
     (key rotation and re-login).
   - New device while the merchant already has 3 active devices -> 409 deviceLimit.
   - publicKeySpki that WebCrypto cannot import as P-256 -> 400 badPublicKey.
   - Success 200: {ok: true, deviceId, merchantId, serverTime, rulesVersion}. Audit "device.register".

2. POST sms-ingest (signed device request)
   Body: {items: [{localId, sender, body, receivedAt (ISO), simSlot, dedupeHash}]}, 1 to 50 items,
   raw body at most 256 KB (else 413 tooLarge; bad shape 400 badRequest).
   For each item, in order:
   a. Recompute SHA-256 of sender + "|" + body. Different from dedupeHash -> rejected hashMismatch
      (not stored).
   b. If findSmsByDedupe finds it -> return that row's current result (duplicate, idempotent).
   c. Run the spec 06 filter and parser with the SERVER rules (getParserRules).
      Ignore monitoring and operator settings (those are phone-side only).
      senderNotTrusted / blocked / notIncoming -> store with status rejected and that reason;
      for blocked, store body as null (never keep OTP text).
      Parse fails -> store as rejected parseFailed (body kept so it can be parsed again later).
   d. receivedAt later than server time -> use server time. receivedAt older than 7 days ->
      rejected tooOld.
   e. Resolve the wallet (wallet_resolve.ts): an active wallet with the same operator and simSlot;
      else the only active wallet of that operator; else null.
   f. Store with status unmatched, then call matcher.onSmsStored.
   Response 200: {ok: true, results: [{localId, smsId (or null), result: accepted | duplicate | rejected,
     reason (or null), verifyStatus, serverMessage}]} in the same order as items.
   Rejected items get verifyStatus "rejected" and a Bangla serverMessage:
     senderNotTrusted "প্রেরক বিশ্বস্ত নয়", blocked "OTP/অফার — রাখা হয়নি",
     notIncoming "টাকা গ্রহণের এসএমএস নয়", parseFailed "ফরম্যাট বোঝা যায়নি",
     hashMismatch "ডেটা মেলেনি — আবার পাঠান", tooOld "৭ দিনের বেশি পুরনো".
   One bad item never fails the whole batch.

3. POST device-heartbeat (signed)
   Body: {appVersion, smsPermission, batteryOptimizationOff, monitoring, queueCount}
   - Updates lastSeenAt and appVersion. Response 200: {ok: true, serverTime, rulesVersion}.

4. POST device-deactivate (signed)
   Body: {} -> sets status revoked. Audit "device.deactivate". Response 200 {ok: true}.
   Later requests from that device get 403 deviceRevoked. A new device-register with the same
   installId makes it active again.

Functional rules
- parser_rules.json in _shared is a copy of app/android/app/src/main/res/raw/parser_rules.json.
  A test fails if the two files differ, so they never drift apart.
- parser.ts follows spec 06 exactly: Bangla digits to English first, case-insensitive patterns,
  amounts in poisha with whole-number math only.
- Every successful write that changes a device writes an audit entry.
- Methods other than POST -> 405 methodNotAllowed.

Edge cases
- The same batch sent twice (network drop after the server saved it) -> second time every item is duplicate
  with the same smsId and status. Nothing is stored twice.
- Two items in one batch with the same dedupeHash -> first accepted, second duplicate.
- An item from an untrusted sender sent by a buggy or tampered app -> stored as rejected, never matched.
- An OTP sent by a buggy app -> stored with body null.
- Clock on the phone 10 minutes fast -> X-Timestamp fails with staleTimestamp (the app will show the
  server time difference in spec 13). receivedAt in the future is clamped, not rejected.
- Signature made over a different function name (for example a heartbeat signature replayed to
  sms-ingest) -> badSignature.
- Body changed after signing -> badSignature.
- A revoked device's old signed request replayed within 5 minutes -> deviceRevoked.

Non-functional rules
- Never log SMS body, sender, TrxID, payer number, keys or tokens. Log only function name,
  request id, result code and merchantId.
- Handlers have no SQL and no Supabase client calls; only the Store interface.
- deno check, deno lint and deno fmt --check pass on supabase/functions.

Acceptance criteria
- deno test supabase/functions/tests passes, covering:
  - device_auth: a valid signature (DER and raw) passes; each error code in the check order;
    signature for "device-heartbeat" rejected on "sms-ingest"; body changed -> badSignature;
    timestamp 5 min 1 s old -> staleTimestamp.
  - device-register: badUserToken, noMerchant, new device, same installId rotates the key and keeps
    the deviceId, 4th device -> deviceLimit, bad key -> badPublicKey, revoked then re-register -> active.
  - sms-ingest: each of the 4 operator samples accepted with the right trxId and amountPoisha;
    hashMismatch; duplicate on resend with the same smsId; two equal items in one batch;
    senderNotTrusted, blocked (body null), notIncoming, parseFailed, tooOld; future receivedAt clamped;
    wallet resolution by simSlot, by single wallet, and null; 51 items -> 400; body over 256 KB -> 413;
    one bad item does not fail the others.
  - heartbeat updates lastSeenAt; deactivate then ingest -> deviceRevoked.
  - parser_rules.json in _shared equals the app's copy byte for byte.
  - Tests use WebCrypto to make a P-256 key pair, export the public key as SPKI, and sign
    like Android does (DER), so the real format is tested.
- deno check, deno lint and deno fmt --check pass.
- Local smoke test (I run it; Claude Code gives me the commands): supabase functions serve with
  BDPAY_FAKE_STORE=1, then a small Deno script supabase/scripts/smoke_device.ts registers a fake device
  (with a fake user token that FakeStore accepts), sends one signed bKash SMS and prints the result.

Assumptions
- Specs 01 to 07 are done.
- The Supabase CLI and Deno are installed. No database is needed for this spec.
- The real Store (Postgres) arrives in spec 12; the Flutter app starts calling these functions in spec 13.
