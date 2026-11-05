# 04 Queue screen (পাঠানো বাকি)

Purpose
Build the পাঠানো বাকি tab so the merchant can see every SMS that has not reached the
server yet, send them by hand, and trust that nothing is lost while the phone is offline.
Also send waiting items automatically when the internet comes back.
It must look and behave like the queue screen in reference/bdpay-sms-verifier-v2.html.

Scope
- The পাঠানো বাকি screen in lib/features/queue/: info card, header with "send all",
  the queue list and the empty state.
- An auto-send coordinator in lib/data/sync_coordinator.dart, started once when the app starts.
- Additions to earlier code, and only these:
  - The queue card "বিস্তারিত" button opens the spec 03 detail sheet.
  - The app shell starts the sync coordinator.
  - New strings in strings.dart.
- No new packages.
- Not in scope: background sending while the app is closed and retry timing (spec 06),
  real server calls (spec 13), deleting queue items.

Contract
- Queue items = transactions with syncStatus queued, sending or failed.
- Pure function in lib/features/queue/queue_logic.dart:
  - List<SmsTransaction> queueItems(List<SmsTransaction> all): queue items, OLDEST first
    (the order they will be sent).
  - bool isStale(SmsTransaction t, DateTime now): true when receivedAt is more than 24 hours before now.
  - bool isStuck(SmsTransaction t): true when retryCount >= 5.
- SyncCoordinator:
  - Listens to DeviceHealth.internetOnline and AppSettings.autoSend.
  - When internetOnline changes from false to true and autoSend is true, it calls
    retryAllPending once and shows the toast from rule 5.
  - It never runs two retryAllPending calls at the same time.
  - It has start() and dispose(), and gets its repositories through providers so tests can
    give it mocks.

Functional rules
1. Info card (top)
   - ⓘ icon and the text: "ইন্টারনেট না থাকলেও এসএমএস ফোনে নিরাপদে জমা থাকে। সংযোগ ফিরলে নিজে থেকেই
     পাঠানো হবে। একই লেনদেন দুবার গণনা হবে না।"
   - When autoSend is off, the second sentence changes to: "অটো পাঠানো বন্ধ আছে — নিচের বোতাম চাপুন।"
2. Header
   - "পাঠানো বাকি ({n})" (17, bold) where n = number of queue items.
   - Under it: "ইন্টারনেট আছে" (ok color) or "ইন্টারনেট নেই" (er color).
   - Right side: primary button "☁ সব পাঠান". Disabled when there are no queued/failed items,
     when offline, or while a send-all is running.
3. Queue card (one per item, oldest first)
   - Row 1: operator badge, TrxID (bold) | amount (emerald).
   - Row 2: "প্রেরক: {payer} • {timeAgo(receivedAt)}".
   - If retryCount > 0: red line "{retryCount} বার চেষ্টা ব্যর্থ • {serverMessage}".
   - If isStuck: an extra red line "বারবার ব্যর্থ — ইন্টারনেট বা সার্ভার চেক করুন".
   - If isStale: an amber line "২৪ ঘণ্টার বেশি পুরনো — গ্রাহকের অর্ডার বাতিল হয়ে যেতে পারে".
   - Bottom row: SyncStatusLabel | buttons "বিস্তারিত" (outline, small) and "⟳ পাঠান" (primary, small).
   - "⟳ পাঠান" is disabled while that item is sending and when offline.
4. Send all
   - Calls retryAllPending. After: all sent -> toast "সব পাঠানো হয়েছে"; some failed -> toast
     "{f} টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে".
   - A sent item leaves the list. A failed item stays with its retryCount increased.
5. Auto-send (SyncCoordinator)
   - Internet back + autoSend on -> send all queued and failed items, then toast
     "ইন্টারনেট ফিরেছে — {k} টি পাঠানো হয়েছে" (k = items that became sent).
     If k = 0, show no toast.
   - autoSend off -> nothing happens automatically.
6. Empty state
   - ☁ (52, emerald), "সব পাঠানো হয়েছে!", "কোনো এসএমএস বাকি নেই।"
7. The tab badge (spec 01) keeps counting queued + failed and updates live.

Edge cases
- Items are never removed from the queue except by becoming sent. There is no delete action.
- Going offline in the middle of send-all: items not yet sent become failed and stay in the list.
- Going offline then online quickly twice runs auto-send at most once at a time.
- An item older than 24 hours AND failed 5 times shows both warnings.
- A sending item shows "পাঠানো হচ্ছে…" and both its buttons are still visible
  ("⟳ পাঠান" disabled).

Non-functional rules
- queue_logic.dart is pure and unit-tested.
- SyncCoordinator holds no UI code except calling showToast through a callback.
- flutter analyze reports zero issues.

Acceptance criteria
- flutter analyze: no issues.
- Unit tests for queue_logic: with sample data queueItems returns 2 items, Rocket (50 min)
  before Upay (95 min) is WRONG - oldest first means Upay first, then Rocket; isStale false at
  23 h 59 m and true at 24 h 1 m; isStuck false at 4 and true at 5.
- Unit tests for SyncCoordinator: offline -> online with autoSend on calls retryAllPending once;
  with autoSend off it is not called; two quick online events while a send is running call it once.
- Widget tests:
  - the header shows "পাঠানো বাকি (2)" and the Rocket card shows "2 বার চেষ্টা ব্যর্থ • নেটওয়ার্ক সংযোগ নেই".
  - offline: "সব পাঠান" and every "⟳ পাঠান" are disabled and "ইন্টারনেট নেই" shows.
  - online: tapping "সব পাঠান" empties the list and shows "সব পাঠানো হয়েছে!".
  - "বিস্তারিত" opens the detail sheet for that item.
  - an item 25 hours old shows the stale warning; an item with retryCount 5 shows the stuck warning.
  - turning autoSend off changes the info card text.
- flutter test passes in full (specs 01-03 tests still pass).
- flutter build apk --debug succeeds.
- I check by eye on an emulator: developer mode -> offline, then back online -> the queue empties
  by itself and the toast shows.

Assumptions
- Specs 01, 02 and 03 are done and all their tests pass.
- The developer-mode offline switch arrives in spec 05; until then tests use setOnline().
