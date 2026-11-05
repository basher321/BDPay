# 02 Home screen and device health

Purpose
Build the হোম tab so the merchant sees at one glance: is the phone working, is the
server reachable, how much money was verified today, and the latest payments.
It must look and behave like the dashboard in reference/bdpay-sms-verifier-v2.html.

Scope
- The হোম screen in lib/features/home/, with these sections in this order:
  1. Device card
  2. Device health card
  3. Today's verified total card
  4. Three count cards
  5. "Send pending now" button (only when pending items exist)
  6. Developer test button (only in developer mode)
  7. Operator strip
  8. Latest transactions (max 5) with "সব দেখুন (N)"
- A shared TransactionCard widget in lib/widgets (used again in spec 03).
- Additions to spec 01 code, and only these:
  - DeviceHealthRepository gets pingServer(), requestSmsPermission(), requestBatteryExemption().
  - The mock DeviceHealthRepository implements them.
  - New providers: clockProvider, tickerProvider, selectedTabProvider, transactionFilterProvider.
  - New strings in strings.dart.
- No new packages.
- Not in scope: the transaction detail screen, the লেনদেন screen content, real Android
  permission or battery calls (spec 06), real server calls (spec 13).

Contract
DeviceHealthRepository (added methods):
- Future<bool> pingServer(): mock returns true when online and sets lastServerContactAt
  to now; returns false when offline.
- Future<void> requestSmsPermission(): mock sets smsPermission true.
- Future<void> requestBatteryExemption(): mock sets batteryOptimizationOff true.
Mock starting state: smsPermission true, batteryOptimizationOff false, internetOnline true,
monitoring true, lastSmsAt = newest sample transaction time, lastServerContactAt = app start.

Providers (lib/data/providers.dart):
- clockProvider: returns the current time (DateTime.now().toUtc()). Tests override it.
- tickerProvider: emits every 30 seconds so "N মিনিট আগে" texts refresh.
- selectedTabProvider: the current bottom tab (AppTab enum: home, transactions, queue, devLab, settings).
- transactionFilterProvider: Set<VerifyStatus>? (null = all). Spec 03 reads it.

TransactionCard(transaction, onTap): operator badge, TrxID (bold), "প্রেরক: {payer} • {kind label}",
VerifyStatusChip, time (dhakaClock), amount (MoneyText, emerald) and SyncStatusLabel on the right.
onTap may be null in this spec.

Functional rules
1. Device card
   - Round icon: emerald ◉ when monitoring is on, red ⊘ when off.
   - Title: AppSettings.deviceName. Subtitle: "এসএমএস দেখা হচ্ছে" when on,
     "মনিটরিং বন্ধ — নতুন পেমেন্ট ধরা হবে না" when off.
   - An AppSwitch on the right calls setMonitoring.
   - Server row: green dot + "সার্ভার সংযুক্ত" when online, red dot + "সার্ভারে সংযোগ নেই" when offline,
     then " • শেষ সংযোগ {timeAgo(lastServerContactAt)}". A small ⟳ button calls pingServer:
     true -> toast "সার্ভার সংযুক্ত আছে", false -> toast "সার্ভারে সংযোগ নেই".
2. Device health card
   - Title "ডিভাইস স্বাস্থ্য". Right side: "সব ঠিক আছে ✓" (ok color) or "{n} টি সমস্যা" (wa color).
   - Rows, each with a ✓ (ok) or ! (wa) circle, a title and a hint:
     a. "এসএমএস পড়ার অনুমতি": ok "দেওয়া আছে" / problem "অনুমতি দিন — না দিলে অ্যাপ কাজ করবে না",
        button "ঠিক করুন" -> requestSmsPermission.
     b. "ব্যাটারি সেভার থেকে বাদ": ok "ঠিক আছে" / problem "চালু থাকলে ফোন অ্যাপটি বন্ধ করে দিতে পারে",
        button "ঠিক করুন" -> requestBatteryExemption.
     c. "ইন্টারনেট": ok "সংযুক্ত" / problem "নেই — এসএমএস ফোনে জমা থাকবে". No button.
     d. "এসএমএস মনিটরিং": ok "চালু" / problem "বন্ধ আছে". No button (the switch is in the device card).
     e. "সর্বশেষ এসএমএস": always ok, hint timeAgo(lastSmsAt), or "এখনো আসেনি" when null.
   - The problem count is the number of rows a-d that are not ok.
3. Today's total card
   - Label "আজ নিশ্চিত হওয়া মোট টাকা", the sum (formatPoisha, 32 size, emerald),
     caption "শুধু সার্ভার যেগুলো নিশ্চিত করেছে".
   - Sum = amountPoisha of transactions with verifyStatus verified whose receivedAt falls on
     today's date in Asia/Dhaka (from clockProvider). Integer sum only.
4. Count cards (three, side by side)
   - "নিশ্চিত" = verified count, ok dot.
   - "যাচাই বাকি" = pending count, wa dot.
   - "মেলেনি / বাতিল" = mismatch + rejected count, er dot.
   - Counts cover all transactions, not only today.
   - Tapping a card sets transactionFilterProvider ({verified}, {pending}, {mismatch, rejected})
     and switches to the লেনদেন tab.
5. Send pending button
   - Outline button "⟳ বাকি {n} টি এখনই পাঠান" where n = queued + failed. Hidden when n = 0.
   - Tap -> retryAllPending. The button is disabled while it runs.
   - After: all sent -> toast "সব পাঠানো হয়েছে"; some failed -> toast "{f} টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে".
6. Developer button
   - Only when developerMode is true: outline button "⚗ এসএমএস পরীক্ষা (ডেভেলপার)" -> switches to the পরীক্ষা tab.
7. Operator strip
   - Title "অপারেটর". Four equal tiles: operator name in its text color and "{count} টি".
   - A tile for an operator not in enabledOperators is faded (50%) and shows "বন্ধ".
8. Latest transactions
   - Title "সর্বশেষ লেনদেন" and on the right "সব দেখুন ({total})" -> clears the filter and switches to লেনদেন.
   - The newest 5 transactions as TransactionCard.
   - Empty: "এখনো কোনো লেনদেন নেই".
- The whole screen scrolls. "N মিনিট আগে" texts refresh every 30 seconds through tickerProvider.
- Every color, size and label follows the reference file.

Edge cases
- No transactions: total ৳ 0.00, all counts 0, no send button, empty text shown.
- A verified transaction from yesterday (Dhaka time) is not in today's total, even if it is
  less than 24 hours old.
- Dhaka midnight: 23:59 Dhaka is yesterday's total, 00:00 Dhaka is today's (UTC 18:00 boundary).
- Offline: the server row, the online pill and the internet health row all show the problem at once.
- Tapping "send pending" twice fast runs retryAllPending only once.
- A very long device name is cut with an ellipsis.

Non-functional rules
- No logic inside widgets beyond reading providers. The total and counts come from a small
  pure function in lib/features/home/home_summary.dart so they can be unit-tested.
- flutter analyze reports zero issues.

Acceptance criteria
- flutter analyze: no issues.
- Unit tests for home_summary with the clock fixed at 2026-10-29 12:00 Asia/Dhaka:
  sample data total = ৳ 3,750.00; counts 2 / 2 / 1; a verified item at 2026-10-28 23:59 Dhaka
  is excluded; one at 2026-10-29 00:00 Dhaka is included.
- Widget tests:
  - health header shows "1 টি সমস্যা"; tapping the battery "ঠিক করুন" changes it to "সব ঠিক আছে ✓".
  - setOnline(false) shows "সার্ভারে সংযোগ নেই" and the header shows "2 টি সমস্যা".
  - turning the monitoring switch off shows "মনিটরিং বন্ধ — নতুন পেমেন্ট ধরা হবে না".
  - the send button shows "বাকি 2 টি এখনই পাঠান"; after tapping it (online) it disappears.
  - the developer button appears only in developer mode.
  - disabling Upay in settings shows "বন্ধ" on the Upay tile.
  - tapping "নিশ্চিত" sets the filter to {verified} and the selected tab to transactions.
  - the latest list shows at most 5 cards.
- flutter test passes in full (spec 01 tests still pass).
- flutter build apk --debug succeeds.
- I check by eye on an emulator that the home screen matches the reference dashboard.

Assumptions
- Spec 01 is done and all its tests pass.
