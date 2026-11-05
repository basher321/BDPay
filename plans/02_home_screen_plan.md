# Plan 02 - Home screen and device health

Spec: specs/02_home_screen.md (builds on specs/01_app_foundation.md)
Status found: spec 01 is NOT done. app/ exists with packages added, but app/assets/fonts is empty
and no spec 01 code is written yet (app/lib has only the generated main.dart). Spec 02 starts
only after spec 01 passes all its checks.

Text decision carried over from spec 01 (D1 = A): all strings live in app/lib/l10n/app_bn.arb.
Where spec 02 says "strings.dart", this plan uses app_bn.arb (section 4, item 1).

Decision needed before execution
- D2. **The shell has to change, but the spec doesn't allow it.** Spec 02 allows only four kinds of change to spec 01 code
  (repository methods, mock methods, providers, strings). But the হোম tab can only show HomeScreen,
  and the new selectedTabProvider can only drive the tabs, if app/lib/shell/app_shell.dart changes.
  Proposal: allow exactly this one extra change: the shell shows HomeScreen on the হোম tab and reads the
  current tab from selectedTabProvider. Nothing else in the shell changes. Approve, or change the spec.

## 1. Files

### New files
- app/lib/features/home/home_screen.dart - the scrolling হোম screen; places the 8 sections in spec order.
- app/lib/features/home/home_summary.dart - pure functions: HomeSummary (today's verified total, verified /
  pending / mismatch+rejected counts, sendable count, per-operator counts) and healthProblemCount(DeviceHealth).
- app/lib/features/home/widgets/device_card.dart - section 1: monitoring icon, name, subtitle, switch, server row, ⟳ ping.
- app/lib/features/home/widgets/health_card.dart - section 2: header with problem count and rows a-e with "ঠিক করুন".
- app/lib/features/home/widgets/today_total_card.dart - section 3: today's verified total.
- app/lib/features/home/widgets/count_cards.dart - section 4: three tappable count cards.
- app/lib/features/home/widgets/send_pending_button.dart - section 5: button with the running guard and the result toast.
- app/lib/features/home/widgets/dev_lab_button.dart - section 6: developer-only button.
- app/lib/features/home/widgets/operator_strip.dart - section 7: four operator tiles.
- app/lib/features/home/widgets/latest_transactions.dart - section 8: title, "সব দেখুন (N)", up to 5 cards, empty text.
- app/lib/widgets/transaction_card.dart - shared TransactionCard(transaction, onTap), reused in spec 03. Shows
  "প্রেরক: —" when payerNumber is null (spec 03 needs this and may not change this file).
- app/test/features/home/home_test_helpers.dart - pumps HomeScreen with a fixed clock (2026-10-29 12:00 Dhaka =
  06:00 UTC), a controllable ticker and fresh mocks. New file, so spec 01's test_helpers.dart is not changed.
- app/test/features/home/home_summary_test.dart - unit tests for home_summary with the fixed clock.
- app/test/features/home/home_screen_test.dart - widget tests for the home screen.

### Changed spec 01 files (marked [CHANGED 01]) - only what spec 02 allows, plus D2
- [CHANGED 01] app/lib/domain/repositories/device_health_repository.dart - add pingServer(),
  requestSmsPermission(), requestBatteryExemption(). (Allowed: "DeviceHealthRepository gets ...")
- [CHANGED 01] app/lib/data/mock/mock_device_health_repository.dart - implement the 3 methods; starting state
  as in the spec (battery off = false, lastSmsAt = newest sample, lastServerContactAt = start); reads time
  from a clock function passed in. (Allowed: "The mock DeviceHealthRepository implements them")
- [CHANGED 01] app/lib/data/providers.dart - add clockProvider, tickerProvider, selectedTabProvider,
  transactionFilterProvider; give the mocks their "now" from clockProvider. (Allowed: "New providers")
- [CHANGED 01] app/lib/l10n/app_bn.arb - all new spec 02 strings, with {n}/{f}/{total}/{count}/{time}
  placeholders. (Allowed: "New strings")
- [CHANGED 01, needs D2] app/lib/shell/app_shell.dart - the হোম tab shows HomeScreen; the current tab is read from
  selectedTabProvider; the existing "dev mode off on devLab -> home" rule now sets selectedTabProvider.

### Not changed (kept out on purpose)
- sample_transactions.dart, app_tab.dart: plan 01 now builds them the way spec 02 needs (the samples take a
  "now" value; AppTab uses devLab), so spec 02 does not touch them.
- mock_transaction_repository.dart, all widgets from spec 01, pubspec.yaml: unchanged.
- Spec 01 tests (test/widget_test.dart, test_helpers.dart and the rest): unchanged; they must still pass as they are.
- No new packages.

## 2. Order of work

0. Finish spec 01 and pass all its checks (blocked: font files). Get your answer on D2.
1. Repository interface + mock: the 3 new methods, starting state, clock passed in. flutter analyze.
2. Providers: clockProvider, tickerProvider, selectedTabProvider, transactionFilterProvider. flutter analyze;
   flutter test (spec 01 still green).
3. home_summary.dart + home_summary_test.dart. flutter analyze; flutter test.
4. New strings in app_bn.arb. flutter analyze.
5. TransactionCard. flutter analyze.
6. The 8 section widgets, then home_screen.dart, then the shell change (D2). flutter analyze after each group.
7. home_test_helpers.dart + home_screen_test.dart. Full flutter test.
8. flutter build apk --debug, then the searches in section 3.
9. You check the home screen by eye on an emulator.

## 3. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| flutter analyze: no issues | "No issues found!" |
| Sample total ৳ 3,750.00 at 2026-10-29 12:00 Dhaka | home_summary_test: samples 1 (125000) + 2 (250000) verified today -> formatPoisha = "৳ 3,750.00" |
| Counts 2 / 2 / 1 | home_summary_test: verified 2, pending 2, mismatch+rejected 1 |
| Verified at 2026-10-28 23:59 Dhaka excluded | home_summary_test: 2026-10-28 17:59 UTC item not added |
| Verified at 2026-10-29 00:00 Dhaka included | home_summary_test: 2026-10-28 18:00 UTC item added |
| "1 টি সমস্যা" -> battery "ঠিক করুন" -> "সব ঠিক আছে ✓" | home_screen_test |
| setOnline(false) -> "সার্ভারে সংযোগ নেই" and "2 টি সমস্যা" | home_screen_test |
| Monitoring switch off -> "মনিটরিং বন্ধ — নতুন পেমেন্ট ধরা হবে না" | home_screen_test (also icon ◉ -> ⊘) |
| Send button "বাকি 2 টি এখনই পাঠান"; disappears after tap (online) | home_screen_test (contains-match, pump past 700 ms) |
| Developer button only in developer mode | home_screen_test: absent, then present after settings update |
| Upay disabled -> "বন্ধ" on the Upay tile | home_screen_test: settings update without upay |
| Tap "নিশ্চিত" -> filter {verified}, tab transactions | home_screen_test: read both providers from the container |
| Latest list shows at most 5 cards | home_screen_test: add a 6th transaction, find 5 TransactionCard |
| flutter test passes in full (spec 01 too) | full `flutter test`, spec 01 test files unchanged |
| flutter build apk --debug succeeds | exits 0, app-debug.apk exists |
| Home matches the reference dashboard | You check by eye on an emulator |

Functional rules and edge cases (not listed as criteria, checked too)

| Rule | Check |
|---|---|
| Section order 1-8 | home_screen_test: vertical positions of the 8 section keys increase |
| Whole screen scrolls | home_screen_test: one vertical Scrollable; scroll to the latest list |
| "N মিনিট আগে" refreshes every 30 s | home_screen_test: move the fixed clock forward 2 min, emit a ticker event, text changes |
| No transactions: ৳ 0.00, counts 0, no send button, empty text | home_summary_test + home_screen_test with an empty mock |
| Offline shows the problem in the server row, the pill and the internet row together | home_screen_test (same test as setOnline) |
| Send button disabled while it runs | home_screen_test: during the 700 ms the button's onPressed is null |
| Double tap on send runs retryAllPending once | home_screen_test with a counting fake TransactionRepository |
| Some failed -> "{f} টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে"; all sent -> "সব পাঠানো হয়েছে" | home_screen_test |
| Ping toasts (true / false) and lastServerContactAt updated | home_screen_test |
| Count cards {pending} and {mismatch, rejected}; "সব দেখুন" clears the filter and opens লেনদেন | home_screen_test |
| Operator tiles show "{count} টি" | home_screen_test: bKash "2 টি" with sample data |
| Long device name ellipsis | home_screen_test: long name, no overflow error |
| No Color( outside colors.dart | search (same as spec 01) |
| Integer sum only, no double in money | search for `double` in app/lib (same as spec 01) |
| No logic in widgets | review: totals, counts and problem count come only from home_summary.dart |
| Spec 01 files changed only as allowed | review the changed-file list in section 1 before marking done |

## 4. Unclear or possibly wrong in the spec

1. **strings.dart vs ARB.** The spec says "New strings in strings.dart", but you chose ARB for spec 01 (D1 = A). The plan uses
   app_bn.arb. Update the spec line if you agree.
2. **clockProvider shape.** "Returns the current time": a plain Provider<DateTime> is cached and never moves. Plan:
   clockProvider watches tickerProvider and gives a fresh DateTime.now().toUtc() every 30 s; tests override
   it with a fixed time and override tickerProvider with a stream they control (no pending timers).
3. **"App start" vs the clock.** Spec 01 says sample times are relative to app start. Plan 01 now builds the samples from a "now"
   value, and providers.dart passes clockProvider's first value (that value *is* app start).
4. **Tab name.** The spec calls the developer tab devLab. Plan 01 is updated to use devLab, so no rename is needed later.
5. **Failed count for the toast.** retryAllPending() returns void, and the spec allows no interface change. Plan: after it
   finishes, f = number of items with syncStatus failed in the latest list. Is that right?
6. **Parallel retry.** The mock retries all pending items at the same time (one 700 ms wait). Say if you want them one by one.
7. **lastServerContactAt is nullable.** When it is null, plan hides " • শেষ সংযোগ ..." (no new string).
8. **Server vs internet.** In the mock, "server reachable" and internetOnline are the same thing. The real app will need a
   separate field once the real server is connected.
9. **Symbols.** ◉ ⊘ ⟳ ⚗ ✓ come from the reference. Noto Sans Bengali doesn't have them, so Android uses a fallback
   font; ⚗ may draw as an emoji or an empty box. Plan keeps them as specified; check them on the emulator.
10. **Test text.** "বাকি 2 টি এখনই পাঠান" in the test leaves out the leading "⟳ " of the label. Plan uses a contains-match.
11. **No settings screen yet.** "Disabling Upay in settings" means calling SettingsRepository.update in the test.
12. **Spec numbers.** The Scope refers to permissions as "spec 06" and the server as "spec 13", which doesn't match the
    roadmap. Informational only.
13. **Reference still missing.** reference/bdpay-sms-verifier-v2.html is still missing. Plan uses the root "BDPay SMS Verifier.html" plus the
    spec's colours. The reference has no health card, so that card follows the reference card style.

## 5. Review log

Review 1 against spec 02 and CLAUDE.md:
- Outside Scope: none in the screens. Removed spec 01 file changes the spec does not list (below).
- Spec 01 files changed without permission (before the fix): sample_transactions.dart and app_tab.dart (now done
  correctly inside plan 01 instead), test_helpers.dart and possibly widget_test.dart (replaced by the new
  home_test_helpers.dart; spec 01 tests are untouched). app_shell.dart cannot be avoided -> decision D2.
- Criteria without a check: none. Added checks for rules that had none: section order, scrolling, the
  30 s refresh, the disabled button while sending, the "all sent" toast, operator tile counts, and the
  Color( search.
- CLAUDE.md: "Do only what the current spec says" was broken by the extra spec 01 changes -> fixed, except
  the shell, which is now D2. Text in ARB, colours from the theme, money as int and Dhaka time all hold.
