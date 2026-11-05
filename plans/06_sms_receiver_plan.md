# Plan 06 - SMS receiver, parser and offline storage

Spec: specs/06_sms_receiver.md (builds on specs 01-05)
Status found: specs 01-05 are built (analyze clean, 186 Dart tests pass, debug APK builds). There are no Kotlin
tests yet (app/android/app/src/test does not exist) and build.gradle.kts has no dependencies block.

Decisions carried over
- D1 = A: "strings.dart" means app/lib/l10n/app_bn.arb.
- The design reference is the root file "BDPay SMS Verifier.html" (its SMS lab and sample SMS texts are used).

Decisions taken (2026-10-29): D10 = A, D11 = yes, D12 = yes, D13 = B, D14 = yes, D15 = B (all 4 fixes),
D16 = both columns, D17 = NOT approved (no allowBackup change; the SMS database stays in Android Auto Backup).

Decisions needed before execution
- D10. **Kotlin unit tests cannot read the rules file with org.json.** Android's org.json lives in android.jar, which is
  only stubs in JVM unit tests ("Method ... not mocked"). Options:
  A (recommended) a small JSON reader in Kotlin (~80 lines, only what parser_rules.json uses: objects, arrays, strings,
  integers), used by the app and the tests, so the tests use the real file;
  B add testImplementation("org.json:json:...") - a second new Gradle library;
  C tests build the rules by hand - then they don't prove the real file works.
- D11. **The JUnit dependency is not "already in a new Flutter project".** build.gradle.kts has no dependencies at all.
  Plan: add `testImplementation("junit:junit:4.13.2")`. Gradle downloads it from Maven Central into its cache the first
  time `gradlew :app:testDebugUnitTest` runs. That changes installed software (the Gradle cache), so I need your yes.
- D12. **Native state the app cannot read back.** Monitoring and the enabled operators are saved in native preferences,
  but getHealth() returns neither, and the Dart SettingsRepository is still the in-memory mock (it resets on every
  launch). After a restart the app would show "all operators on / monitoring on" while the receiver still ignores
  Upay. The "করেছি" checkbox (rule 7) also needs a place to be saved. Proposal (contract change):
  - getHealth() also returns monitoring, enabledOperators and autoStartConfirmed; new method setAutoStartConfirmed(bool).
  - DeviceHealth gets maker (String?) and autoStartConfirmed (bool), with defaults so earlier code keeps compiling.
  - DeviceHealthRepository gets openAppSettings() and setAutoStartConfirmed(bool); the mock implements both.
  - At start the device repository copies the native operator set into SettingsRepository once; after that every
    change goes app -> native.
- D13. **The mock uploader would write "verified" into the phone database.** CLAUDE.md: "Never mark anything verified on
  the device". Spec 01's mock did that in memory only; now it would be stored on disk and survive into spec 13. Options:
  A keep spec 01 behaviour exactly (verified written, marked MOCK);
  B (recommended) the mock sets sync_status sent + server_code 200 but leaves verify_status pending. Only the server
  will ever set verified. Downside: today's verified total on হোম stays ৳ 0.00 with real SMS until spec 13.
- D14. **Earlier files the spec doesn't list but this step can't work without** (same pattern as D2/D3/D5/D6):
  - app/lib/shell/app_shell.dart: the পরীক্ষা tab shows DevLabScreen instead of the placeholder.
  - app/lib/widgets/transaction_card.dart and app/lib/features/queue/widgets/queue_card.dart: show "অজানা ফরম্যাট"
    instead of the TrxID when parseFailed (rule 2 says "the card shows").
  - app/lib/features/home/home_summary.dart: healthProblemCount also counts the auto-start row (rule 7).
  - app/lib/data/mock/mock_transaction_repository.dart: its send logic moves to MockSmsUploader ("moves here"), same
    behaviour, so the earlier tests don't change.
  - app/android/app/src/main/kotlin/com/bdpay/verifier/MainActivity.kt: registers SmsBridge and returns the permission
    result.
  - app/lib/domain/models/device_health.dart, device_health_repository.dart, mock_device_health_repository.dart (only
    if D12 is approved).
- D15. **Rule patterns that drop or mislabel real payments** (see section 4 for details). Options:
  A write the starting rules exactly as the spec says;
  B (recommended) same rules with three small fixes: (1) before matching, every Unicode space (NBSP etc.) becomes a
  normal space, on both sides, like the Bangla digits; (2) the ASCII ignore words only match as whole words
  ("(?<![a-z])(otp|pin|offer|cashback)(?![a-z])", so "shopping" no longer drops a payment); (3) reference only after
  "Ref" as a whole word, so "Refund" doesn't give reference "und"; (4) add the Bangla words "ওটিপি" and "পিন" to
  ignore (the spec has "কোড" but not these, so a Bangla OTP that also contained "পেয়েছেন" would be stored).
- D16. **Dev-lab SMS go into the real inbox.** simulateIncoming uses the same store, so a fake "You have received
  Tk 5,000" typed in the lab becomes a normal queued row and, from spec 13, would be uploaded like a real payment.
  Anyone holding the merchant's phone could use it to fake a payment. Proposal: add a column `source TEXT NOT NULL
  DEFAULT 'sms'` ('sms' | 'simulated') now (adding it later needs a database migration on every phone); spec 13 must
  never upload simulated rows as real. No new UI for it in this spec (a tag on the cards would be outside Scope).
  In the same change, add
  `operator TEXT NOT NULL` (set by the filter when it keeps the SMS), so a stored payment still has its operator if a
  later rules file drops a sender (section 5, item 9). Approve both, one, or keep the table exactly as written.
- D17. **Android backs up the SMS database to the cloud by default.** The manifest has no android:allowBackup, so it is
  true: Android Auto Backup copies app databases, including sms_inbox with every SMS body, to the user's Google Drive.
  That moves SMS off the phone without anyone asking. Proposal: add `android:allowBackup="false"` to <application>.
  This is a manifest change beyond "the permissions and receiver", so it needs your yes.

## 1. Files

### New files - Android (app/android/app/src/main/)
- kotlin/com/bdpay/verifier/ParserRules.kt - loads parser_rules.json (D10 reader), compiles patterns with IGNORE_CASE,
  normalizeBody() (Bangla digits -> English; plus spaces if D15 = B), operatorForSender() (trim + lower case).
- kotlin/com/bdpay/verifier/SmsFilter.kt - the 6-step keep rule in fixed order; KeepResult enum (wire names = the 7
  results); dedupe hash SHA-256(sender + "|" + body); joinParts() (pure: parts of one broadcast -> one body per sender,
  in order). Depends only on two interfaces (FilterSettings, InboxWriter), so it runs in JVM tests.
- kotlin/com/bdpay/verifier/SmsStore.kt - SQLiteOpenHelper with sms_inbox exactly as in the spec (+ source if D16);
  insertIfNew() (UNIQUE dedupe_hash -> duplicate), listInbox() newest first, updateSync(); no delete method. Every
  query uses ContentValues / bound "?" arguments, never SQL built from SMS text (the body is untrusted: no SQL
  injection, and SQLite error messages never contain the body).
- kotlin/com/bdpay/verifier/NativePrefs.kt - SharedPreferences: monitoring, enabled operators (defaults: on, all four),
  autoStartConfirmed (D12). Implements FilterSettings.
- kotlin/com/bdpay/verifier/SmsReceiver.kt - manifest receiver: getMessagesFromIntent, joinParts, SMSC timestamp
  (UTC ms), SIM slot via SubscriptionManager (unknown when READ_PHONE_STATE is denied or not found), goAsync + a
  single background thread, filter -> store -> notify SmsBridge. Logs nothing.
- kotlin/com/bdpay/verifier/SmsBridge.kt - MethodChannel "bdpay/sms" (all methods in the spec) and EventChannel
  "bdpay/sms/events" ("inbox", "online", "offline"; network callback on ACCESS_NETWORK_STATE). simulateIncoming calls the
  same SmsFilter + SmsStore as the receiver. Events are posted on the main thread.
- kotlin/com/bdpay/verifier/DeviceChecks.kt - RECEIVE_SMS granted, isIgnoringBatteryOptimizations, internet, maker
  (Build.MANUFACTURER, lower case), battery-exemption intent, app-settings intent.
- res/raw/parser_rules.json - the one rules file: a JSON array, one object per operator, each with the spec fields and
  "note": "SAMPLE - verify with real SMS" (see section 5, item 1).

### New files - Android tests (app/android/app/src/test/kotlin/com/bdpay/verifier/)
- SmsFilterTest.kt - the 8 keep-rule cases from the criteria (real rules file, fake settings and fake inbox), plus:
  nothing written for blocked / notIncoming / senderNotTrusted, order (monitoringOff beats senderNotTrusted).
- SmsPartsTest.kt - joining 3 parts gives the full body; two senders in one broadcast stay separate.
- ParserRulesTest.kt - the file loads, has the 4 operators, every pattern compiles, no pattern contains "(?".

### New files - Dart (app/lib/)
- domain/parser/parser_rule.dart - ParserRule (immutable) + parseRules(String json); patterns compiled caseSensitive: false.
- domain/parser/parse_sms.dart - ParsedSms, ParseError (unknownSender, noTrxId, noAmount), parseSms(), pure
  amountTextToPoisha() (int math only), normalizeSmsBody().
- domain/keep_result.dart - KeepResult enum (wire names = Kotlin results) + Bangla label for the lab.
- data/device/sms_channel.dart - the only Dart file that knows the channel names; typed wrappers + event stream.
- data/device/inbox_row.dart - one sms_inbox row (from the channel map), typed.
- data/device/device_health_repository.dart - reads getHealth() at start, on resume (AppLifecycleListener from the Flutter
  SDK) and on online/offline events; lastSmsAt from the newest row; setOnline(false) = developer "offline" override;
  pingServer stays mock ("MOCK - replaced by the server in spec 13").
- data/device/device_transaction_repository.dart - rows -> SmsTransaction via parseSms (parseFailed rows: trxId "—",
  amount 0); refresh on "inbox"; retry / retryAllPending through SmsUploader; autoSend for rows that appear after the
  first load; pushes enabledOperators to native on change; review() always returns notAllowed (the device never
  writes a review decision; see section 5, item 8).
- domain/repositories/dev_lab_repository.dart - DevLabRepository interface: parserRules() and simulateIncoming(sender,
  body, simSlot) -> KeepResult. CLAUDE.md: screens read data only through repository interfaces, so the lab never
  touches the channel itself.
- data/device/device_dev_lab_repository.dart - the channel implementation of DevLabRepository.
- data/mock/mock_dev_lab_repository.dart - test implementation (rules from the real file, results set by the test).
- data/upload/sms_uploader.dart - SmsUploader interface (upload one transaction -> UploadResult). The uploader only
  decides the result; the repository writes it back (section 5, item 19).
- data/upload/mock_sms_uploader.dart - spec 01 send logic (700 ms, online -> sent, offline -> failed + 1 retry; verify
  per D13). "MOCK - replaced by the server in spec 13".
- data/device/device_providers.dart - smsChannelProvider, parserRulesProvider and devLabRepositoryProvider (kept out of
  providers.dart except the switch itself).
- features/dev_lab/dev_lab_screen.dart - the পরীক্ষা tab: info card, template chips, sender / SMS text / SIM fields,
  "পার্স করে দেখুন", "⚡ অ্যাপে পাঠান" and the result line. The two text fields set enableIMEPersonalizedLearning: false,
  enableSuggestions: false and autocorrect: false, so the keyboard app does not learn (save) pasted SMS / OTP text.
- features/dev_lab/dev_lab_templates.dart - the sample SMS texts (test data, not UI text): 4 reference samples, Bangla
  bKash, fake sender, OTP, Send Money, HTML injection.
- features/dev_lab/widgets/parse_result_card.dart - operator, TrxID, amount, payer, errors; all as plain Text.
- features/home/widgets/auto_start_row.dart - the rule 7 row: hint, force-stop line, "সেটিং খুলুন", "করেছি" checkbox
  (checkbox colours from AppColors).

### New files - Dart tests (app/test/)
- domain/parser/parse_sms_test.dart - reads android/app/src/main/res/raw/parser_rules.json from disk (no copy).
- domain/parser/amount_test.dart - the 4 amount cases + bad input.
- data/device/device_transaction_repository_test.dart - fake channel (TestDefaultBinaryMessengerBinding, Flutter SDK).
- data/device/device_health_repository_test.dart - fake channel.
- data/upload/mock_sms_uploader_test.dart - online / offline results, updateSync arguments.
- features/dev_lab/dev_lab_screen_test.dart - widget tests with a fake channel.
- features/home/auto_start_row_test.dart - shown only for the listed makers, counts as a problem until "করেছি".
- domain/keep_result_test.dart - all 7 wire names round-trip and each has its Bangla text.
- widgets/transaction_card_parse_failed_test.dart - a parseFailed transaction shows "অজানা ফরম্যাট" and ৳ 0.00 (new
  file; the spec 01 widgets_test.dart is not touched).

### Changed earlier files
- [CHANGED 01] app/lib/domain/models/sms_transaction.dart - simSlot (default SimSlot.unknown) and parseFailed (default
  false), so every earlier constructor still compiles. (Allowed)
- [CHANGED 01] app/lib/data/providers.dart - transaction and health providers return the device repositories. (Allowed)
- [CHANGED 02] app/lib/features/home/widgets/health_card.dart - adds AutoStartRow for the listed makers. (Allowed)
- [CHANGED 01] app/android/app/src/main/AndroidManifest.xml - the 5 permissions; SmsReceiver with
  android:exported="true", android:permission="android.permission.BROADCAST_SMS" (only the system may send it) and
  the SMS_RECEIVED intent filter. No READ_SMS. (Allowed)
- [CHANGED 01] app/lib/l10n/app_bn.arb + the 2 generated files - new strings. (Allowed)
- [CHANGED, needs D11] app/android/app/build.gradle.kts - `dependencies { testImplementation("junit:junit:4.13.2") }`.
- [CHANGED, needs D14] app_shell.dart, transaction_card.dart, queue_card.dart, home_summary.dart,
  mock_transaction_repository.dart (constructor and behaviour unchanged, so earlier tests that build it still pass),
  MainActivity.kt.
- [CHANGED, needs D17] AndroidManifest.xml: android:allowBackup="false" on <application>.
- [CHANGED, needs D12] device_health.dart, device_health_repository.dart, mock_device_health_repository.dart.

### Not changed (on purpose)
- Every earlier test file and helper: they already override the transaction and health providers with mocks
  (checked: no test uses the real providers), so they never touch the channel.
- SettingsRepository stays the in-memory mock (persisting settings is not in this spec).
- pubspec.yaml: no new Dart packages.

## 2. Order of work

0. Baseline: flutter analyze, flutter test (186). Get your answers on D10-D17.
1. Kotlin, pure part first: build.gradle.kts JUnit (D11), parser_rules.json, ParserRules.kt, SmsFilter.kt (with
   joinParts), then SmsFilterTest / SmsPartsTest / ParserRulesTest.
   `cd app/android && ./gradlew :app:testDebugUnitTest` until green. (If Gradle does not pick up src/test/kotlin,
   the tests go in src/test/java; Kotlin files compile there too.)
2. Kotlin store and receiver: SmsStore.kt, NativePrefs.kt, SmsReceiver.kt, DeviceChecks.kt, manifest.
   gradle tests again + `flutter build apk --debug` (compiles the Kotlin).
3. Channel: SmsBridge.kt + MainActivity.kt registration. flutter build apk --debug.
4. Dart parser: parser_rule.dart, parse_sms.dart + parse_sms_test / amount_test (real rules file). analyze; test.
5. Model changes: SmsTransaction fields; DeviceHealth fields (D12). analyze; full test (186 still green).
6. Upload: sms_uploader.dart, mock_sms_uploader.dart; MockTransactionRepository uses it (D14). full test.
7. Dart device layer: sms_channel.dart, inbox_row.dart, both device repositories, device_providers.dart + their tests.
8. providers.dart switch. analyze; full test (earlier tests must still pass unchanged).
9. ARB strings; health card AutoStartRow + healthProblemCount; "অজানা ফরম্যাট" on the two cards. analyze; test.
10. DevLabRepository (interface, device, mock), dev lab screen + templates + shell tab (D14) + dev_lab_screen_test.
    analyze; test.
11. Final: flutter analyze, flutter test, gradlew test, flutter build apk --debug, the searches in section 3.
12. You run the emulator checks with the commands in section 3.

## 3. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| flutter analyze: no issues | "No issues found!" |
| parseSms: bKash reference sample -> TrxID 9K48X7Z2, 125000, payer 01712345678 | parse_sms_test (real rules file) |
| parseSms: Nagad sample -> 71B99AA2, 250000, 01812345678 | parse_sms_test |
| parseSms: Rocket sample -> 24010200123, 150000, 017123456789 | parse_sms_test |
| parseSms: Upay sample -> 4UP82910, 80000, 01711223344 | parse_sms_test |
| Bangla bKash sample -> amount 125000 (and payer from the "থেকে" form) | parse_sms_test |
| "৳ ১,২৫০.০০" -> 125000 | parse_sms_test |
| Amount text: "1,250.50" 125050, "1,250.5" 125050, "1,250" 125000, "0.5" 50 | amount_test |
| No TrxID -> ok false with an error | parse_sms_test (errors contains noTrxId) |
| Kotlin SmsFilter: stored, duplicate, monitoringOff, senderNotTrusted ("01799999999"), operatorOff, blocked (OTP), notIncoming (Send Money), " BKASH " trusted | SmsFilterTest: `cd app/android && ./gradlew :app:testDebugUnitTest` (PowerShell: `.\gradlew.bat :app:testDebugUnitTest`) |
| Kotlin: joining 3 parts gives the full body | SmsPartsTest |
| flutter test in full (earlier tests on the mocks) | full `flutter test`; no earlier test file changed |
| flutter build apk --debug | exits 0, app-debug.apk exists |
| Emulator 1: Rocket SMS appears in লেনদেন within 2 s | you, commands below |
| Emulator 2: SMS while the app is swiped away is there on open | you, commands below |
| Emulator 3: SMS after a restart, before opening, is there on open | you, commands below |
| Emulator 4: the same SMS again -> no second row | you, commands below |
| Emulator 5: OTP from 16216 -> nothing new | you, commands below |
| Dev lab: "⚠ ভুয়া এসএমএস" -> "প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি" | dev_lab_screen_test (fake channel) + you on the emulator (real filter) |
| Dev lab: "⚠ OTP" -> "OTP/অফার — নেওয়া হয়নি" | dev_lab_screen_test + emulator |
| Dev lab: "⚠ HTML ইনজেকশন" stored, detail shows the tag as plain text | dev_lab_screen_test + emulator (detail sheet: "মূল এসএমএস" box shows `<img src=x onerror=alert(1)>` literally) |
| (Rule 6) Info card texts; template chips: 4 operators, Bangla bKash, fake, OTP, outgoing, HTML | dev_lab_screen_test |
| (Rule 6) "পার্স করে দেখুন" shows operator, TrxID, amount, payer, errors | dev_lab_screen_test (bKash sample and a no-TrxID text) |
| (Rule 6) Every keep result has its Bangla text; outgoing template -> "টাকা গ্রহণের এসএমএস নয় — নেওয়া হয়নি" | keep_result_test + dev_lab_screen_test + emulator |

Rules and edge cases (not listed as criteria, checked too)

| Rule | Check |
|---|---|
| Nothing written for monitoringOff / senderNotTrusted / operatorOff / blocked / notIncoming | SmsFilterTest: the fake inbox stays empty after each |
| Rules file missing or broken -> nothing is written (fails closed) | SmsFilterTest with an empty rule list -> senderNotTrusted, inbox empty |
| 3-part SMS on a real device path | emulator, optional: the long command under "Emulator commands" shows one row whose "মূল এসএমএস" is the full text |
| received_at_ms is the SMS's own time, UTC | review (SmsMessage.timestampMillis) + device_transaction_repository_test (ms -> UTC DateTime) |
| SIM slot from the subscription; unknown when denied / not found | review of SmsReceiver + device_transaction_repository_test (sim_slot "sim2" -> SimSlot.sim2, missing -> unknown) |
| lastSmsAt = newest row's time | device_health_repository_test |
| Auto-start row shows "অ্যাপ জোর করে বন্ধ করবেন না" | auto_start_row_test |
| An OTP from "bKash" never reaches disk | SmsFilterTest |
| Same SMS twice -> one row | SmsFilterTest (fake inbox) + emulator 4 (real SQLite) |
| Parse failure -> row shown, queued, "অজানা ফরম্যাট", amount ৳ 0.00 | device_transaction_repository_test + a widget test on TransactionCard |
| List refresh on "inbox" event | device_transaction_repository_test (fake event -> new list) |
| autoSend: a new row is sent at once | device_transaction_repository_test |
| retry -> MockSmsUploader -> updateSync with the right values | mock_sms_uploader_test |
| Health re-read on start, resume, online/offline; fix buttons re-read | device_health_repository_test |
| Monitoring / operator change calls setMonitoring / setEnabledOperators | device repository tests (recorded channel calls) |
| Auto-start row only for the 10 makers; a problem until "করেছি" | auto_start_row_test |
| Patterns have no inline flags; rules file has the 4 operators | ParserRulesTest + parse_sms_test |
| No SMS body, sender or TrxID in any log | search: no Log./println/print/debugPrint in the new Kotlin and Dart code; emulator: `adb logcat -d \| findstr 24010200123` prints nothing |
| No READ_SMS, no inbox reading | search: "READ_SMS" and "content://sms" appear nowhere in app/android and lib |
| Receiver only accepts system broadcasts | search: manifest receiver has android:permission="android.permission.BROADCAST_SMS" |
| No cloud backup of the SMS database (D17) | search: android:allowBackup="false" in the manifest |
| SQL never built from SMS text | review + search: no string concatenation into execSQL / rawQuery in SmsStore.kt |
| Lab text fields don't feed the keyboard's learning | dev_lab_screen_test reads enableIMEPersonalizedLearning == false on both fields |
| No error text carries SMS content | review: Kotlin catch blocks log nothing and channel errors use fixed codes; Dart uses int.tryParse (int.parse's FormatException would print the amount text) and ParseError codes |
| The lab reads data only through DevLabRepository | search: no "bdpay/sms" or SmsChannel import in lib/features |
| Device never writes "verified" (D13 = B) or a review decision | mock_sms_uploader_test: updateSync gets verifyStatus "pending"; device_transaction_repository_test: review() -> notAllowed, no channel call |
| New files UTF-8 without BOM | search (as in spec 05) |
| Receiver doesn't block | review: goAsync + background executor in SmsReceiver |
| No double for money | search (as in spec 01) |

### Emulator commands (run from D:\BDPay\app; work in PowerShell and Git Bash)

Setup once:
```
adb devices
flutter run -d emulator-5554
```
In the app: sign in (demo@bdpay.test / 123456), on হোম tap "ঠিক করুন" on the SMS permission row and allow.
(Alternative: `adb shell pm grant com.bdpay.verifier android.permission.RECEIVE_SMS`.) Stop `flutter run` with q;
the app stays installed.

1. Arrives within 2 seconds (app open on লেনদেন):
```
adb emu sms send 16216 "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123"
```
2. App swiped away:
```
adb shell input keyevent KEYCODE_HOME
```
Swipe BDPay away in Recents by hand (or `adb shell am kill com.bdpay.verifier`; `adb shell pidof com.bdpay.verifier`
prints nothing when it is gone). Do not use "Force stop". Then:
```
adb emu sms send 16216 "Tk2,000.00 received from 017123456780 for A/C: 019876543211. Fee Tk0.00, Balance Tk7,600.00. TxnId: 24010200124"
adb shell monkey -p com.bdpay.verifier -c android.intent.category.LAUNCHER 1
```
3. After a restart, before opening:
```
adb reboot
adb wait-for-device
adb shell getprop sys.boot_completed
```
(repeat the last line until it prints 1)
```
adb emu sms send 16216 "Tk3,000.00 received from 017123456781 for A/C: 019876543211. Fee Tk0.00, Balance Tk10,600.00. TxnId: 24010200125"
adb shell monkey -p com.bdpay.verifier -c android.intent.category.LAUNCHER 1
```
4. Same SMS again (the count "{n} টি লেনদেন" must not change):
```
adb emu sms send 16216 "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123"
```
5. OTP:
```
adb emu sms send 16216 "Your OTP is 123456"
```
Optional, 3-part SMS (over 300 characters, so the emulator sends it in parts; it must show as ONE row with the whole
text in "মূল এসএমএস"):
```
adb emu sms send 16216 "Tk4,000.00 received from 017123456782 for A/C: 019876543211. Fee Tk0.00, Balance Tk14,600.00. This line is padding so the message is longer than three hundred characters and the emulator has to split it into several parts before delivery. More padding text here to be sure it is long enough. TxnId: 24010200126"
```
Privacy check after all five (must print nothing):
```
adb logcat -d | findstr 24010200123
```
(Git Bash: `adb logcat -d | grep 24010200123`)

Note: the app is signed in only through the spec 05 mock, which forgets the sign-in when the process dies. After steps
2 and 3 you will see the login screen first; sign in as demo again and the stored SMS are there (the SMS store is
native and does not depend on sign-in).

## 4. Regex: Kotlin (java.util.regex) vs Dart (JavaScript-style RegExp)

Who uses what: Kotlin only uses senders, ignore and incoming (the keep decision). Dart uses every pattern (parsing).
Kotlin compiles with RegexOption.IGNORE_CASE; Dart with caseSensitive: false; neither with unicode mode.

Result for the spec's starting patterns: **none of them gives a different keep decision in Kotlin and Dart today.**
The differences below are real, but they only bite with some inputs or future rules:

1. **`\s`.** Java: ASCII only (space, \t, \n, \x0B, \f, \r). Dart: also NBSP (U+00A0), U+2000-U+200A, U+202F, U+205F,
   U+3000, U+FEFF, U+2028/2029. Used only in Dart-side patterns now (trx, amount, payer, balance, reference), so no
   keep difference; but "Tk\u00A01,250.00" parses in Dart, and if a future incoming/ignore rule uses `\s`, Kotlin and
   Dart would disagree on an SMS with NBSP. Also, a literal space in "you have received" doesn't match NBSP in either.
   Fix proposed in D15 (1): turn every Unicode space into ' ' before matching, on both sides.
2. **Case folding.** Java IGNORE_CASE without UNICODE_CASE folds ASCII only; Dart folds Unicode. Same for ASCII and
   for Bangla (no case). Differs only for letters like Kelvin "K" (U+212A) or long s (U+017F). No action; noted in the
   rules "note" so nobody adds such letters.
3. **`\b` (not used yet).** Java treats Unicode letters as word characters for `\b`; Dart only [A-Za-z0-9_]. So `\bpin\b`
   next to a Bangla letter differs. D15 uses lookarounds with explicit ASCII classes instead, which behave the same.
4. **`.` (not used yet).** Java's `.` also refuses U+0085; Dart's doesn't. Rule-writing note: don't use `.` as a wildcard.
5. **Payer groups.** Same in both, but `(?:from|Sender:?)\s*(01...)|(01...)\s*থেকে` has TWO capture groups: the Bangla
   form fills group 2, not group 1. Dart takes the first non-empty group (section 5, item 2).
6. **Bangla words in patterns** ("পেয়েছেন", "কোড", "অফার", "ক্যাশব্যাক", "থেকে"). Both compare code points with no
   normalization, so they behave the same; but both miss an SMS that writes "য়" as one code point (U+09DF) while the
   rules file uses "য" + nukta (U+09AF U+09BC), or the other way round (section 5, item 4).
7. Lookbehind `(?<!...)` (used only if D15 = B) works the same in both. `[A-Z0-9]` with ignore-case also matches
   lower case in both; the TrxID is upper-cased after matching.

## 5. Unclear or wrong in the spec

1. **"A JSON array" vs "a top-level note field".** An array has no top-level fields. Plan: keep the array and put
   "note": "SAMPLE - verify with real SMS" (plus the regex rules from section 4) in every operator object. The shared
   patterns ("all") are repeated in each object, since an array has no shared part.
2. **Payer "group 1".** The spec's payer pattern puts the Bangla form in group 2. Plan: the payer is the first non-empty
   group (both forms work); the rules note says so.
3. **Ignore words match inside other words.** "pin" blocks "shopping"/"Spin", "otp" blocks "footprint", "offer" blocks
   "offered". A blocked SMS is never stored, so a real payment would be lost without a trace. Also "Ref" matches inside
   "Refund". -> D15.
4. **Unicode forms of Bangla.** "পেয়েছেন" can be written two ways. Plan: the rules file uses the form in the spec; a
   real-phone check before release must confirm the operators' form. (Normalizing in code would need a Unicode table;
   not proposed.)
5. **Which sender goes into the dedupe hash.** " BKASH " and "bKash" would hash differently. Plan: the trimmed, lower-case
   sender + "|" + the body exactly as received.
6. **"sending" in the database.** If the app dies during a send, a row saved as "sending" would stay stuck (retry skips
   it, logout is blocked forever). Plan: "sending" lives only in memory; the database only holds queued, sent, failed.
7. **"Newly stored" for autoSend.** SMS stored while the app was closed are not "new" to a running app. Plan: autoSend
   sends rows that appear after the first load; older queued rows go with the spec 04 auto-send on internet return or
   by hand. (Background upload is spec 13.)
8. **review() on the device repository** isn't mentioned. Device rows have no claim and never become mismatch, so the
   review card never shows buttons. Plan: review() always returns notAllowed and writes nothing. Writing the spec 03
   mock decision (verified / rejected) to the phone database would break "never mark anything verified on the device";
   the real review goes to the server in spec 13.
9. **Operator of a stored row.** Dart finds it again from the sender with the current rules. Only trusted senders are
   stored, so it is always found today; but if a later rules file drops a sender, an already stored payment would have
   no operator and could not be shown. -> part of D16 (store the operator in the row).
10. **Parse errors in the lab** are shown in Bangla from ARB (ParseError -> text), not as raw codes.
11. **The force-stop text** "অ্যাপ জোর করে বন্ধ করবেন না" is shown as a second hint line on the auto-start row.
12. **Maker names.** Redmi and POCO phones report the maker "Xiaomi", so checking Build.MANUFACTURER covers them;
    Build.BRAND is checked too, to be safe.
13. **Login after the app dies.** The spec 05 auth mock is in memory, so after steps 2 and 3 of the emulator check the app
    asks for login again. Expected until the real auth (spec 13); noted under the commands.
14. **SmsStore has no JVM unit test.** SQLiteOpenHelper needs Android (Robolectric would be a new library). The real store
    is proven by emulator checks 1-4; the filter logic is tested with a fake inbox.
15. **Play Store policy.** RECEIVE_SMS and REQUEST_IGNORE_BATTERY_OPTIMIZATIONS need a policy declaration for Play
    release. Not a code issue now; noted for release.
16. **Dev-lab template texts** are SMS samples (test data) kept in a Dart const file, not ARB; chip labels and all other
    lab text are in ARB.
17. **Reference wording.** The lab buttons and info text follow the spec ("পার্স করে দেখুন", "⚡ অ্যাপে পাঠান"), not the
    reference ("টোকেন দেখুন", "⚡ পাইপলাইনে পাঠান"), because the spec wins. Field labels come from the reference
    ("এসএমএস প্রেরক হেডার (যেমন: bKash, 16247, NAGAD)", "ইনকামিং এসএমএস টেক্সট").
18. **strings.dart / reference file name.** Same as before: ARB (D1), and the root "BDPay SMS Verifier.html".
19. **"MockSmsUploader ... writes the result back with updateSync".** If the uploader itself called the channel, the
    test-only MockTransactionRepository (in memory) could not use it, and the spec says the old send logic "moves" there.
    Plan: the uploader returns the result; DeviceTransactionRepository writes it with updateSync, the mock repository
    writes it to memory. Same behaviour, one copy of the send logic.
20. **What the uploader will send (spec 13).** CLAUDE.md: the server re-parses every raw SMS and never trusts the
    device's parsed values. So the upload carries sender, raw body, received time and SIM slot; the parsed fields are
    only for showing on the phone.
21. **CLAUDE.md says the phone database is drift**; this spec says plain SQLiteOpenHelper in Kotlin (so the receiver can
    store while Flutter is not running). The current step spec wins, so no drift. Noted so CLAUDE.md can be updated.

## 6. Privacy paths (OTP, outgoing SMS, untrusted sender)

| Path | Can it reach disk or a log? | Guard |
|---|---|---|
| Untrusted sender | No | filter step 2 returns before any write; SmsFilterTest |
| OTP / PIN / promotion from a trusted sender | No | step 4 before the write; SmsFilterTest. Steps 1 and 3 (monitoring / operator off) also come first and write nothing |
| Outgoing (Send Money) from a trusted sender | No | step 5 before the write; SmsFilterTest |
| Rules file missing or broken | No | the filter fails closed (no rule = no trusted sender = nothing written) |
| Dev lab "পার্স করে দেখুন" | No | parseSms in memory only; the text stays in the text field |
| Dev lab "⚡ অ্যাপে পাঠান" | Only if the same filter keeps it | same SmsFilter as the receiver; rows marked simulated (D16) |
| Exceptions | No | Kotlin: catch, finish the broadcast, log nothing; channel errors use fixed codes with no SMS text. Dart: no int.parse / no exception message built from SMS text |
| SQLite errors / SQL injection | No | bound arguments only; an error message never contains the body |
| Keyboard learning in the dev lab | No | enableIMEPersonalizedLearning: false, no suggestions, no autocorrect |
| Bangla OTP ("ওটিপি", "পিন") that also says "পেয়েছেন" | Yes with the spec's ignore list | D15 (4) adds both words |
| logcat / print | No | no Log / println / print / debugPrint in new code (search) + the emulator logcat check |
| EventChannel | No | events carry only "inbox" / "online" / "offline", never content |
| Android Auto Backup to Google Drive | Yes today (default) | D17: android:allowBackup="false" |
| Kept SMS bodies on disk | Yes, by design (only kept money-received SMS) | plain app-private SQLite, never deleted (spec); no READ_SMS, no inbox reading |

## 7. Review log

Review 1 against spec 06 and CLAUDE.md:
- Outside Scope: no READ_SMS, no inbox reading, no foreground service, no Room, no new Dart package; the only Gradle
  line is JUnit (D11). Removed: the "পরীক্ষা" tag on simulated cards (new UI) - D16 now only adds the columns.
  Extra small files (ParserRules.kt, NativePrefs.kt, keep_result.dart, inbox_row.dart, device_providers.dart, the
  DevLabRepository files) support the listed parts and add no feature.
- Disk / log paths: all listed in section 6. Found and fixed: Android Auto Backup (new D17); the filter now fails
  closed without rules; monitoringOff / operatorOff are checked to write nothing; error texts never carry SMS
  content (int.tryParse, fixed error codes).
- Earlier files: everything outside the spec's list is under D11, D12, D14 or D17; MockTransactionRepository keeps its
  constructor so no earlier test changes.
- Criteria: all had a check. Added checks for the 3-part SMS on the emulator, received time, SIM slot mapping,
  lastSmsAt, the force-stop text, allowBackup, BOM.
- CLAUDE.md: device review() no longer writes verified/rejected (always notAllowed); D13 = B recommended for the
  uploader; the lab now goes through a repository interface (DevLabRepository) instead of the channel; drift vs
  SQLiteOpenHelper noted (spec wins).

Review 2 (same five questions, looking for what review 1 missed):
- Outside Scope: nothing new found.
- Disk / log paths, new: SQL must use bound arguments (SMS body is untrusted; also keeps SQLite errors free of SMS
  text); the dev-lab text fields would let the keyboard app learn pasted OTP text -> IME learning off; the spec's
  ignore list has no Bangla "ওটিপি" / "পিন" -> added to D15 as fix (4).
- Earlier files: the parse-failed card test is now a new file, so spec 01's widgets_test.dart stays untouched. The
  uploader/write-back split (section 5, item 19) is what lets the mock repository keep its constructor.
- Criteria: rule 6 had parts with no check (info texts, all template chips, the parse card, the 7 result texts, the
  outgoing template) -> added rows and keep_result_test.dart.
- CLAUDE.md: checkbox colours from AppColors; the upload carries the raw SMS, not parsed values (section 5, item 20).

## 8. Execution log (2026-10-29)

- Done in plan order: Kotlin filter + rules + tests first (gradle green), then store / receiver / bridge (APK built),
  then Dart parser, models, uploader, device layer, providers switch, health row and cards, dev lab.
- D17 was not approved: android:allowBackup is not set, so Android Auto Backup still covers the SMS database.
- One small extra Kotlin file, SmsPipeline.kt: the single filter -> store -> notify path shared by SmsReceiver and
  simulateIncoming (rule 6: "runs the SAME filter and store path"), with the one background thread.
- The sms_inbox CHECK constraints refuse "sending" and unknown values, so a stuck "sending" row cannot be stored.
- app_shell.dart: with every tab now having a screen, the PlaceholderPage fallback became unreachable (analyzer
  warning) and was removed from the switch. placeholder_page.dart itself is left in place, unused.
- Results: flutter analyze clean; flutter test 236 passed (201 before this step's Dart work started, 186 at the
  start); gradle testDebugUnitTest 25 passed; flutter build apk --debug built.
