# Plan 03 - Transactions list, detail and manual review

Spec: specs/03_transactions.md (builds on specs 01 and 02)
Status found: specs 01 and 02 are NOT built. app/ has its packages, but app/assets/fonts is empty
and app/lib has only the generated main.dart. Spec 03 starts only after 01 and 02 pass all their checks.

Text decision carried over (D1 = A): where the spec says "strings.dart", this plan uses app/lib/l10n/app_bn.arb.

Decision needed before execution
- D3. **The shell has to change again.** The লেনদেন tab can only show TransactionsScreen if app/lib/shell/app_shell.dart changes, and
  the spec doesn't list this change. Like D2 for spec 02, the proposal is exactly one extra change: the লেনদেন tab shows
  TransactionsScreen. Nothing else in the shell changes. Approve, or change the spec.
- D4. **Review on the phone conflicts with CLAUDE.md.** CLAUDE.md says "A device is not a user" and "v1 has one dashboard role: owner".
  Approve/reject on the phone means anyone holding the merchant's phone (e.g. a cashier) can approve a payment
  whose amount did not match. The product spec put this in the dashboard (FR-D6, owner only). The plan builds what
  spec 03 says (UI + mock only), but before the server step you must choose one:
  A. Keep review on the phone, and the server accepts a device review only under a rule you define (e.g. an owner PIN).
  B. Move approve/reject to the dashboard spec, and the phone only shows "রিভিউ দরকার" read-only.
  Then update CLAUDE.md or the spec so the two agree.

## 1. Files

### New files
Domain
- app/lib/domain/models/claim_info.dart - immutable ClaimInfo(claimId, orderRef, expectedAmountPoisha).
- app/lib/domain/review.dart - ReviewDecision (approve, reject, with toWire/fromWire) and ReviewResult (done, offline,
  notAllowed). A new file, so spec 01's enums.dart is not changed.

Transactions screen (app/lib/features/transactions/)
- transactions_screen.dart - the লেনদেন tab: one lazy CustomScrollView with the search box, chips, banner, count and a
  SliverList of TransactionCard.
- transaction_filter.dart - pure filterTransactions(list, {query, operator, statuses}).
- transactions_providers.dart - searchQueryProvider and operatorFilterProvider (they live outside the screen, so they keep
  their values when you switch tabs); filteredTransactionsProvider and mismatchCountProvider.
  This is a new file, so spec 01's providers.dart is not changed. transactionFilterProvider (spec 02) is only read and written.
- widgets/search_box.dart - search field with its own TextEditingController, kept alive so focus and cursor are kept.
- widgets/operator_chips.dart - "সব অপারেটর" + 4 operators; tapping the selected one again clears it.
- widgets/status_chips.dart - "সব", "নিশ্চিত", "যাচাই বাকি", "মেলেনি", "বাতিল"; several can show selected.
- widgets/review_banner.dart - amber "{n} টি পেমেন্টে টাকা মেলেনি — দেখুন" card.

Detail sheet (app/lib/features/transactions/detail/)
- show_transaction_detail.dart - showTransactionDetail(context, id): opens the bottom sheet. Used by লেনদেন and হোম
  (and later the queue).
- transaction_detail_sheet.dart - the sheet. Watches the transaction list by id, so it updates live.
- detail_format.dart - pure helpers: amountDifference(expectedPoisha, smsPoisha) -> "৳ 20.00 কম" / "... বেশি", and
  dhakaDateTime(utc) -> "29 Oct 2026, 06:25 PM" (uses spec 01's fixed UTC+6 offset).
- widgets/detail_row.dart - label/value row with an optional ⧉ copy (Clipboard + toast "কপি হয়েছে").
- widgets/server_reply_card.dart - "সার্ভারের উত্তর": SyncStatusLabel, code or —, message or "এখনো উত্তর আসেনি".
- widgets/raw_sms_box.dart - "মূল এসএমএস": monospace SelectableText (plain text only, wraps).
- widgets/review_card.dart - amber "রিভিউ দরকার" card: order, the two amounts, difference, the two buttons; running guard.
- widgets/review_confirm_dialog.dart - confirm dialog: both amounts, optional note (maxLength 200), "না" / "হ্যাঁ, নিশ্চিত".

Tests (app/test/features/transactions/)
- transactions_test_helpers.dart - pumps the screens with a fixed clock, fresh mocks, and a fake repository with custom
  items for special cases (e.g. "<b>x</b>", no payerNumber).
- transaction_filter_test.dart - the 5 filter cases from the criteria, plus spaces-only and empty search.
- detail_format_test.dart - difference "৳ 20.00 কম", the "বেশি" case and equal; dhakaDateTime sample.
- app/test/data/mock_review_test.dart - the mock review rules: notAllowed, offline, approve, reject; nothing changes on
  offline or notAllowed. (In test/data, next to spec 01's mock repository test; a new file.)
- transactions_screen_test.dart - search, chips, banner, count, empty state, filters kept across tabs.
- transaction_detail_test.dart - detail rows, copy, send button, live update, review flow, raw SMS as text, opening from হোম.

### Changed files from specs 01 and 02 - only what spec 03 allows, plus D3
- [CHANGED 01] app/lib/domain/models/sms_transaction.dart - add `ClaimInfo? claim` (constructor + copyWith).
  (Allowed: "SmsTransaction gets an optional field claim")
- [CHANGED 01] app/lib/domain/repositories/transaction_repository.dart - add
  `Future<ReviewResult> review(String id, ReviewDecision decision, String? note)`. (Allowed: "TransactionRepository gets review()")
- [CHANGED 01] app/lib/data/mock/mock_transaction_repository.dart - implement review() with the 4 mock rules and the comment
  "MOCK - replaced by the server in spec 13". (Allowed: "The mock repository implements review()")
- [CHANGED 01] app/lib/data/mock/sample_transactions.dart - item 5 gets ClaimInfo("clm_demo_5", "#1045", 45000).
  (Allowed: "sample item 5 gets a ClaimInfo")
- [CHANGED 02] app/lib/features/home/widgets/latest_transactions.dart - TransactionCard onTap calls showTransactionDetail.
  (Allowed: "The হোম TransactionCard onTap opens the detail sheet")
- [CHANGED 01] app/lib/l10n/app_bn.arb - all new spec 03 strings with {n}/{orderRef}/{expected}/{amount}/{difference}
  placeholders. (Allowed: "New strings")
- [CHANGED 01, needs D3] app/lib/shell/app_shell.dart - the লেনদেন tab shows TransactionsScreen.

### Needed from earlier plans (no change in spec 03)
- TransactionCard (spec 02) must already show "প্রেরক: —" when payerNumber is null. Plan 02 is updated to build it that
  way, so spec 03 does not have to touch transaction_card.dart.
- The "—" sign comes from app_bn.arb like every other text.

### Not changed (on purpose)
- enums.dart, providers.dart, core/time.dart, core/money.dart, all spec 01 widgets including TransactionCard (spec 02):
  unchanged. New code lives in new files instead.
- All spec 01 and 02 test files: unchanged; they must still pass as they are.
- pubspec.yaml: unchanged, no new packages. Clipboard is from flutter/services.

## 2. Order of work

0. Specs 01 and 02 built and green (blocked: font files). Get your answer on D3.
1. ClaimInfo, review.dart, the SmsTransaction field, the repository method, the mock review() and the sample item 5
   claim. flutter analyze; flutter test (01 + 02 still green).
2. transaction_filter.dart and detail_format.dart, with their unit tests and mock_review_test.dart. flutter analyze; flutter test.
3. New strings in app_bn.arb. flutter analyze.
4. transactions_providers.dart. flutter analyze.
5. The লেনদেন screen widgets, then transactions_screen.dart, then the shell change (D3). flutter analyze.
6. The detail sheet widgets, review card and dialog, then show_transaction_detail.dart. flutter analyze.
7. Hook up the হোম card onTap (latest_transactions.dart). flutter analyze.
8. Widget tests. Full flutter test.
9. flutter build apk --debug, then the searches in section 3.
10. You check the list and the detail by eye on an emulator.

## 3. Acceptance criteria -> check

| Criterion | Check |
|---|---|
| flutter analyze: no issues | "No issues found!" |
| filter: "9k48" finds 1 | transaction_filter_test |
| filter: "  0181  " finds 1 | transaction_filter_test (item 2, payer 01812345678) |
| filter: operator bkash finds 2 | transaction_filter_test (items 1, 5) |
| filter: {mismatch, rejected} finds 1 | transaction_filter_test (item 5) |
| filter: rocket + {verified} finds 0 | transaction_filter_test |
| Difference 45000 vs 43000 -> "৳ 20.00 কম" | detail_format_test |
| Search keeps focus and narrows the list | transactions_screen_test: enterText "9k48", hasFocus still true, 1 card |
| bKash, then bKash again -> all 5 | transactions_screen_test |
| Banner "1 টি পেমেন্টে টাকা মেলেনি — দেখুন"; tap -> 1 item | transactions_screen_test |
| Item 1 detail: TrxID 9K48X7Z2, reference ORD-101; ⧉ -> "কপি হয়েছে" | transaction_detail_test (also checks the clipboard text) |
| Item 3 shows "⟳ এখনই পাঠান"; item 1 does not | transaction_detail_test |
| Item 5: review card; approve + "হ্যাঁ, নিশ্চিত" -> "পেমেন্ট নিশ্চিত ✓", card gone | transaction_detail_test |
| Reject while offline -> "ইন্টারনেট নেই — পরে চেষ্টা করুন", nothing changes | transaction_detail_test: setOnline(false), item 5 still mismatch |
| Raw "<b>x</b>" shows as literal text | transaction_detail_test with the fake repository |
| Tapping a card on হোম opens the same sheet | transaction_detail_test: pump HomeScreen, tap a card, find TransactionDetailSheet |
| flutter test passes in full (01 + 02 too) | full `flutter test`, earlier test files unchanged |
| flutter build apk --debug succeeds | exits 0, app-debug.apk exists |
| List and detail match the reference | You check by eye on an emulator |

Functional rules and edge cases (not listed as criteria, checked too)

| Rule | Check |
|---|---|
| Spaces-only search = empty search | transaction_filter_test |
| Typing keeps the cursor position | transactions_screen_test: after each enterText the selection offset is at the end of the text |
| Operator and status chips are one row that scrolls sideways | transactions_screen_test: each chip row is a horizontal Scrollable |
| List is newest first | transactions_screen_test: card order matches receivedAt descending |
| Raw "<img onerror=...>" shows as plain text | transaction_detail_test: the literal text is found; no Image or HTML widget in the tree |
| Approve done -> toast "অনুমোদন দেওয়া হয়েছে"; afterwards no review buttons (cannot be undone) | transaction_detail_test |
| ✕ and "বন্ধ করুন" both close the sheet | transaction_detail_test |
| Status chips: {mismatch, rejected} from হোম shows 2 selected; tapping a chip sets that one; "সব" sets null | transactions_screen_test |
| Selected operator chip uses the operator colour | transactions_screen_test reads the chip's decoration colour |
| Banner hidden when nothing is mismatch | transactions_screen_test after approving item 5 |
| "{n} টি লেনদেন" count | transactions_screen_test |
| Empty result -> "কিছু পাওয়া যায়নি" / hint | transactions_screen_test (query "zzz") |
| Filters and search kept when switching tabs | transactions_screen_test: set filters, go to হোম and back |
| Lazy list | review: SliverList / builder, no Column of all items |
| Rows with no value hidden; no payerNumber -> "—", no copy button | transaction_detail_test with the fake repository |
| Server card: code "—" and "এখনো উত্তর আসেনি" when empty | transaction_detail_test (item 4) |
| "⟳ এখনই পাঠান" calls retry and closes the sheet | transaction_detail_test |
| Sheet updates live; shows "পাঠানো হচ্ছে…" while retrying | transaction_detail_test: start retry, open sheet, find label |
| claim null on a mismatch item -> "কোনো অর্ডারের সাথে যুক্ত নয়", no buttons | transaction_detail_test with the fake repository |
| Dialog repeats both amounts; note max 200 | transaction_detail_test |
| Reject done -> "বাতিল করা হয়েছে"; notAllowed -> "এটি আর রিভিউ করা যাবে না" | transaction_detail_test + mock_review_test |
| Review buttons disabled while running | transaction_detail_test: onPressed null during the call (fake with a delay) |
| Mock rules (notAllowed / offline change nothing) | mock_review_test |
| No double, no Color( outside colors.dart, MOCK comment present | searches (same as spec 01) |
| Earlier files changed only as allowed | review the changed-file list in section 1 before marking done |

## 4. Unclear or possibly wrong in the spec

1. **The shell change is not listed.** Needed so the লেনদেন tab shows TransactionsScreen -> D3.
2. **strings.dart vs ARB.** The plan uses app_bn.arb (D1 = A).
3. **Where search and operator state lives.** They must survive tab switches, but the spec only lists transactionFilterProvider (statuses). Plan:
   two new providers in a new feature file (transactions_providers.dart), so spec 01's providers.dart stays unchanged. Is that OK?
4. **Missing payer: hidden or "—"?** "Rows with no value are hidden" conflicts with "no payerNumber shows '—'". Plan: the
   প্রেরকের নম্বর row always shows, with "—" and no copy button; every other empty row is hidden.
5. **Which way the difference goes.** The example (expected 45000, SMS 43000 -> "কম") means the word describes the SMS against the
   order: SMS lower = "কম", SMS higher = "বেশি". When the amounts are equal, the plan shows "৳ 0.00" with no word.
   (A mismatch item with equal amounts shouldn't happen.)
6. **The note is not stored.** review() takes a note, but the mock ignores it and nothing shows it. The server stores it later in audit_log.
7. **notAllowed can't be reached by tapping.** The review buttons only show for mismatch items, so the toast only appears if the status changes
   while the dialog is open. It is tested at the repository level and with a fake in the widget test.
8. **Review on the phone.** See D4. Also: the mock changing verifyStatus is acceptable only because it carries the MOCK
   comment (CLAUDE.md: "Never mark anything verified on the device"); the real review goes through the server.
9. **Full date format.** "29 Oct 2026, 06:25 PM" uses English month names (intl, locale en). Say if you want Bangla month names.
10. **Spec numbers.** "MOCK - replaced by the server in spec 13" doesn't match the roadmap. The text is kept as written.
11. **Reference still missing.** reference/bdpay-sms-verifier-v2.html is still missing. Plan uses the root "BDPay SMS Verifier.html" (it has
    the list and the detail popup) plus the spec's colours. It has no review card, so that card follows its card style.
12. **The reference uses a centred dialog, not a bottom sheet.** Its detail is a centred popup (.ov/.dl); the spec asks for a bottom sheet.
    The spec wins; the sheet uses the same colours, radius and layout as the popup.

## 5. Review log

Review 1 against spec 03 and CLAUDE.md:
- Outside Scope: nothing found. All new code lives in lib/features/transactions/ or in new domain files.
  transactions_providers.dart is new feature code, not a change to earlier code (it still needs your OK, section 4 item 3).
  Moved mock_review_test.dart to test/data/ next to the other mock test.
- Earlier files changed without permission: only app_shell.dart (-> D3). Hidden dependency found: the spec 02
  TransactionCard must handle a null payerNumber; plan 02 now builds it that way, so transaction_card.dart is not
  changed here.
- Criteria without a check: none. Added checks for rules that had none: cursor position, sideways chip rows,
  newest-first order, the <img onerror> case, the approve toast and no undo, and closing with ✕ / "বন্ধ করুন".
- CLAUDE.md: review on the phone conflicts with "A device is not a user" and the owner-only role -> D4. The mock marking
  verified is allowed only as MOCK code. Text (including "—") comes from ARB, money is int, dates are in Dhaka time,
  the raw SMS is plain text, no new packages.
