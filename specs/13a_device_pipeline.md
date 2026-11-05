# 13a Phone to server pipeline

Purpose
Connect the phone to the server: give each phone its own key, register it, send every caught SMS to the
server in the background (even when the app is closed), keep the server informed that the phone is alive,
show live verification results, let the merchant approve or reject mismatches on the server, and update
the SMS rules from the server. After this spec the whole system works end to end on a local setup.

Scope
Android (Kotlin, app/android/app/src/main/kotlin/com/bdpay/verifier/):
- DeviceKeys: ECDSA P-256 key in the Android Keystore (alias "bdpay_device_key_v1", sign only, SHA-256).
  publicKeySpki() returns the X.509 SPKI bytes as base64. sign(text) returns the DER signature as base64.
  installId: a UUID created once and kept in SharedPreferences.
- DeviceConfig (SharedPreferences): deviceId, functionsUrl, clockOffsetMs, revoked flag, rulesVersion.
- ServerClient: signed POST requests (spec 08 headers and signed text) using HttpURLConnection
  (no OkHttp), 15-second timeout. Timestamp = device time + clockOffsetMs. Every response's serverTime
  (or the HTTP Date header) updates clockOffsetMs.
- SmsUploadWorker (WorkManager): sends queued and failed rows to sms-ingest.
- StatusRefreshWorker (WorkManager): asks sms-status for rows that are still pending or mismatch.
- HeartbeatWorker (WorkManager): sends device-heartbeat every 5 minutes (a one-time job that schedules
  the next one), and fetches new rules when rulesVersion from the server is higher.
- RulesStore: keeps the downloaded rules JSON in app files; SmsFilter uses it when its version is higher
  than the bundled parser_rules.json, otherwise the bundled file.
- SmsStore upgrade (database version 2, add columns only, never drop): server_sms_id TEXT, claim_json TEXT,
  last_status_check_ms INTEGER.
- SmsBridge additions (rule 9).
- Gradle: androidx.work:work-runtime-ktx with an exact pinned version (ask me first). No other library.
Flutter:
- DeviceRegistration in lib/data/device/: registers the phone after sign-in and on every app start.
- NativeSmsUploader replaces MockSmsUploader in the app (the mock stays for tests).
- TransactionRepository.review() calls claim-review through FunctionsGateway.
- DeviceHealthRepository.pingServer() runs a heartbeat now.
- UI pieces in the existing style: device-limit screen, "phone disconnected" banner, rules version line in
  the developer lab.
Backend:
- New Edge Function parser-rules (signed device request): POST {} -> {ok: true, version, rules}.
- supabase/scripts/make_session.ts (local test helper only): creates a payment session for a merchant email,
  amount and order ref, and prints the pay page URL.
Not in scope: deploying, a foreground service, push notifications, iOS, new tables or columns on the server.

Contract
Registration (DeviceRegistration):
- When AuthState is signedIn: get installId and publicKeySpki through the channel, call device-register with
  the user token, deviceName from settings, appVersion and Android version. On success, save deviceId and
  functionsUrl in DeviceConfig (setDeviceConfig), clear the revoked flag, set AuthState.deviceId,
  apply serverTime to the clock offset.
- Runs again on every app start while signed in, and when the device name changes (same installId, so the
  server keeps the same deviceId).
- deviceLimit -> a full screen "এই অ্যাকাউন্টে ৩টি ফোন যুক্ত আছে" / "অন্য একটি ফোন থেকে লগ আউট করে আবার চেষ্টা করুন"
  with "আবার চেষ্টা করুন" and "লগ আউট". offline -> retry when the internet returns; the app still works offline.

SmsUploadWorker:
- Unique work name "sms-upload", policy KEEP while running, then the next request runs after it (no two
  uploads at once). Network required. Exponential backoff starting at 30 seconds.
- Enqueued as expedited (falls back to normal when out of quota) by: the SMS receiver after storing a row
  (only when autoSend is on), uploadNow() from Dart, and when the internet returns (autoSend on).
- Takes up to 50 rows with sync_status queued or failed, oldest first; sets them sending; sends one batch;
  applies each result:
  accepted or duplicate -> sent, server_sms_id, verify_status and server_message from the result;
  rejected -> sent, verify_status rejected, server_message from the result (no retry);
  hashMismatch -> failed, retry_count + 1.
  Then repeats until no rows are left or a request fails.
- HTTP failures: network error, timeout, 5xx, 429 -> rows back to failed, retry_count + 1, WorkManager retry.
  401 staleTimestamp -> update the clock offset from the response and retry once at once.
  401 unknownDevice or 403 deviceRevoked -> rows back to queued (not failed), set the revoked flag, stop
  (no retry until registration succeeds again).
- The device needs no user login token for this; it works while the app is closed.
- A device with no deviceId yet (never registered) does nothing; rows wait as queued.

StatusRefreshWorker:
- Runs after every successful upload, after every heartbeat, and through refreshNow() from Dart.
- Rows with server_sms_id, verify_status pending or mismatch, received in the last 48 hours -> sms-status in
  batches of 100 -> update verify_status, server_message, claim_json ({claimId, orderRef,
  expectedAmountPoisha} or null), last_status_check_ms. Fires the "inbox" event.
- While the app is in front, Dart calls refreshNow() every 30 seconds.

HeartbeatWorker:
- Sends appVersion, smsPermission, batteryOptimizationOff, monitoring and queueCount (queued + sending + failed).
- Success -> lastServerContactAt; if response rulesVersion > DeviceConfig.rulesVersion -> call parser-rules,
  save with RulesStore, update rulesVersion, and give Dart the new rules (event "rules").
- Schedules the next heartbeat 5 minutes later whatever the result. Started at app start and after reboot
  (WorkManager keeps scheduled work across reboots).

Review (Dart):
- review(id, decision, note): the row's server_sms_id is null -> notAllowed. Offline -> offline.
  claim-review result done -> refreshNow() and return done; notAllowed -> notAllowed; notFound -> notAllowed.

Logout (spec 05 flow, before Supabase sign out):
- Queue must be empty (spec 05 rule). Then call deactivateDevice() (signed device-deactivate).
  Success -> clear deviceId in DeviceConfig, then sign out. No internet -> block with toast
  "লগ আউট করতে ইন্টারনেট দরকার". The key and installId stay (a later login re-registers the same phone).

SmsBridge additions:
  getInstallId() -> String; getDevicePublicKey() -> String (base64 SPKI);
  setDeviceConfig(deviceId, functionsUrl) -> void; clearDeviceConfig() -> void;
  uploadNow() -> void; refreshNow() -> void; heartbeatNow() -> bool; deactivateDevice() -> bool;
  getPipelineState() -> {deviceId, revoked, clockOffsetMs, rulesVersion, lastServerContactMs}.
  Event "pipeline" when any of those change.
  listInbox rows also return server_sms_id and claim_json (mapped to SmsTransaction.claim).

Functional rules
1. Signing: the private key never leaves the Keystore and is never exported, logged or sent.
2. revoked flag set -> হোম shows a red banner "এই ফোন BDPay থেকে বিচ্ছিন্ন — আবার লগইন করুন" with button
   "লগ আউট" (skips the deactivate call, since the server already revoked it), and the health card counts it
   as a problem. New SMS are still caught and kept as queued.
3. The online pill, the server row and "শেষ সংযোগ" use lastServerContactMs from the pipeline state.
4. The developer lab shows "নিয়ম সংস্করণ: {rulesVersion}" (bundled or downloaded).
5. parser-rules: same signed check as spec 08; returns the active rules from the database.
6. make_session.ts refuses to run unless SUPABASE_URL is local.

Edge cases
- The phone clock is 10 minutes fast -> the first upload may get staleTimestamp, the offset is fixed, and
  the retry succeeds.
- No internet for 2 days with 30 SMS -> all 30 uploaded in one batch when online (under 50).
- 70 queued SMS -> two batches.
- App force-stopped -> WorkManager jobs stop until the app is opened (Android rule; the spec 06 warning covers it).
- An upload succeeds on the server but the response is lost -> rows become failed, the retry returns
  duplicate with the same server_sms_id (no double counting).
- Server revoked the device while offline SMS were queued -> they stay queued and upload after the next login.
- A downloaded rules file that fails to parse -> keep using the previous rules and report nothing to the user.
- Two quick uploadNow() calls -> one running upload, the second request runs after it.

Non-functional rules
- Never log SMS content, TrxIDs, payer numbers, keys, signatures or tokens (Kotlin and Dart).
- Pure Kotlin logic (body builder, signed-text builder, result applier, clock offset, batch selection) has
  JVM unit tests; Keystore and WorkManager code stays thin.
- flutter analyze reports zero issues; deno check and deno lint pass.

Acceptance criteria
- flutter analyze: no issues. flutter test passes (earlier tests still pass).
- Kotlin unit tests (./gradlew :app:testDebugUnitTest) cover: the signed text is exactly
  functionName + "\n" + timestamp + "\n" + hex SHA-256 of the body; batch selection (oldest first, max 50,
  only queued/failed); every result and HTTP case in SmsUploadWorker; clock offset from serverTime and from
  a Date header; status refresh selection (48 h, pending/mismatch, has server id); rules version choice.
- Cross-check between Kotlin and the server: a Kotlin JVM test signs a sample request with a P-256 key
  (JVM KeyPairGenerator, DER signature) and writes supabase/functions/tests/fixtures/android_signature.json
  (public key SPKI, function name, timestamp, body, signature). A Deno test verifies it with device_auth.ts.
- deno test for parser-rules: signed ok, revoked, returns the active version.
- Dart unit tests with fakes: registration success saves deviceId; deviceLimit screen; offline registration
  retries later; review mapping (no server id -> notAllowed, done -> refresh); logout blocked offline.
- flutter build apk --debug succeeds.
- Manual checks on the emulator against local Supabase and "supabase functions serve" (Claude Code gives me
  the exact commands):
  1. Sign in -> a devices row with a public key and status active appears in Studio.
  2. make_session.ts for Tk 1,500.00 -> open the pay URL -> pick Rocket -> submit TxnId 24010200999 ->
     adb emu sms send 16216 with that TxnId and Tk1,500.00 -> the pay page shows "পেমেন্ট নিশ্চিত হয়েছে"
     within 10 seconds and the app shows "পেমেন্ট নিশ্চিত ✓".
  3. Airplane mode on -> send an SMS -> it shows "পাঠানো বাকি" -> airplane mode off -> it uploads by itself.
  4. Swipe the app away -> send an SMS -> it reaches sms_messages in Studio without opening the app.
  5. A session for Tk 1,600.00 paid with a Tk 1,500.00 SMS -> the app shows "টাকা মেলেনি" -> approve ->
     the pay page shows verified.
  6. Log out -> the device is revoked in Studio; log in again -> the same device row is active again.
  7. devices.last_seen_at updates about every 5 minutes; with the emulator stopped for 16 minutes,
     calling alerts-check opens phoneSilent.
  8. Set the emulator clock 10 minutes ahead -> uploads still work.
  9. Make a parser_rules version 2 active in Studio -> after the next heartbeat the developer lab shows
     "নিয়ম সংস্করণ: 2".

Assumptions
- Specs 01 to 13 are done; local Supabase and "supabase functions serve" are running and reachable from the
  emulator at 10.0.2.2.
- The heartbeat may run later than every 5 minutes when Android saves battery; spec 14 checks on a real
  phone whether the 15-minute phoneSilent limit from spec 11 causes false alerts.
