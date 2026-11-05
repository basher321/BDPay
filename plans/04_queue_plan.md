# Plan 04 - Queue screen (পাঠানো বাকি)

Spec: specs/04_queue.md (builds on specs 01-03)
Status found: spec 01 is built (analyze clean, 17 tests pass, debug APK built). Spec 02 is in progress (new files
written, not yet wired or tested). Spec 03 is not started. Spec 04 starts only after 01-03 pass all their checks.

Text decision carried over (D1 = A): where the spec says "strings.dart", this plan uses app/lib/l10n/app_bn.arb.

Decision needed before execution
- D5. **The shell has to change again.** The spec allows the shell to start the sync coordinator, but the পাঠানো বাকি tab can only show
  QueueScreen if the shell changes too, and the spec doesn't list that. Like D2/D3, the proposal is exactly one extra
  change: the queue tab shows QueueScreen. Approve, or change the spec.

## 1. Files

### New files
Queue screen (app/lib/features/queue/)
- queue_logic.dart - pure queueItems(all) (queued/sending/failed, oldest first), isStale(t, now) (> 24 h), isStuck(t)
  (retryCount >= 5).
- queue_screen.dart - the tab: info card, header, then a lazy list of QueueCard (oldest first) or the empty state.
- widgets/queue_info_card.dart - ⓘ + the 3-sentence text; the 2nd sentence changes when autoSend is off.
- widgets/queue_header.dart - "পাঠানো বাকি ({n})", internet line, "☁ সব পাঠান" with its running guard and result toast.
- widgets/queue_card.dart - one queue item: badge, TrxID, amount, payer + timeAgo, red/amber warning lines,
  SyncStatusLabel, "বিস্তারিত" (opens showTransactionDetail from spec 03) and "⟳ পাঠান".

Auto-send
- app/lib/data/sync_coordinator.dart - SyncCoordinator(health, settings, transactions, onAutoSent) with start() /
  dispose(), plus syncCoordinatorProvider (gets the 3 repositories from the spec 01 providers, so tests can give mocks).
  It keeps the latest health, settings and transaction list from their streams; on internetOnline false -> true with
  autoSend on it runs retryAllPending once (a guard flag ignores new events while one is running), then calls
  onAutoSent(k) where k = items that went from queued/failed to sent. It has no UI code and no text: the toast and
  its ARB text are done by the callback in the shell.

Tests
- app/test/features/queue/queue_logic_test.dart - queueItems order and filter, isStale 23h59m / 24h01m, isStuck 4 / 5.
- app/test/data/sync_coordinator_test.dart - the 3 coordinator cases from the criteria, plus k counting, k = 0 -> no callback,
  and the first event only setting the starting point.
- app/test/features/queue/queue_test_helpers.dart - pumps QueueScreen with a fixed clock, fresh mocks, and a fake
  repository with custom items (25 h old, retryCount 5, sending). It imports the spec 03 test fake repository if
  that one fits, so no earlier test file is changed or copied.
- app/test/features/queue/queue_screen_test.dart - widget tests for the screen.
- app/test/features/queue/auto_send_app_test.dart - pumps the whole app with spec 01's pumpApp (unchanged) and runs the
  emulator scenario automatically: setOnline(false), setOnline(true) -> the queue empties by itself and the toast
  "ইন্টারনেট ফিরেছে — 2 টি পাঠানো হয়েছে" shows. This proves the shell really starts the coordinator.

### Changed earlier files
- [CHANGED 01] app/lib/shell/app_shell.dart:
  - starts the coordinator in initState and disposes it in dispose; its callback shows the toast
    "ইন্টারনেট ফিরেছে — {k} টি পাঠানো হয়েছে" with the shell's context. (Allowed: "The app shell starts the sync coordinator")
  - the পাঠানো বাকি tab shows QueueScreen. (Needs D5)
- [CHANGED 01] app/lib/l10n/app_bn.arb - all new spec 04 strings with {n}/{f}/{k}/{retryCount}/{message}/{payer}/{time}
  placeholders. (Allowed: "New strings")
- "বিস্তারিত" opening the spec 03 detail sheet is a call to showTransactionDetail from the new queue_card.dart; no spec 03
  file changes. (Allowed: "The queue card "বিস্তারিত" button opens the spec 03 detail sheet")

### Not changed (on purpose)
- providers.dart, all repositories and mocks, the spec 02 home widgets (including SendPendingButton), the spec 03 detail sheet:
  unchanged. syncCoordinatorProvider lives in the new sync_coordinator.dart.
- All spec 01-03 test files: unchanged; they must still pass as they are.
- pubspec.yaml: unchanged, no new packages.

## 2. Order of work

0. Specs 02 and 03 built and green. Get your answer on D5.
1. queue_logic.dart + queue_logic_test.dart. flutter analyze; flutter test.
2. sync_coordinator.dart + sync_coordinator_test.dart. flutter analyze; flutter test.
3. New strings in app_bn.arb. flutter analyze.
4. Queue widgets, then queue_screen.dart. flutter analyze.
5. Shell: start/dispose the coordinator, queue tab shows QueueScreen. flutter analyze; flutter test (01-03 still green).
6. queue_test_helpers.dart + queue_screen_test.dart. Full flutter test.
7. flutter build apk --debug, then the searches in section 3.
8. You check by eye on an emulator (see section 4, item 9 about the offline switch).

## 3. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| flutter analyze: no issues | "No issues found!" |
| queueItems with sample data: 2 items, Upay (95 min) first, then Rocket (50 min) | queue_logic_test |
| isStale false at 23 h 59 m, true at 24 h 1 m | queue_logic_test |
| isStuck false at 4, true at 5 | queue_logic_test |
| Coordinator: offline -> online, autoSend on -> retryAllPending once | sync_coordinator_test with a counting fake TransactionRepository |
| Coordinator: autoSend off -> not called | sync_coordinator_test |
| Coordinator: two quick online events while sending -> called once | sync_coordinator_test: fake retryAllPending waits on a Completer; send online, offline, online; count = 1 |
| (Spec: SyncCoordinator has start() and dispose()) | sync_coordinator_test: after dispose(), offline -> online calls nothing |
| Header "পাঠানো বাকি (2)"; Rocket card "2 বার চেষ্টা ব্যর্থ • নেটওয়ার্ক সংযোগ নেই" | queue_screen_test |
| Offline: "সব পাঠান" and every "⟳ পাঠান" disabled; "ইন্টারনেট নেই" shown | queue_screen_test: every AppButton's onPressed is null |
| Online: "সব পাঠান" empties the list and shows "সব পাঠানো হয়েছে!" | queue_screen_test (pump past 700 ms) |
| "বিস্তারিত" opens the detail sheet for that item | queue_screen_test: sheet shows that item's TrxID |
| 25 h old -> stale warning; retryCount 5 -> stuck warning | queue_screen_test with the fake repository |
| autoSend off changes the info card text | queue_screen_test: settings update, "অটো পাঠানো বন্ধ আছে — নিচের বোতাম চাপুন।" found |
| flutter test passes in full (01-03 too) | full `flutter test`, earlier test files unchanged |
| flutter build apk --debug succeeds | exits 0, app-debug.apk exists |
| On an emulator: offline, back online -> queue empties, toast shows | Automated now in auto_send_app_test.dart; you check by eye once spec 05 adds the offline switch (section 4, item 9) |

Functional rules and edge cases (not listed as criteria, checked too)

| Rule | Check |
|---|---|
| Queue items include sending (not only queued/failed) | queue_logic_test |
| Header line "ইন্টারনেট আছে" (ok) / "ইন্টারনেট নেই" (er) | queue_screen_test |
| "সব পাঠান" disabled with no queued/failed items and while running | queue_screen_test: only a sending item -> disabled; during the 700 ms -> disabled |
| Send all with some failed -> "{f} টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে"; failed item stays with retryCount + 1 | queue_screen_test: go offline during send-all |
| Offline in the middle of send-all -> items become failed and stay | same test as above |
| Card row 1: badge, TrxID, amount | queue_screen_test: Rocket card shows "Rocket", its TrxID and "৳ 1,500.00" |
| Card row 2 "প্রেরক: {payer} • {timeAgo}" | queue_screen_test |
| Retry and stuck lines are red, stale line is amber | queue_screen_test reads the Text colour (er / wa) |
| Stale + stuck on one item shows both warnings | queue_screen_test with the fake repository |
| Sending item: "পাঠানো হচ্ছে…", both buttons visible, "⟳ পাঠান" disabled | queue_screen_test with the fake repository |
| Empty state ☁ / "সব পাঠানো হয়েছে!" / "কোনো এসএমএস বাকি নেই।" | queue_screen_test |
| Auto-send toast "ইন্টারনেট ফিরেছে — {k} টি পাঠানো হয়েছে"; none when k = 0 | sync_coordinator_test (callback value) + a shell widget test in queue_screen_test |
| Tab badge updates live | the spec 01 badge test still passes; queue_screen_test checks the badge after send-all |
| No delete action anywhere in the queue | review: no delete/remove call in lib/features/queue |
| Coordinator has no UI code and no text | review: sync_coordinator.dart imports no Flutter widget/material library and no l10n |
| Coordinator started once when the app starts | review: started in the shell's initState, not in build; auto_send_app_test shows exactly one retry per online event |
| No double, no Color( outside colors.dart | searches (same as spec 01) |
| Earlier files changed only as allowed | review the changed-file list in section 1 before marking done |

## 4. Unclear or possibly wrong in the spec

1. **The shell change for the queue tab is not listed.** -> D5.
2. **The criterion text is garbled.** "Rocket (50 min) before Upay (95 min) is WRONG - oldest first means Upay first, then Rocket"
   reads like an edit note. Plan: queueItems returns [Upay, Rocket]. Please clean the sentence in the spec.
3. **Events while a send is running.** The plan ignores them (they don't queue a second run). Items that are still failed after the
   run wait for the next false -> true change or a manual send. Say if you want "run once more after the current run ends".
4. **"Order they will be sent" vs the mock.** The mock's retryAllPending sends all items at the same time, so "oldest first" is only the
   display order for now. A real one-by-one order is retry timing (spec 06).
5. **Counting k.** After retryAllPending finishes, the coordinator waits one event-loop turn for the list stream and then counts
   the items that were queued/failed before and are sent now. (The send-all toast on the screen works the same way, like
   the হোম button in spec 02.)
6. **Repeated send-all code.** The queue header and the spec 02 হোম button both run send-all and show the same toasts. The spec doesn't allow
   changing the spec 02 button, so this small piece of code is repeated in queue_header.dart.
7. **"Second sentence".** The info card text has three sentences; "the second sentence" = "সংযোগ ফিরলে নিজে থেকেই পাঠানো হবে।". With
   autoSend off the text becomes: "ইন্টারনেট না থাকলেও এসএমএস ফোনে নিরাপদে জমা থাকে। অটো পাঠানো বন্ধ আছে — নিচের বোতাম চাপুন।
   একই লেনদেন দুবার গণনা হবে না।"
8. **"⟳ পাঠান" during send-all.** The spec disables it while that item is sending and when offline. Items become "sending" as soon as
   send-all starts, so this covers send-all too.
9. **No offline switch for the emulator check.** It needs the developer-mode offline switch, which arrives in spec 05. The mock doesn't read the
   emulator's real network, so the eye check can't be done before spec 05. Until then, auto_send_app_test.dart runs
   the same scenario in the full app.
13. **Two senders at once.** The হোম "send pending" button (spec 02), the queue's "সব পাঠান" and the coordinator can all start a send.
    The spec only requires the coordinator to never overlap with itself. It is still safe: the mock retry skips an item that
    is already sending, so no item is sent twice.
10. **Font size 17.** The header is 17 bold, but the theme has no 17 style and the spec doesn't allow changing app_theme.dart.
    Plan: AppText.title16.copyWith(fontSize: 17).
11. **Bangla digits.** The stale text uses Bangla digits ("২৪ ঘণ্টার"); every other number in the app uses Latin digits. Kept exactly as written.
12. **Reference still missing.** reference/bdpay-sms-verifier-v2.html is still missing. Plan uses the root "BDPay SMS Verifier.html" queue
    screen (info card, header with button, cards with details/sync buttons, empty state) plus the spec's colours.

## 5. Review log

Review 1 against spec 04 and CLAUDE.md:
- Outside Scope: nothing found. All new code is in lib/features/queue/ and lib/data/sync_coordinator.dart.
- Earlier files changed without permission: only the queue-tab part of app_shell.dart (-> D5). Starting the coordinator
  in the shell and the new ARB strings are allowed. No spec 02/03 file changes; the spec 03 test fake is only imported.
- Criteria without a check: none. The emulator criterion now also has an automated full-app test
  (auto_send_app_test.dart). Added checks for start/dispose, card row 1, the warning colours, and "started once".
- CLAUDE.md: the toast text comes from ARB through the shell callback (the coordinator has no text); no delete action;
  the mock-only sends are still marked MOCK; money is int. Possible overlap between the 3 senders is written down
  (section 4, item 13) and is safe with the current mock.
