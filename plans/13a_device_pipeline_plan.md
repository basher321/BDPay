# Plan 13a - Phone to server pipeline

Spec: specs/13a_device_pipeline.md. Written 2026-10-30.
Read with: CLAUDE.md, specs 06, 08-11, 13, 13a and the current code: Kotlin (SmsStore, SmsBridge, SmsPipeline,
SmsReceiver, SmsFilter, NativePrefs, ParserRules/MiniJson), app/android/app/build.gradle.kts, the manifest,
Dart (SmsChannel, InboxRow, ChannelTransactionRepository, ChannelDeviceHealthRepository, SmsUploader /
MockSmsUploader, account_section, dev lab) and supabase/functions (spec 08 handlers, FakeStore).

Reviewed 2026-10-30 against the spec and CLAUDE.md (three times); sections 8-10 list what each review changed.

Note (second review): many of the files below already exist in the project (written 2026-10-30 08:53-09:04,
before this review), and build.gradle.kts already contains the work-runtime-ktx line. Nothing in this plan treats
them as done: when coding starts, each existing file is checked against this plan and fixed where it differs.
Still missing: parser-rules, make_session.ts, native_sms_uploader.dart.

Decisions (2026-10-30, build): work-runtime-ktx 2.12.0 yes; D148 and D149 accepted; D171 option A (monitoring
stops at logout; a new merchant's registration holds the previous merchant's unsent rows); D151 and D159 yes (D159
also carries merchantId for D171); D158 no (the re-queue that was already in SmsStore.onUpgrade was removed);
D164 no (allowBackup unchanged). Build fix: the rules version is the server's parser_rules row version, saved with
the downloaded file as {"version", "rules"} (the highest inner rule version would never reach 2 in manual check 9).

Default rule: until you answer a decision below, the build follows the spec text; where the spec cannot work as
written (section 0, D147-D150) I stop and ask.

## 0. Blockers

| Spec 13a assumes | Today | Effect |
|---|---|---|
| Specs 01-13 done; local Supabase + functions serve reachable at 10.0.2.2 | No Docker / CLI, no migrations (spec 12), no PgStore (12a); spec 13's real repositories are built but untested against a server | Every manual check waits |
| sms-status and claim-review (spec 09) | Not built (spec 09 has only match_rules.ts) | StatusRefreshWorker and review() can be built and unit-tested against the spec 09 contract, never called for real |
| make_session.ts creates a session | Needs spec 09's createPaymentSession, spec 12's tables and 12a's PgStore | The script can be written; it cannot run |
| device-register, sms-ingest, device-heartbeat, device-deactivate (spec 08) | Built and tested (FakeStore) | The phone side can be built against them now |

- D147. **Build order.** A (recommended) build now everything the spec lists that is testable without a server:
  pure Kotlin + JVM tests, the signature fixture + Deno test, Keystore / WorkManager / bridge, Dart with fakes,
  parser-rules (with FakeStore), make_session.ts (written, refusing non-local), the APK build. Manual checks wait
  for the backend. B wait.

## 1. Files

[CHANGED 06] / [CHANGED 08] / [CHANGED 13] = an earlier spec's file.

### Kotlin - new (app/android/app/src/main/kotlin/com/bdpay/verifier/)
Pure (no Android imports; JVM-tested):
- SignedText.kt - signedText(functionName, timestampMs, bodyBytes) = name + "\n" + ts + "\n" + hex SHA-256(body).
- JsonWriter.kt - a tiny JSON writer (strings escaped, numbers, booleans, null, lists, maps) - org.json is an
  Android stub on the JVM, and no library may be added.
- UploadBatch.kt - selectBatch(rows, max = 50): queued/failed only, oldest first; ingestBody(rows) builds the
  sms-ingest JSON {items: [{localId, sender, body, receivedAt (ISO UTC), simSlot, dedupeHash}]}.
- UploadOutcome.kt - applyResults(rows, results) -> row updates (accepted / duplicate / rejected / hashMismatch);
  applyHttpFailure(rows, status, errorCode) -> {updates, action: retryLater | retryNowAfterClockFix | stopRevoked}.
- ClockOffset.kt - offsetFrom(serverTimeIso | dateHeader, deviceNowMs) -> Long; signed timestamp = now + offset.
- StatusRefresh.kt - selectForRefresh(rows, nowMs): server_sms_id set, pending/mismatch, received in 48 h; batches
  of 100; statusBody(ids); applyStatus(results) -> updates incl. claim_json.
- RulesChoice.kt - chooseRules(bundledJson, downloadedJson?): the downloaded file only when it parses and its
  version is higher; rulesVersion(rules) = highest rule version (plan 08 D70).
- PipelineState.kt - data class {deviceId, revoked, clockOffsetMs, rulesVersion, lastServerContactMs} + toMap().
- UploadRun.kt - the whole upload loop as plain Kotlin over two small interfaces (InboxRows: select / apply;
  Server: post): no deviceId -> nothing; revoked -> nothing; batch -> apply -> repeat until no rows are left or a
  request fails; rows already tried in this run are not picked again in the same run (so a hashMismatch row
  cannot loop); a result missing for a sent row -> failed + retry_count + 1; 401 staleTimestamp -> clock fix and
  one immediate retry; the worker only returns UploadRun's verdict (success / retry / stop).
- HeartbeatRun.kt - the heartbeat as plain Kotlin: body (appVersion, smsPermission, batteryOptimizationOff,
  monitoring, queueCount), lastServerContactMs on success, rules fetch when the server version is higher, and the
  rules are saved only if RulesChoice accepts them (a broken file changes nothing, not even rulesVersion).
- StatusRun.kt - the status refresh loop as plain Kotlin (select, batches of 100, apply).
Thin (Android):
- DeviceKeys.kt - Keystore P-256 key "bdpay_device_key_v1" (PURPOSE_SIGN only, DIGEST_SHA256, created inside
  the AndroidKeyStore provider, so the private key is non-exportable by design). publicKeySpki() = the
  certificate's public key .encoded (base64); sign(text) base64 DER ("SHA256withECDSA"). It has no method that
  returns the private key or its bytes, and nothing calls getEncoded() on it. installId UUID in SharedPreferences.
  Never logs.
- DeviceConfig.kt - SharedPreferences "bdpay_device": deviceId, functionsUrl, clockOffsetMs, revoked,
  rulesVersion, lastServerContactMs; change listeners -> the "pipeline" event.
- ServerClient.kt - signed POST with HttpURLConnection, 15 s connect + read timeout, headers X-Device-Id /
  X-Timestamp / X-Signature; returns {status, json, dateHeader}; updates the clock offset from serverTime or Date.
  Errors carry a fixed code only (never the body, URL, headers or signature). instanceFollowRedirects = false,
  so a redirect can never re-send the signed headers and body to another address; a 3xx is treated like a 5xx.
- RulesStore.kt - the downloaded rules JSON in filesDir/parser_rules_server.json (written to a temp file, then
  renamed); read by SmsPipeline through RulesChoice.
- SmsUploadWorker.kt, StatusRefreshWorker.kt, HeartbeatWorker.kt - CoroutineWorkers that only wire UploadRun /
  StatusRun / HeartbeatRun to SmsStore, ServerClient and DeviceConfig. doWork catches everything and returns
  Result.retry() / failure without an exception message (WorkManager logs uncaught exceptions with their
  message, so none may escape).
- Pipeline.kt - enqueue helpers:
  - uploadNow: unique work "sms-upload". If a request is already ENQUEUED (not started) and has never run ->
    nothing (it will pick up the new rows). If the ENQUEUED request is waiting out a retry backoff
    (runAttemptCount > 0, which can grow to hours after repeated 5xx / timeouts) -> REPLACE it with a fresh
    request, so "internet is back" and "সব পাঠান" upload now instead of hours later; it is not running, so
    REPLACE cannot cause two uploads at once. If one is RUNNING -> APPEND_OR_REPLACE one follow-up (so the second request runs after it,
    never at the same time). Otherwise enqueue. Network constraint, exponential backoff from 30 s, expedited on
    Android 12+ with OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST (D149). The state check and the enqueue
    run inside one process-wide lock, so the receiver, the bridge and the network callback cannot all decide
    "append" at once. Even without the lock, unique work with APPEND only ever chains requests one after
    another; it never runs two "sms-upload" workers in parallel. At most one running and one waiting upload exist.
  - Verdicts: retryLater -> Result.retry(); stopRevoked and "no deviceId" -> Result.success() (nothing to retry;
    the next registration calls uploadNow); done -> Result.success() and refreshNow() + scheduleHeartbeat(KEEP).
  - refreshNow: unique "sms-status", KEEP (a running refresh is not doubled).
  - scheduleHeartbeat: unique "heartbeat"; the worker schedules its successor with APPEND_OR_REPLACE and a
    5-minute initial delay (REPLACE would cancel the running worker itself); app start and every upload run use
    KEEP (D160).
- UploadState.kt - the in-memory set of row ids being sent (D148), read by listInbox. The upload worker removes
  its ids in a finally block, so a worker that WorkManager stops mid-request (network lost, quota) never leaves
  rows shown as "sending"; those rows are still queued / failed in the database and the next run sends them
  (the server answers duplicate if the first request had arrived).

### Kotlin - changed
- [CHANGED 06] SmsStore.kt - DB_VERSION 2; onCreate makes the v2 table; onUpgrade(1 -> 2) adds the 3 columns
  (section 4); listInbox returns server_sms_id, claim_json and "sending" (D148); new queries: selectForUpload,
  selectForRefresh, countPending, and two guarded writers in one transaction each - applyUploadResults (UPDATE
  ... WHERE id = ? AND sync_status IN ('queued','failed'), so it can never overwrite a row another path already
  finished) and applyStatus (writes verify_status, server_message, claim_json, last_status_check_ms only, WHERE
  server_sms_id = ?). Never a delete.
  - countPending = rows with sync_status queued or failed in the database. "sending" rows are still queued in
    the database (D148), so this already equals the spec's queued + sending + failed; adding the in-memory
    sending set again would count them twice.
  - A verifyStatus outside the table's CHECK list (pending, verified, mismatch, rejected) is skipped for that row
    (row unchanged, picked up again later) instead of failing the whole batch's transaction. Spec 09 never
    sends another value, so this is a guard only. A row missing from the sms-status results is left unchanged.
  - claim_json is written from the parsed claim with expectedAmountPoisha as a Long (never Double; MiniJson
    numbers are read as Long), or SQL NULL when claim is null.
- [CHANGED 06] SmsPipeline.kt - rules come from RulesChoice (bundled vs downloaded) and are reloaded when the
  "rules" update happens; after a stored row, Pipeline.uploadNow() when autoSend is on (D151).
- [CHANGED 06] SmsBridge.kt - the 9 new methods of the Contract, the "pipeline" and "rules" events, setAutoSend
  (D151); network callback "online" also calls uploadNow when autoSend is on. Errors go to Dart as
  result.error(<fixed code>, null, null) - never an exception message, because a PlatformException message can
  end up in Flutter's error log. No method returns key material other than the public SPKI.
- [CHANGED 06] NativePrefs.kt - autoSend (D151).
- [CHANGED 06] MainActivity.kt - starts the heartbeat chain (KEEP) on create.
- [CHANGED 06, only with D164 = yes] AndroidManifest.xml - android:allowBackup="false" (and no
  fullBackupContent), so Android's cloud backup cannot copy the SMS database, installId or deviceId to Google
  Drive or another phone.

### Kotlin tests - new (app/android/app/src/test/kotlin/com/bdpay/verifier/)
- SignedTextTest, JsonWriterTest, UploadBatchTest, UploadOutcomeTest (every result and HTTP case),
  UploadRunTest (the loop: no deviceId, revoked, 30 rows -> 1 batch, 70 -> 2, stop on failure, hashMismatch not
  retried in the same run, response lost -> failed then duplicate with the same server id, missing result,
  staleTimestamp once), ClockOffsetTest, StatusRefreshTest + StatusRunTest, RulesChoiceTest, HeartbeatRunTest
  (rules fetched only when higher; broken rules keep the old ones and the old version), SmsStoreMigrationTest
  (D152), NoLoggingTest (scans the Kotlin sources: no android.util.Log, println, print(, System.out, System.err,
  printStackTrace; no result.error(...) that passes .message; no getEncoded / .encoded on a private key).
- AndroidSignatureFixtureTest - JVM KeyPairGenerator("EC", secp256r1) + Signature("SHA256withECDSA") over
  SignedText for a sample sms-ingest body; writes supabase/functions/tests/fixtures/android_signature.json
  ({publicKeySpki, functionName, timestamp, body, signature}); the private key exists only in memory and is a
  throwaway JVM key, not a device key. The sample body is made up (fake TrxID and numbers), never a real SMS.

### Gradle / manifest
- [CHANGED 06] app/android/app/build.gradle.kts - `implementation("androidx.work:work-runtime-ktx:2.12.0")`
  (section 2).
- AndroidManifest.xml - nothing needed for WorkManager (its own manifest merges in RECEIVE_BOOT_COMPLETED and
  its boot receiver, which the spec's "after reboot" needs). No FOREGROUND_SERVICE, no notification, no
  getForegroundInfo (D149).

### Dart - new (app/lib/)
- data/device/device_registration.dart - DeviceRegistration: on signedIn (start, sign-in, device-name change, back
  online / in front) -> channel.getInstallId + getDevicePublicKey -> FunctionsGateway "device-register" ->
  channel.setDeviceConfig(deviceId, functionsUrl, serverTime); state stream {unregistered, registering,
  registered(deviceId), deviceLimit, offline}.
- data/device/pipeline_state.dart - PipelineState model + a repository over getPipelineState + "pipeline" events.
- data/upload/native_sms_uploader.dart - NativeSmsUploader: retry / retryAll = channel.uploadNow() (D153).
- features/shell or auth: device_limit_screen.dart - the full screen with "আবার চেষ্টা করুন" and "লগ আউট".
- features/home/widgets/disconnected_banner.dart - the red "এই ফোন BDPay থেকে বিচ্ছিন্ন — আবার লগইন করুন" banner.

### Dart - changed
- [CHANGED 06] data/device/sms_channel.dart - the new methods and events.
- [CHANGED 06] data/device/inbox_row.dart - serverSmsId, claimJson, sending.
- [CHANGED 06] data/device/device_transaction_repository.dart - rows map claim_json -> SmsTransaction.claim and
  sending -> SyncStatus.sending; retry / retryAllPending use NativeSmsUploader (no updateSync from Dart, D153);
  review() calls claim-review; refreshNow() every 30 s while the app is in front.
- [CHANGED 06] domain/models/sms_transaction.dart - serverSmsId (String?) (D154).
- [CHANGED 06] data/device/device_health_repository.dart - pingServer() = heartbeatNow(); lastServerContactAt from
  the pipeline state; revoked counts as a problem.
- [CHANGED 02] shell/app_header.dart, features/home/widgets/device_card.dart, health_card.dart - rule 3 (D155).
- [CHANGED 05/13] shell/app_shell.dart - the device-limit screen; features/home/home_screen.dart - the banner.
- [CHANGED 05/13] features/settings/widgets/account_section.dart - logout: queue empty -> deactivateDevice() ->
  false: toast "লগ আউট করতে ইন্টারনেট দরকার"; true: clearDeviceConfig + signOut. Banner logout skips deactivate.
- [CHANGED 05] features/settings/widgets/device_section.dart - device ID from the registration (D156); a name
  change re-registers.
- [CHANGED 06] features/dev_lab/dev_lab_screen.dart - "নিয়ম সংস্করণ: {rulesVersion}".
- [CHANGED 06] data/device/device_providers.dart - parserRulesProvider re-reads on the "rules" event.
- [CHANGED 05/13] data/account_providers.dart / data/providers.dart - wiring (real only when configured; mocks in
  tests as today).
- [CHANGED 01] lib/l10n/app_bn.arb - the new texts.
- Dart logging: no print / debugPrint / log() in the new or changed files; DeviceRegistration, review() and
  logout map FunctionsGateway and PlatformException errors to result codes and never show or log their
  messages (they can contain the user token or request details).

### Dart tests - new (app/test/)
- data/device/device_registration_test.dart (success saves deviceId + serverTime; runs again on app start and on
  a device-name change with the same installId; deviceLimit; offline then "online" -> registered; after success
  uploadNow() is called so revoked-time queued rows go out), data/device/review_mapping_test.dart,
  data/device/native_pipeline_channel_test.dart (MethodChannel mock handler - no package: listInbox maps
  server_sms_id / claim_json / sending; 30 s refreshNow while in front, none in the background),
  features/device_limit_screen_test.dart, features/disconnected_banner_test.dart (banner + health card counts
  revoked + banner logout skips deactivate), features/online_pill_test.dart (rule 3, D155),
  features/settings/logout_test.dart (offline -> blocked toast; success -> deactivate, clearDeviceConfig, then
  signOut, in that order), features/dev_lab/rules_version_test.dart, data/providers_wiring_test.dart (the app
  wiring uses NativeSmsUploader and the native pipeline; pingServer() calls heartbeatNow()).

### Backend - new
- supabase/functions/_shared/rules.ts - handle(req, deps) for parser-rules: same signed check as spec 08
  (checkDeviceRequest with "parser-rules"), body {} -> {ok: true, version, rules} from Store.getParserRules
  (already in the Store interface - no Store, FakeStore or table change). Logs only the fixed log entry shape
  of spec 08 (function, status, code), never headers, signature or body.
- supabase/functions/parser-rules/index.ts - serveFunction wiring, like spec 08's four.
- supabase/functions/tests/parser_rules_fn_test.ts - signed ok, revoked 403, unsigned 401, returns the active
  version, 405 on GET.
- supabase/functions/tests/android_signature_test.ts - verifies the Kotlin fixture with device_auth.ts (imported as
  JSON, so no --allow-read needed).
- supabase/functions/tests/fixtures/android_signature.json - written by the Kotlin test (public data only).
- supabase/scripts/make_session.ts - local helper: exports main(env, args); refuses unless SUPABASE_URL is local
  (assertLocal from 12a) before making any client; finds the merchant by email, creates the session through the
  Store's createPaymentSession (spec 09; no SQL in the script), prints only the pay page URL (D157) - never the
  service key or any other env value. --amount "1500.00" is parsed as a string into whole poisha (digits, one
  optional dot, at most 2 decimals; anything else is refused) - never through parseFloat / Number.
- supabase/functions/tests/make_session_guard_test.ts - main() with a remote or missing SUPABASE_URL throws
  "refusing" before any network call (fake fetch records none); amount parsing ("1500.00" -> 150000,
  "1,500.00" / "15.555" / "-1" refused).
- [CHANGED 08] tests/boundaries_test.ts - the INDEX list gains parser-rules/index.ts and the CORE list rules.ts.
- [CHANGED 08] tests/logging_test.ts - parser-rules added: no header, signature or body in its log lines.

## 2. Gradle dependency (asked before adding)

`implementation("androidx.work:work-runtime-ktx:2.12.0")` - the newest stable release (published 2026-09-23,
more than two weeks ago) from Google's Maven repository. The line is already in build.gradle.kts (added before
this review); it still needs your explicit yes, and without it the line comes out again before any build. It brings its own dependencies (work-runtime,
kotlinx-coroutines, androidx.startup, room for WorkManager's own database), which Gradle resolves; nothing else is
added. No work-testing artifact (that would be a second library) - workers stay thin and the logic is tested as
plain Kotlin.

## 3. Order of work

0. You answer D147-D158 (at least D147, the Gradle yes, D148 and D149).
1. Pure Kotlin + JVM tests: SignedText, JsonWriter, UploadBatch, UploadOutcome, ClockOffset, StatusRefresh,
   RulesChoice, PipelineState. `cd app/android; ./gradlew :app:testDebugUnitTest` after each.
2. Signature fixture: AndroidSignatureFixtureTest writes the fixture; android_signature_test.ts verifies it with
   device_auth.ts (`deno test --allow-read supabase/functions/tests`).
3. Gradle dependency (after your yes); Keystore (DeviceKeys), DeviceConfig, ServerClient, RulesStore, SmsStore v2
   (+ SmsStoreMigrationTest), the three workers, Pipeline, bridge additions, SmsPipeline / MainActivity changes.
   Kotlin tests + `flutter build apk --debug` after this group.
4. Dart: channel + InboxRow, pipeline state, DeviceRegistration, NativeSmsUploader, transaction repository (claim,
   sending, review, 30 s refresh), health repository, UI pieces, logout, dev lab line, ARB.
   `flutter analyze` after each group; `flutter test` at the end.
5. parser-rules (handler, index, test) + boundaries_test; make_session.ts. `deno check`, `deno lint`,
   `deno fmt --check`, `deno test --allow-read`.
6. Full run: Kotlin tests, flutter analyze / test / build apk, deno checks, the logging searches.

## 4. SmsStore upgrade (version 1 -> 2) without losing rows

- DB_VERSION becomes 2. SQLiteOpenHelper calls onUpgrade(db, 1, 2) once, inside its own transaction, the first
  time the new app opens the database; existing rows stay where they are.
- onUpgrade runs only additive statements (inside the one transaction SQLiteOpenHelper opens for it, so a failure
  rolls back to version 1 with every row untouched), in order, each guarded by `PRAGMA table_info(sms_inbox)` so a column
  that already exists (a half-tried dev build) is skipped instead of failing the whole upgrade:
  `ALTER TABLE sms_inbox ADD COLUMN server_sms_id TEXT NULL`
  `ALTER TABLE sms_inbox ADD COLUMN claim_json TEXT NULL`
  `ALTER TABLE sms_inbox ADD COLUMN last_status_check_ms INTEGER NULL`
  Existing rows get NULL in the new columns, which means "not on the server yet / no claim / never checked" - the
  correct meaning for rows that have not been uploaded with a server id. No existing value is changed by these
  statements. Rows the old mock marked "sent" (no server id) would never reach the server - D158 proposes
  re-queuing them, which DOES change existing rows, so it is only done with your yes; without it the upgrade
  changes no row.
- No DROP, no table copy, no CHECK change (SQLite cannot change a CHECK without rebuilding the table, which the
  spec forbids - hence D148 for "sending").
- onCreate (fresh installs) creates the v2 table directly with the same three columns, so both paths end in the
  same schema.
- onDowngrade is not overridden: an older app on a newer database fails loudly instead of deleting data.
- Once a v2 build has been installed anywhere, the v2 upgrade is never edited; a later change is version 3 (the
  same rule as server migrations).
- Test (D152): SmsStoreMigrationTest checks the upgrade statement list is ADD COLUMN only and that onCreate's
  columns = v1 columns + the three; the real upgrade is checked on the emulator by installing the new APK over the
  current one (`adb install -r`) and seeing the old rows still listed.

## 5. Acceptance criteria -> test or check

Commands below are PowerShell from D:\BDPay unless noted; `adb` is in D:\tools\android-sdk\platform-tools.

| Criterion | Test or check |
|---|---|
| flutter analyze: no issues | `cd app; flutter analyze` |
| flutter test passes (earlier tests too) | `cd app; flutter test` |
| Kotlin: signed text exactly name + "\n" + ts + "\n" + hex SHA-256(body) | SignedTextTest (known vector computed outside Kotlin, like plan 08's hash pin) |
| Kotlin: batch selection oldest first, max 50, only queued/failed | UploadBatchTest (incl. 70 rows -> 50 then 20; 30 rows -> one batch) |
| Kotlin: every result and HTTP case in SmsUploadWorker | UploadOutcomeTest + UploadRunTest: accepted, duplicate, rejected, hashMismatch; network / timeout / 5xx / 429 -> failed + retry_count; 401 staleTimestamp -> clock fix + one retry; 401 unknownDevice / 403 deviceRevoked -> queued + revoked + stop; no deviceId -> nothing; missing result; no loop on hashMismatch |
| Edge: 30 SMS -> one batch; 70 -> two; response lost -> duplicate with the same server id | UploadRunTest |
| Edge: revoked while offline -> rows stay queued and upload after the next login | UploadRunTest + device_registration_test (uploadNow after a successful registration) |
| Edge: broken downloaded rules -> keep the previous | RulesChoiceTest + HeartbeatRunTest |
| Edge: two quick uploadNow() -> one running, one after it | review of Pipeline.uploadNow (lock + unique work; no WorkManager test library allowed) + manual check 11 |
| Internet back after a long retry backoff -> uploads now | review of Pipeline.uploadNow (backoff request replaced) + manual check 3 after a few failed tries (stop `supabase functions serve`, send an SMS, start it again) |
| A stopped upload never leaves rows stuck as "sending" | PipelineRunTest (run cancelled mid-request -> sending set empty, rows still queued) |
| Edge: phone clock 10 minutes fast | ClockOffsetTest + UploadRunTest (staleTimestamp -> offset fixed -> one retry succeeds) + manual check 8 |
| Edge: app force-stopped | no check: Android rule, covered by spec 06's warning |
| Upload worker setup: unique "sms-upload", network required, backoff from 30 s, expedited with fallback | review of Pipeline.kt (thin code; no WorkManager test library) + manual checks 3 and 11 |
| Heartbeat schedules the next one in 5 minutes whatever the result; started at app start | HeartbeatRunTest (returns "next in 5 min" on success and on every failure) + review + manual check 7 |
| Status refresh runs after upload and heartbeat, fires "inbox" | StatusRunTest + PipelineRunTest (upload done -> refresh requested) + manual check 5 |
| Unknown verifyStatus / missing result in sms-status -> row unchanged | StatusRefreshTest |
| Rule 1: private key never leaves the Keystore | see "Private key never leaves the Keystore" below |
| Rule 4: developer lab "নিয়ম সংস্করণ: {rulesVersion}" | rules_version_test + manual check 9 |
| Rule 5: parser-rules same signed check as spec 08 | parser_rules_fn_test (unsigned 401, stale 401, bad signature 401, revoked 403) |
| NativeSmsUploader replaces the mock in the app; pingServer() runs a heartbeat | providers_wiring_test |
| Heartbeat body, lastServerContact, rules fetch when higher | HeartbeatRunTest |
| Rule 2: banner, health card problem, banner logout skips deactivate | disconnected_banner_test |
| Rule 3: online pill / server row / "শেষ সংযোগ" from lastServerContactMs | online_pill_test |
| Rule 6: make_session.ts refuses a non-local URL | make_session_guard_test.ts |
| Registration on app start and on a device-name change | device_registration_test |
| listInbox server_sms_id / claim_json -> SmsTransaction.claim; 30 s refresh while in front | native_pipeline_channel_test |
| Logout order: deactivate -> clear -> sign out; key and installId stay | logout_test (+ review: clearDeviceConfig does not touch the key or installId) |
| Kotlin: clock offset from serverTime and from a Date header | ClockOffsetTest (10 minutes fast -> -600000; Date header RFC 1123) |
| Kotlin: status refresh selection (48 h, pending/mismatch, server id) | StatusRefreshTest (+ batches of 100, claim_json written) |
| Kotlin: rules version choice | RulesChoiceTest (higher downloaded wins; lower / equal / broken -> bundled) |
| Cross-check Kotlin signature <-> server | AndroidSignatureFixtureTest writes the fixture; android_signature_test.ts verifies it with checkDeviceRequest |
| deno test parser-rules: signed ok, revoked, active version | parser_rules_fn_test.ts |
| Dart: registration success saves deviceId | device_registration_test (fake channel + fake FunctionsGateway) |
| Dart: deviceLimit screen | device_registration_test + device_limit_screen_test |
| Dart: offline registration retries later | device_registration_test (offline, then "online" event -> registered) |
| Dart: review mapping (no server id -> notAllowed, done -> refresh) | review_mapping_test (+ notFound -> notAllowed, offline -> offline) |
| Dart: logout blocked offline | logout_test |
| flutter build apk --debug | `cd app; flutter build apk --debug --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_ANON_KEY=$env:BDPAY_ANON_KEY` |
| deno check / lint pass | `deno check supabase/functions supabase/scripts; deno lint supabase/functions supabase/scripts` |
| Never log SMS content, TrxIDs, payer numbers, keys, signatures, tokens | NoLoggingTest (Kotlin sources, incl. result.error without messages) + the Dart secrets_and_boundaries_test extended to the new files (no print / debugPrint / log) + logging_test.ts for parser-rules + doWork never lets an exception escape + manual check 10 (logcat) |
| make_session.ts: money as whole poisha, no float | make_session_guard_test (amount parsing) |
| Private key never leaves the Keystore | NoLoggingTest also fails on getEncoded / privateKey.encoded in DeviceKeys; the bridge has no method returning key material; review |
| Kotlin tests command | spec: `./gradlew :app:testDebugUnitTest`; in PowerShell: `cd app\android; .\gradlew.bat :app:testDebugUnitTest` |
| Upgrade keeps rows | section 4 + manual check 0 |

Manual checks (needs backend; you run them). Before: local Supabase + spec 12 schema/seed, `supabase functions
serve --env-file supabase/functions/.env.local --no-verify-jwt` running, the app on the emulator with the command
from plan 13 section 4.

0. Upgrade: with the current app installed and some SMS in it, `cd app; flutter build apk --debug ...` then
   `adb install -r app\build\app\outputs\flutter-apk\app-debug.apk`; open লেনদেন -> the old rows are still there.
1. Sign in -> Studio (http://127.0.0.1:54323) > devices: one row, public_key_spki filled, status active.
2. `deno run --allow-net=127.0.0.1:54321 --allow-env --env-file=supabase/functions/.env.test.local
   supabase/scripts/make_session.ts --email <your login email> --amount 1500.00 --order "#T1"` -> open the printed
   URL in the emulator's Chrome (it must reach 10.0.2.2) -> Rocket -> TxnId 24010200999 -> then
   `adb emu sms send 16216 "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200999"`
   -> within 10 s the page shows "পেমেন্ট নিশ্চিত হয়েছে" and the app "পেমেন্ট নিশ্চিত ✓".
3. `adb shell cmd connectivity airplane-mode enable` -> send another Rocket SMS (new TxnId, e.g. 24010200998) ->
   it shows "পাঠানো বাকি" -> `adb shell cmd connectivity airplane-mode disable` -> it uploads by itself.
4. Swipe the app away (or `adb shell am kill com.bdpay.verifier` - not force-stop) -> send an SMS (TxnId
   24010200997) -> Studio > sms_messages shows it without opening the app.
5. make_session.ts with `--amount 1600.00 --order "#T2"` -> submit TxnId 24010200996 -> send the Tk1,500.00 SMS
   with that TxnId -> the app shows "টাকা মেলেনি" -> open it -> approve -> the pay page shows verified.
6. সেটিংস > লগ আউট -> Studio devices.status = revoked; sign in again -> the same row, status active.
7. Studio devices.last_seen_at moves about every 5 minutes; `adb emu kill`, wait 16 minutes, then
   `Invoke-RestMethod -Method Post -Uri http://127.0.0.1:54321/functions/v1/alerts-check -Headers @{ 'X-Cron-Secret' = $env:BDPAY_CRON_SECRET } -Body '{}' -ContentType 'application/json'`
   (you set $env:BDPAY_CRON_SECRET to the value in your .env.local yourself) -> Studio alerts has an open
   phoneSilent (needs spec 11's alerts-check).
8. Needs an emulator image without Google Play ("Google APIs"), because `adb root` is refused on Play images;
   on a Play image, turn off automatic time in the emulator's Settings > System > Date & time and set it 10
   minutes ahead by hand instead. `adb root`; `adb shell settings put global auto_time 0`;
   `$t = (Get-Date).AddMinutes(10).ToString('MMddHHmmyyyy.ss'); adb shell "date $t"` -> send an SMS -> it uploads
   (first try may be staleTimestamp, then the fixed retry). Afterwards `adb shell settings put global auto_time 1`.
9. In Studio's SQL editor: set the version 1 row is_active = false, then insert version 2 with the same rules
   JSON and is_active = true -> wait for the next heartbeat (or tap the server row's ping) -> the developer lab
   shows "নিয়ম সংস্করণ: 2".
10. Logging: `adb logcat -d | Select-String -Pattern "TxnId|TrxID|24010200|01712|BEGIN|eyJ|X-Signature"` -> no
    lines from com.bdpay.verifier or WM-WorkerWrapper that contain SMS text, keys or signatures.
11. Two quick uploads: airplane mode on, send two SMS, airplane mode off and immediately tap "সব পাঠান" twice ->
    Studio sms_messages has each SMS once and both rows show "পাঠানো হয়েছে".

## 6. Unclear or wrong in the spec

Blocking: D147 (build order / no backend), the Gradle yes, D148, D149.

- D148. **"sets them sending" cannot be stored.** sms_inbox has CHECK (sync_status IN ('queued','sent','failed')),
  and SQLite cannot change a CHECK without rebuilding the table, which "add columns only, never drop" forbids.
  Options: A (recommended) "sending" lives only in memory (UploadState, same process as the worker and the bridge);
  listInbox reports it; after a crash the rows are simply still queued / failed and the next upload sends them
  again (sms-ingest answers duplicate - no double counting); B a fourth new column (upload_started_ms) - more than
  the spec's three. This also matches spec 06's own note: "sending is never stored".
- D149. **Expedited work on Android 8-11 needs a foreground notification.** On API 26-30 WorkManager runs expedited
  work as a foreground service and calls getForegroundInfo(); without it the worker crashes. The spec says
  "expedited" but "no foreground service", so the only in-Scope choice is: expedited only on Android 12+, normal
  (non-expedited) work below - same code, no notification, uploads may start a little later on old phones. A
  foreground notification is out of Scope and is not offered. Needs your yes because it narrows "expedited".
- D150. **sms-status and claim-review do not exist yet** (spec 09). The workers and review() are built against
  spec 09's written contract; they cannot be run end to end until spec 09 is built.
- D151. **autoSend is not known to the native side.** The receiver must enqueue uploads "only when autoSend is on"
  while the app is closed, but autoSend lives in Dart's MockSettingsRepository (in memory, not saved - even the
  device name resets on restart). Proposal: a bridge method setAutoSend(bool) saved in NativePrefs (like
  setMonitoring), called when the setting changes and at app start. Not in the spec's bridge list -> needs your
  yes. The unsaved settings (device name, autoSend) are a spec 05 gap; noted.
- D152. **The SQLite upgrade cannot run in a JVM test** (Android's SQLite is a stub there, and Robolectric would be
  a new library). The JVM test checks the statements and the column list; the real upgrade is manual check 0.
- D153. **SmsUploader does not fit a background batch.** SmsUploader.upload(one row) -> UploadResult is written
  back by Dart with updateSync; with the native worker the rows are written natively. Proposal: in the app,
  retry / retryAllPending call uploadNow() and the list refreshes from the "inbox" event; Dart no longer writes
  sync results; MockSmsUploader and the old path stay for tests (spec: "the mock stays for tests").
- D154. **review() needs the server SMS id per transaction.** Proposal: SmsTransaction gets serverSmsId (String?),
  filled from listInbox; nothing in the UI shows it.
- D155. **Rule 3 "online pill uses lastServerContactMs" has no threshold.** Proposal: online = internet up AND last
  server contact within the last 10 minutes (spec 09's deviceOnline rule); the "শেষ সংযোগ" text shows the time.
  Heartbeats every 5 minutes keep it green; Doze may turn it amber/red on an idle phone (spec 14 checks).
- D156. **"set AuthState.deviceId"** - AuthState comes from AuthRepository, which does not know the device.
  Proposal: DeviceRegistration exposes its own state and the settings "এই ডিভাইস" ID reads it; AuthState.deviceId
  stays as it is (null on the real path). The server device id is a UUID; the settings row shows it shortened
  (first 8 characters). No new screen shows the full id.
- D157. **make_session.ts prints a pay URL that contains the session token.** The spec asks for it; it is a local
  test session on your machine. The script prints only that URL (no keys), and refuses a non-local SUPABASE_URL.
  The URL's host must be reachable from the emulator's browser: it prints both 127.0.0.1 and 10.0.2.2 forms.
- D158. [CHANGES EXISTING ROWS] **Rows marked "sent" by the old mock.** Spec 01-06's MockSmsUploader marked rows sent without a server.
  After the upgrade they have no server_sms_id and would never reach the server. Proposal: onUpgrade also sets
  sync_status = 'queued' WHERE sync_status = 'sent' AND server_sms_id IS NULL (an UPDATE with WHERE, no delete),
  so they upload once (the server de-duplicates). Needs your yes (it changes existing rows' status).
- D159. **setDeviceConfig has no serverTime argument**, but registration must "apply serverTime to the clock
  offset". Proposal: setDeviceConfig(deviceId, functionsUrl, serverTime) (one extra optional argument).
- D160. **Heartbeat on Android 8-11 after reboot.** WorkManager reschedules after reboot, but a one-time chain whose
  next job was pending survives only if it was enqueued; if the process died mid-run the chain may stop.
  Proposal: MainActivity and the boot-time WorkManager reschedule use KEEP on the unique "heartbeat" work, and
  every SmsUploadWorker run also calls scheduleHeartbeat(KEEP) - so any SMS or app start restarts a broken chain.
- D161. **"SmsBridge additions (rule 9)"** - there is no rule 9; the additions are in the Contract. Noted.
- D162. **Clock fix for a wrong date.** If the phone's date is days off, staleTimestamp keeps the HTTP Date header
  as the only time source; the offset from the Date header (1 s resolution) is enough for the 5-minute window.
- D163. **Re-registration on every start re-sends the public key.** device-register (spec 08) updates the key each
  time (key rotation); with the same Keystore key that is a no-op. If the Keystore key is lost (app data cleared),
  installId is lost too, so the server gets a new device (counts toward the limit of 3) - expected.
- D164. **Android cloud backup would copy the SMS database off the phone.** The manifest has no
  android:allowBackup, so it defaults to true: Android's auto-backup can copy bdpay_sms.db (SMS text) and the
  SharedPreferences (installId, deviceId) to the user's Google Drive and restore them onto another phone - where
  the Keystore key does not exist, so every signed request would fail with badSignature, and SMS text would sit in
  a cloud backup. Proposal: android:allowBackup="false". A one-line manifest change outside the spec's list ->
  needs your yes; recommended.
- D165. **Gradle may install SDK parts by itself.** The last debug build installed CMake 3.22.1 automatically. Adding
  work-runtime-ktx should not need more SDK parts, but if a build starts installing something, I stop and tell you.
- D166. **A status refresh started before an upload finished** can miss the just-uploaded rows (KEEP drops the
  second request while the first runs). They are picked up by the next 30-second refresh or heartbeat; nothing is
  lost. Noted.
- D167. **A hashMismatch row is retried on every later upload run.** The spec says hashMismatch -> failed,
  retry_count + 1, with no limit. The row is never sent twice in one run (UploadRun skips rows already tried),
  but if the server keeps answering hashMismatch it stays "Failed" and is re-sent once per run. Nothing is lost
  or counted twice (the server stores nothing for a hash mismatch). Noted; a retry limit would be a spec change.
- D168. **Revoked flag and re-registration order.** setDeviceConfig clears the revoked flag before
  DeviceRegistration calls uploadNow(), otherwise the queued rows would be skipped again as "revoked".
- D169. **CLAUDE.md lists the app under apps/mobile; the project and the spec use app/.** The plan follows the
  spec (the current step spec wins). Noted, no folder is moved.
- D170. **make_session.ts needs spec 09's createPaymentSession and 12a's PgStore**, which do not exist yet (section
  0). The script is written against the Store interface; it cannot run until they do.
- D171. [NEEDS YOUR DECISION] **Another merchant signs in on the same phone.** sms_inbox rows carry no merchant,
  and logout keeps them (the spec only clears deviceId). If merchant B signs in after merchant A logged out:
  (a) B's app lists A's SMS - against "a merchant can only ever see its own rows"; (b) SMS caught after A's
  logout (the receiver keeps running) or in the gap between the queue check and deactivate are queued and then
  uploaded under B's new device (spec 08 keys devices by merchant + installId), so A's payment SMS would be
  stored and matched for B. Nothing in specs 05, 13 or 13a covers this. Options: A (recommended) stop
  monitoring at logout and refuse uploads when the registered merchant differs from the one recorded in
  DeviceConfig at the last registration (rows wait, nothing is sent to the wrong merchant) - a small addition
  outside the spec text; B leave as written and note it for a later spec. I do not build either without your
  answer.
- D172. **Cleartext HTTP to 10.0.2.2.** Kotlin's HttpURLConnection obeys Android's cleartext rule. The debug-only
  network_security_config from spec 13 (D134) already allows http://10.0.2.2 and nothing else; release stays
  HTTPS-only. No change needed; recorded so the manual checks are not blocked by it.

## 7. CLAUDE.md check

| Rule | How the plan keeps it |
|---|---|
| Server decides paid; never mark verified on the device | verify_status is written only from sms-ingest / sms-status answers; the mock-only "markVerified" path is not used by the app |
| SMS capture native, works with the UI closed | receiver + WorkManager; no Flutter needed for upload |
| Add no package / library the spec does not name; ask first | only work-runtime-ktx 2.12.0 (named; already in the file, needs your yes or it is removed); its own transitive dependencies (work-runtime, coroutines, startup, room) come with it; no OkHttp, no work-testing, no Robolectric, no Dart package |
| Money in whole poisha, never float | claim_json amounts as Long in Kotlin; make_session.ts parses "1500.00" as a string into poisha |
| Never read or print .env files | make_session.ts reads env vars only through the process (you pass --env-file when you run it) and prints none; Claude never opens the .env files |
| Secrets on the phone | the private key stays in the Keystore (never exported); deviceId / installId are not secrets |
| Never log SMS, TrxID, keys, tokens | no Log calls in Kotlin; no print in Dart; logcat check 10 |
| SMS text untrusted, plain text | unchanged; bodies only in bound SQLite args and JSON-escaped request bodies |
| Device signs every request (Backend rules) | ServerClient signs exactly spec 08's text; fixture cross-check |
| Phone database: rows never deleted | SmsStore v2 adds columns only (existence-checked); no delete; guarded UPDATEs only; D158 (an UPDATE with WHERE) only with your yes |
| SMS text stays on the phone and the server only | D164 (no cloud backup of the SMS database) |
| All user text from ARB, Bangla | new texts in app_bn.arb |
| Design reference / theme tokens | banner and device-limit screen reuse AppCard, AppButton, AppColors.er |
| Edge Function logic only via Store | parser-rules uses Store.getParserRules and checkDeviceRequest |
| Work only on local Supabase | make_session.ts refuses non-local; no remote calls |
| Ask before installing / changing data | the Gradle dependency and `flutter build` (Gradle downloads) asked; D165 (stop if Gradle installs SDK parts); adb commands are yours |
| Do only what the spec says | no foreground service, no push, no new library, no server table; D151, D158, D164 only with your yes |

## 8. Review changes (2026-10-30)

- Scope: D149 B (foreground notification) marked outside Scope and the manifest option removed; no full-device-id
  screen (D156); additions that need a yes listed in the CLAUDE.md table (D151, D158, D164).
- Key and logs: DeviceKeys spelled out (AndroidKeyStore, sign-only, no getEncoded on the private key); ServerClient
  errors carry codes only; workers never let an exception escape (WorkManager logs exception messages);
  NoLoggingTest scans the Kotlin sources; logcat check covers X-Signature and WorkManager's own tag; D164 stops
  cloud backup of the SMS database.
- Uploads: uploadNow keeps at most one running and one waiting request (heartbeat uses APPEND_OR_REPLACE, not
  REPLACE, which would cancel itself); the loop never retries a hashMismatch row in the same run (it would loop
  forever); a missing result counts as failed; database writes are guarded by the expected status so two paths
  cannot overwrite each other; the loop moved into UploadRun / HeartbeatRun / StatusRun so it is JVM-tested.
- Upgrade: each ADD COLUMN is existence-checked; the upgrade changes no row unless you say yes to D158; the v2
  upgrade is never edited once installed.
- Checks added: UploadRun / HeartbeatRun / StatusRun tests, registration re-runs and post-registration upload,
  rule 2 / rule 3 / rule 6 tests, listInbox mapping, the 30 s refresh, logout order, two-quick-uploads manual
  check, the PowerShell form of the Gradle test command.

## 9. Second review changes (2026-10-30)

- Scope: the foreground-notification option is removed from D149 (out of Scope); parser-rules uses the existing
  Store.getParserRules (no Store or table change); WorkManager's transitive dependencies and merged boot receiver
  stated; the Gradle line already in the file still needs your yes.
- Key and logs: bridge errors carry fixed codes only (no exception message to Dart); Dart maps gateway and
  platform errors to codes, no print / debugPrint / log; NoLoggingTest also checks System.out/err, print(,
  result.error with .message and private-key .encoded; parser-rules added to logging_test.ts; the signature
  fixture uses a throwaway JVM key and a made-up body; make_session.ts prints no env values.
- Uploads: uploadNow's check + enqueue under one process lock; expedited fallback policy named; worker verdicts
  mapped to WorkManager results; heartbeat queueCount from the database only (sending rows were counted twice);
  D167 (hashMismatch retried every run) and D168 (clear revoked before uploadNow) added.
- Upgrade / data: the upgrade's single transaction stated; an unknown verifyStatus or a missing sms-status result
  leaves the row unchanged instead of failing the batch; claim amounts kept as Long.
- Checks: rows added for the 10-minute clock edge, force-stop (no check), upload worker setup, heartbeat
  re-scheduling, status refresh triggers, rules 1 / 4 / 5, NativeSmsUploader wiring and pingServer, make_session
  amount parsing; logout_offline_test renamed to logout_test to match section 1.
- CLAUDE.md: make_session.ts parses money as a string into poisha (no float) and uses the Store (no SQL);
  apps/mobile vs app/ noted (D169); make_session's backend dependency noted (D170); D163 moved into order.

## 10. Third review changes (2026-10-30)

- Uploads: a request waiting out a long retry backoff is replaced (it is not running), so new SMS and "internet
  back" upload now; the worker clears its "sending" ids in a finally block, so a stopped run leaves no row stuck
  as sending; ServerClient does not follow redirects (signed headers and body cannot go to another address).
- Data separation: D171 - merchant B signing in on the same phone could see merchant A's SMS and upload SMS
  caught after A's logout under B. Needs your decision; nothing is built for it without one.
- Checks: rows for the backoff replace and the stuck-"sending" case; manual check 8 notes that `adb root` needs a
  non-Play emulator image (with a by-hand alternative).
- Confirmed, no change: cleartext to 10.0.2.2 is already allowed in debug only (D172); no foreground service,
  push, extra library or server table anywhere in the plan; the upgrade still only adds columns.
