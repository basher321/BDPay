# 01 App foundation

Purpose
Create the Flutter Android app skeleton for BDPay: theme, shared widgets, data
models, a mock data layer and the bottom-navigation shell. Later specs build each
screen on this base, and the backend later replaces the mock data without any
screen changing.

Scope
- A new Flutter project in app/ (Android only, application id com.bdpay.verifier, minSdk 26).
- Theme and color tokens copied from the :root block of reference/bdpay-sms-verifier-v2.html.
- Shared widgets in lib/widgets: AppCard (normal and big), OperatorBadge, VerifyStatusChip,
  SyncStatusLabel, MoneyText, AppSwitch, AppButton (primary, outline, small), EmptyState,
  and showToast (styled like the reference toast).
- Domain models, enums and repository interfaces listed in Contract.
- Mock repositories holding the sample data listed in Contract.
- App shell: the header (logo, "BDPay SMS Verifier", subtitle "পেমেন্ট যাচাই অ্যাপ",
  online pill) and the bottom navigation. Each tab shows a placeholder with its title only.
- Packages: flutter_riverpod, intl. Font: Noto Sans Bengali (Regular, Medium, Bold) from app/assets/fonts.
- Not in scope: real screen content, SMS reading, local database, Supabase, login,
  notifications, English language.

Contract
Enums (Dart name = wire name):
- MfsOperator: bkash, nagad, rocket, upay.
  Display: bKash, Nagad, Rocket, Upay.
  Brand colors: #E2136E, #F7941D, #8C3494, #004884.
  Text colors on dark: #F0559A, #F9A940, #B565C0, #5B9BE6.
- VerifyStatus: pending, verified, mismatch, rejected.
  Labels: যাচাই বাকি, পেমেন্ট নিশ্চিত ✓, টাকা মেলেনি, বাতিল. Colors: wa, ok, er, er.
- SyncStatus: queued, sending, sent, failed.
  Labels: পাঠানো বাকি, পাঠানো হচ্ছে…, পাঠানো হয়েছে, আবার চেষ্টা হবে. Colors: wa, t3, ok, er.
- TxKind: payment, received. Labels: পেমেন্ট, টাকা গ্রহণ.
Each enum has toWire() and fromWire(String); fromWire throws on an unknown value.

Model SmsTransaction (immutable, with copyWith):
  id String, operator MfsOperator, sender String, trxId String, amountPoisha int,
  payerNumber String?, kind TxKind, verifyStatus VerifyStatus, syncStatus SyncStatus,
  receivedAt DateTime (UTC), rawBody String, reference String?, balancePoisha int?,
  serverCode int?, serverMessage String?, retryCount int (default 0).
Model DeviceHealth: smsPermission bool, batteryOptimizationOff bool, internetOnline bool,
  monitoring bool, lastSmsAt DateTime?, lastServerContactAt DateTime?.
Model AppSettings: developerMode bool, autoSend bool, enabledOperators Set<MfsOperator>,
  deviceName String.

Repository interfaces (lib/domain/repositories):
- TransactionRepository: Stream<List<SmsTransaction>> watchAll() (newest first);
  Future<void> retry(String id); Future<void> retryAllPending().
- DeviceHealthRepository: Stream<DeviceHealth> watch(); Future<void> setMonitoring(bool on);
  Future<void> setOnline(bool on) (mock only, used by developer mode).
- SettingsRepository: Stream<AppSettings> watch(); Future<void> update(AppSettings s).
Riverpod providers in lib/data/providers.dart return the mock implementations.
Screens read only the interfaces.

Helpers in lib/core:
- formatPoisha(int p): 125050 -> "৳ 1,250.50"; 0 -> "৳ 0.00"; 123456789 -> "৳ 1,234,567.89".
- dhakaClock(DateTime utc): "hh:mm AM/PM" in Asia/Dhaka (fixed UTC+6, no timezone package).
- timeAgo(DateTime utc, DateTime now): under 60 s "এইমাত্র", then "N মিনিট আগে",
  "N ঘণ্টা আগে", "N দিন আগে".

Sample data (receivedAt relative to app start):
1. bkash, TrxID 9K48X7Z2, 125000, payer 01712345678, payment, verified, sent, 5 min ago,
   reference ORD-101, balance 1534050, code 200, message "অর্ডারের সাথে মিলেছে".
2. nagad, 71B99AA2, 250000, 01812345678, received, verified, sent, 35 min ago, code 200.
3. rocket, 24010200123, 150000, 017123456789, received, pending, failed, 50 min ago,
   retryCount 2, message "নেটওয়ার্ক সংযোগ নেই".
4. upay, 4UP82910, 80000, 01711223344, received, pending, queued, 95 min ago.
5. bkash, 8H22K9P1, 43000, 01911002200, payment, mismatch, sent, 140 min ago,
   code 409, message "অর্ডারের টাকার সাথে মেলেনি".
Use the raw SMS texts from the reference file for each item.

Functional rules
- Color tokens: em #00D09C, bg #080D1A, sf #10192D, cd #17233D, bd #233558,
  t1 #F8FAFC, t2 #B4C0D3, t3 #8A9AB3, ok #10B981, wa #F59E0B, er #EF4444, in #38BDF8.
  Radius: card 14, big card 18, button 12, small button 8.
- Bottom tabs in this order: হোম, লেনদেন, পাঠানো বাকি, সেটিংস.
  A fifth tab পরীক্ষা appears before সেটিংস only when developerMode is true.
  Turning developer mode off while on পরীক্ষা returns to হোম.
- The active tab shows the emerald pill (56 x 30) behind its icon, like the reference.
- The পাঠানো বাকি tab shows an amber badge with the count of queued + failed items. Hide it when 0.
- The online pill reads DeviceHealth.internetOnline: green "অনলাইন" or red "অফলাইন".
- Mock retry(): set sending; after 700 ms, if online, set sent and keep the server result from
  a simulated response (amount > 0 -> verified, code 200); if offline, set failed and add 1 to
  retryCount. Mark this code with a comment: "MOCK - replaced by the server in spec 13".
- Money is int poisha everywhere. No double in any money field or calculation.

Edge cases
- Empty transaction list: EmptyState renders an icon, a title and a hint.
- formatPoisha with a negative value throws an ArgumentError.
- Long TrxID, sender or message text is cut with an ellipsis and never overflows the row.
- fromWire with an unknown string throws, so bad data from the server fails loudly.

Non-functional rules
- flutter analyze reports zero issues.
- No network calls in this spec.
- Widgets hold no business logic. Logic lives in repositories and helpers.

Acceptance criteria
- flutter analyze: no issues.
- flutter test passes, with tests for: every formatPoisha example above; formatPoisha
  negative throws; timeAgo at 30 s, 5 min, 2 h, 3 days; toWire/fromWire round trip for
  every enum value; fromWire unknown throws.
- Widget tests: the shell shows 4 tabs when developer mode is off and 5 when it is on;
  the পাঠানো বাকি badge shows 2 with the sample data; the online pill text changes when
  setOnline(false) is called.
- flutter build apk --debug succeeds.
- A search shows no Color( values outside lib/core/theme/colors.dart and no double in
  any money field.
- I check by eye on an emulator that the header and bottom navigation match the reference.

Assumptions
- Flutter stable and the Android SDK with an emulator are installed.
- reference/bdpay-sms-verifier-v2.html exists.
- The Noto Sans Bengali font files are in app/assets/fonts. If they are missing, stop and
  ask me to add them. Do not download anything.
- If the font files are missing, use the system font and add them before release