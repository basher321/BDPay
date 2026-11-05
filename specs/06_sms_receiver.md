# 06 SMS receiver, parser and offline storage

Purpose
Catch every MFS "money received" SMS on the merchant's Android phone, even when the app
is closed, keep it safely on the phone, and show it in the app. Never keep personal SMS,
OTPs or outgoing-payment SMS. After this spec the app shows real SMS instead of sample data.
Sending to the server stays mocked until spec 13.

Scope
- Android native code (Kotlin) in app/android/app/src/main/kotlin/com/bdpay/verifier/:
  - SmsReceiver: a manifest-registered receiver for SMS_RECEIVED.
  - SmsFilter: decides keep or ignore, using the rules file.
  - SmsStore: a local SQLite table (plain SQLiteOpenHelper, no Room).
  - SmsBridge: the Flutter MethodChannel and EventChannel.
  - DeviceChecks: SMS permission, battery optimization, internet, phone maker.
- One parser rules file: app/android/app/src/main/res/raw/parser_rules.json.
  Kotlin reads it directly; Dart gets it through the channel. There is no second copy.
- Dart:
  - lib/domain/parser/: ParserRule model and a pure parseSms function.
  - lib/data/device/: DeviceTransactionRepository and DeviceHealthRepository using the channel.
  - lib/data/upload/: SmsUploader interface and MockSmsUploader (the old mock send logic moves here).
  - The পরীক্ষা (developer test lab) screen in lib/features/dev_lab/.
- Additions to earlier code, and only these:
  - SmsTransaction gets simSlot (SimSlot) and parseFailed (bool, default false).
  - providers.dart switches the app to the device repositories. The old mock repositories
    stay for tests only.
  - The health card gets one row for phone makers that block background apps (rule 7).
  - AndroidManifest.xml gets the permissions and receiver below.
  - New strings in strings.dart.
- Permissions: RECEIVE_SMS, READ_PHONE_STATE (optional, for SIM slot), ACCESS_NETWORK_STATE,
  INTERNET, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS. Do NOT add READ_SMS. Do NOT read the SMS inbox.
- No new Dart packages. No new Gradle libraries except the JUnit test dependency already in
  a new Flutter project.
- Not in scope: real server upload, background upload while the app is closed (spec 13),
  rule updates from the server (spec 13), a foreground service, iOS.

Contract
parser_rules.json: a JSON array, one object per operator:
  operator   bkash | nagad | rocket | upay
  senders    list of sender IDs, compared case-insensitive after trimming
  incoming   pattern that must match for a money-received SMS
  ignore     pattern; if it matches, the SMS is dropped (OTP, PIN, codes, promotions)
  trx        pattern, group 1 = TrxID
  amount     pattern, group 1 = amount text like 1,250.50
  payer      pattern, group 1 = payer number (optional match)
  balance    pattern, group 1 = balance text (optional match)
  reference  pattern, group 1 = reference (optional match)
  payment    pattern; if it matches, kind = payment, else kind = received
  version    integer
- Patterns are written WITHOUT inline flags such as (?i). Both Kotlin and Dart compile them
  case-insensitive. Use only regex features that work the same in Kotlin and Dart.
- Before matching, Bangla digits (০-৯) in the body are changed to English digits, on both sides.
- Starting rules (every one marked "SAMPLE - verify with real SMS" in a top-level "note" field):
  - bkash: senders [bKash, 16247]; incoming "you have received|পেয়েছেন";
    trx "TrxID\s*:?\s*([A-Z0-9]{8,12})".
  - nagad: senders [NAGAD, 16167]; incoming "money received";
    trx "TxnID\s*:?\s*([A-Z0-9]{8,12})".
  - rocket: senders [16216]; incoming "received from";
    trx "TxnId\s*:?\s*([0-9]{8,14})".
  - upay: senders [upay, 16268]; incoming "you have received";
    trx "Txn ID\s*:?\s*([A-Z0-9]{8,12})".
  - all: ignore "otp|verification code|pin|কোড|offer|অফার|cashback|ক্যাশব্যাক";
    amount "(?:Tk|৳|BDT)\s?([0-9,]+(?:\.[0-9]{1,2})?)";
    payer "(?:from|Sender:?)\s*(01[0-9]{9,10})|(01[0-9]{9,10})\s*থেকে";
    balance "Balance:?\s*Tk\s?([0-9,]+(?:\.[0-9]{1,2})?)";
    reference "Ref(?:erence)?:?\s*([A-Za-z0-9#-]+)"; payment "payment".

Keep rule (Kotlin SmsFilter, the same order every time):
  1. Monitoring is off -> ignore (reason monitoringOff).
  2. Sender is not in any rule's senders -> ignore (senderNotTrusted). Nothing is written to disk.
  3. That operator is turned off in settings -> ignore (operatorOff).
  4. Body matches ignore -> drop (blocked). Nothing is written to disk.
  5. Body does not match incoming -> ignore (notIncoming). Nothing is written to disk.
  6. Otherwise keep: write to SmsStore (stored), or duplicate if the same dedupe hash exists.
Results: stored, duplicate, monitoringOff, senderNotTrusted, operatorOff, blocked, notIncoming.

SmsStore table sms_inbox:
  id TEXT primary key (UUID), sender TEXT, body TEXT, received_at_ms INTEGER (UTC),
  sim_slot TEXT (sim1 | sim2 | unknown), dedupe_hash TEXT UNIQUE (SHA-256 of sender + "|" + body),
  sync_status TEXT default 'queued', verify_status TEXT default 'pending', retry_count INTEGER
  default 0, server_code INTEGER NULL, server_message TEXT NULL, created_at_ms INTEGER.
  Rows are never deleted by the app.

MethodChannel "bdpay/sms":
  getParserRules() -> String (the JSON file)
  listInbox() -> List<Map> (all rows, newest first)
  updateSync(id, syncStatus, verifyStatus, retryCount, serverCode, serverMessage) -> void
  simulateIncoming(sender, body, simSlot) -> String (a keep-rule result; runs the SAME filter
    and store path as the real receiver)
  setMonitoring(bool), setEnabledOperators(List<String>) -> void (saved in native preferences)
  getHealth() -> Map {smsPermission, batteryOptimizationOff, internetOnline, maker}
  requestSmsPermission() -> bool (also asks READ_PHONE_STATE; denial of that one is fine)
  requestBatteryExemption() -> void
  openAppSettings() -> void
EventChannel "bdpay/sms/events": sends "inbox" when a row is added or changed, and
  "online"/"offline" when the internet changes.

Dart parseSms(String sender, String body, List<ParserRule> rules) -> ParsedSms:
  operator, trxId (upper case), amountPoisha, payerNumber, balancePoisha, reference, kind, ok,
  errors (list). Amount text is turned into poisha with whole-number math only:
  "1,250.50" -> 125050, "1,250.5" -> 125050, "1,250" -> 125000, "0.5" -> 50. No double ever.

Functional rules
1. Receiving
   - SmsReceiver joins all message parts in one broadcast into one body, per sender, in order.
   - received_at_ms is the SMS time from the message, in UTC.
   - The SIM slot comes from the broadcast's subscription, looked up through SubscriptionManager.
     If READ_PHONE_STATE is denied or it cannot be found -> unknown.
   - The receiver works when the app is closed or the screen is off, as long as the app has been
     opened once since install.
   - The receiver finishes quickly (store on a background thread with goAsync).
2. Showing
   - DeviceTransactionRepository turns each sms_inbox row into an SmsTransaction using parseSms.
   - If parsing fails (no TrxID or no amount), the row is still shown and still queued for upload,
     with parseFailed true, trxId "—", amount 0, and the card shows "অজানা ফরম্যাট" instead of the TrxID.
     The server will parse it again with newer rules.
   - The list updates within 2 seconds of an SMS arriving (EventChannel "inbox").
3. Sending (still mocked)
   - retry and retryAllPending call SmsUploader. MockSmsUploader keeps the spec 01 behaviour
     and writes the result back with updateSync. Mark it "MOCK - replaced by the server in spec 13".
   - autoSend on: a newly stored SMS is sent right away (through the same uploader).
4. Health
   - DeviceHealthRepository reads getHealth() at start, when the app comes to the front,
     and on "online"/"offline" events.
   - "ঠিক করুন" buttons call requestSmsPermission and requestBatteryExemption, then re-read health.
   - lastSmsAt = newest row's received time.
5. Settings link
   - Turning monitoring or an operator on/off in the app also calls setMonitoring or
     setEnabledOperators, so the receiver obeys it when the app is closed.
6. Developer test lab (পরীক্ষা tab), like the reference
   - Info card: "এসএমএস পরীক্ষা (ডেভেলপার)" / "আসল টাকা ছাড়াই পার্সিং, ভুয়া এসএমএস ঠেকানো ও ডুপ্লিকেট চেক পরীক্ষা করুন।"
   - Template chips: one per operator sample, Bangla bKash, "⚠ ভুয়া এসএমএস" (trusted words from an
     untrusted number), "⚠ OTP", "⚠ টাকা পাঠানো (outgoing)", "⚠ HTML ইনজেকশন".
   - Fields: sender, SMS text, SIM (সিম ১ / সিম ২ / জানি না).
   - "পার্স করে দেখুন" shows the parseSms result card (operator, TrxID, amount, payer, errors).
   - "⚡ অ্যাপে পাঠান" calls simulateIncoming and shows the result in Bangla:
     stored "নেওয়া হয়েছে", duplicate "আগেই নেওয়া হয়েছে (ডুপ্লিকেট)", monitoringOff "মনিটরিং বন্ধ",
     senderNotTrusted "প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি", operatorOff "এই অপারেটর বন্ধ",
     blocked "OTP/অফার — নেওয়া হয়নি", notIncoming "টাকা গ্রহণের এসএমএস নয় — নেওয়া হয়নি".
7. Background-blocking phone makers
   - If maker is one of xiaomi, redmi, poco, oppo, realme, vivo, infinix, tecno, huawei, honor:
     the health card shows the row "অটোস্টার্ট চালু করুন" with hint
     "ফোনের সেটিং-এ BDPay-এর অটোস্টার্ট ও ব্যাকগ্রাউন্ড চালু রাখুন", a button "সেটিং খুলুন"
     (openAppSettings), and a checkbox "করেছি". The row counts as a problem until "করেছি" is ticked
     (the app cannot check this itself, so the merchant confirms it). Other makers: no row.

Edge cases
- A 3-part SMS arrives in one broadcast -> stored as one row with the full body.
- The same SMS delivered twice -> one row (duplicate).
- An OTP from sender "bKash" -> never written to disk.
- "Send Money Tk 500.00 to 01711000000 successful. TrxID ABC12345" from bKash -> notIncoming, not stored.
- Sender " BKASH " -> trusted (trim + case-insensitive).
- Body with Bangla digits "৳ ১,২৫০.০০" -> amount 125000.
- Body with "<img src=x onerror=alert(1)>" -> stored as plain text, shown as plain text.
- App force-stopped by the user -> Android stops the receiver until the app is opened again.
  The health card cannot detect this, so the onboarding text on the auto-start row says
  "অ্যাপ জোর করে বন্ধ করবেন না".
- Phone rebooted -> the receiver works again without opening the app (unless it was force-stopped).

Non-functional rules
- No SMS body, sender or TrxID is ever written to logcat or any log.
- The receiver never blocks: work is done off the main thread.
- parseSms and the amount conversion are pure Dart with unit tests. SmsFilter has Kotlin unit tests.
- flutter analyze reports zero issues.

Acceptance criteria
- flutter analyze: no issues.
- Dart unit tests for parseSms with the rules file:
  - each of the 4 operator samples from the reference parses ok with the right TrxID, amount and payer;
  - the Bangla bKash sample gives amount 125000;
  - amount text cases: "1,250.50" 125050, "1,250.5" 125050, "1,250" 125000, "0.5" 50;
  - a body with no TrxID gives ok false with an error.
- Kotlin unit tests for SmsFilter (cd app/android && ./gradlew :app:testDebugUnitTest):
  stored, duplicate, monitoringOff, senderNotTrusted ("01799999999"), operatorOff, blocked (OTP),
  notIncoming (Send Money), and " BKASH " trusted.
- Kotlin unit test: joining 3 parts gives the full body.
- flutter test passes in full (earlier tests use the mock repositories and still pass).
- flutter build apk --debug succeeds.
- Emulator checks (I run them; Claude Code gives me the exact commands):
  1. adb emu sms send 16216 "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123"
     -> appears in লেনদেন within 2 seconds.
  2. Swipe the app away, send a second Rocket SMS with a new TxnId, open the app -> it is there.
  3. Restart the emulator, send a third one before opening the app, then open it -> it is there.
  4. Send the same SMS again -> no second row.
  5. Send "Your OTP is 123456" from 16216 -> nothing new appears.
- Developer lab: "⚠ ভুয়া এসএমএস" shows "প্রেরক বিশ্বস্ত নয় — নেওয়া হয়নি"; "⚠ OTP" shows
  "OTP/অফার — নেওয়া হয়নি"; "⚠ HTML ইনজেকশন" is stored and its detail shows the tag as plain text.

Assumptions
- Specs 01 to 05 are done and all their tests pass.
- The sample SMS formats may differ from real ones. Real SMS will be checked on a real phone
  before release, and only parser_rules.json should need to change.
- The emulator may only accept number senders in adb emu sms send; letter senders (bKash, NAGAD)
  are tested through the developer lab, which uses the same filter and store.
