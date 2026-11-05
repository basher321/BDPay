# 03 Transactions list, detail and manual review

Purpose
Build the লেনদেন tab so the merchant can find any payment, open its full detail,
and decide by hand on payments where the TrxID matched but the amount did not.
It must look and behave like the transactions screen and detail popup in
reference/bdpay-sms-verifier-v2.html.

Scope
- The লেনদেন screen in lib/features/transactions/: search box, operator chips,
  status chips, result count, a review banner and the list.
- A transaction detail bottom sheet in lib/features/transactions/detail/, opened from the
  লেনদেন list, the হোম latest list and (later) the queue.
- Manual review (approve / reject) inside the detail sheet, for mismatch items only.
- Additions to earlier code, and only these:
  - SmsTransaction gets an optional field claim (ClaimInfo).
  - TransactionRepository gets review().
  - The mock repository implements review(), and sample item 5 gets a ClaimInfo.
  - The হোম TransactionCard onTap opens the detail sheet.
  - New strings in strings.dart.
- No new packages. Copy uses Flutter's built-in Clipboard.
- Not in scope: CSV export, editing or deleting a transaction, the queue screen, real server calls.

Contract
New model ClaimInfo (immutable): claimId String, orderRef String, expectedAmountPoisha int.
SmsTransaction: add claim ClaimInfo? (null when no order is linked yet).
Sample item 5 gets claim: claimId "clm_demo_5", orderRef "#1045", expectedAmountPoisha 45000.

New enum ReviewDecision: approve, reject (wire names approve, reject).
New enum ReviewResult: done, offline, notAllowed.

TransactionRepository (added):
- Future<ReviewResult> review(String id, ReviewDecision decision, String? note)
  Mock rules:
  - verifyStatus is not mismatch -> notAllowed, nothing changes.
  - offline -> offline, nothing changes.
  - approve -> verifyStatus verified, serverMessage "ম্যানুয়ালি অনুমোদিত", returns done.
  - reject  -> verifyStatus rejected, serverMessage "ম্যানুয়ালি বাতিল", returns done.
  - Mark with the comment "MOCK - replaced by the server in spec 13".

Pure filter function in lib/features/transactions/transaction_filter.dart:
  List<SmsTransaction> filterTransactions(list, {String query, MfsOperator? operator, Set<VerifyStatus>? statuses})

Functional rules
1. Search
   - Placeholder "🔍 TrxID বা প্রেরকের নম্বর".
   - Matches trxId or payerNumber, case-insensitive, ignoring leading/trailing spaces.
   - Typing never loses focus or cursor position.
2. Operator chips (one row, scrolls sideways)
   - "সব অপারেটর", then bKash, Nagad, Rocket, Upay. One selected at a time.
   - Tapping the selected operator again returns to "সব অপারেটর".
   - A selected operator chip uses that operator's color, like the reference.
3. Status chips (one row, scrolls sideways)
   - "সব", "নিশ্চিত", "যাচাই বাকি", "মেলেনি", "বাতিল".
   - They read and write transactionFilterProvider.
   - When the filter came from the হোম "মেলেনি / বাতিল" card ({mismatch, rejected}),
     both chips show selected. Tapping any chip changes to that single status. "সব" sets null.
4. Review banner
   - When at least one transaction is mismatch, show an amber card above the list:
     "{n} টি পেমেন্টে টাকা মেলেনি — দেখুন". Tapping it sets the filter to {mismatch}.
   - Hidden when there are none.
5. Result count and list
   - "{n} টি লেনদেন" for the filtered list.
   - Newest first, using TransactionCard. Use a lazily built list.
   - Empty result: EmptyState 🔍 "কিছু পাওয়া যায়নি" / "ফিল্টার বদলে আবার চেষ্টা করুন".
   - Filters and search stay set when switching tabs and coming back.
6. Detail sheet
   - Top: operator badge and a ✕ close button. Then the amount (28, emerald) and the VerifyStatusChip.
   - Rows (label left, value right); rows with no value are hidden:
     TrxID (with ⧉ copy), প্রেরকের নম্বর (with ⧉ copy), ধরন, রেফারেন্স, নতুন ব্যালেন্স,
     সময় (full date and time in Dhaka, e.g. 29 Oct 2026, 06:25 PM).
   - Copy puts the value on the clipboard and shows toast "কপি হয়েছে".
   - "সার্ভারের উত্তর" card: অবস্থা (SyncStatusLabel), কোড (or —), the server message
     (or "এখনো উত্তর আসেনি").
   - "মূল এসএমএস": the raw SMS in a monospace box, plain text, wraps, selectable.
   - Bottom buttons: "বন্ধ করুন", plus "⟳ এখনই পাঠান" only when syncStatus is queued or failed
     (calls retry and closes the sheet).
   - The sheet updates live if the transaction changes while it is open.
7. Manual review (only when verifyStatus is mismatch)
   - An amber "রিভিউ দরকার" card in the sheet, above the server card, showing:
     অর্ডার {orderRef}, অর্ডারের টাকা {expected}, এসএমএস-এ টাকা {amount},
     পার্থক্য {difference}.
   - When claim is null, show "কোনো অর্ডারের সাথে যুক্ত নয়" and no review buttons.
   - Two buttons: "অনুমোদন দিন" (primary) and "বাতিল করুন" (outline, red text).
   - Each opens a confirm dialog that repeats both amounts, has an optional note field
     (max 200 characters), and buttons "না" / "হ্যাঁ, নিশ্চিত".
   - Results: done -> toast "অনুমোদন দেওয়া হয়েছে" or "বাতিল করা হয়েছে", and the review card
     disappears; offline -> toast "ইন্টারনেট নেই — পরে চেষ্টা করুন"; notAllowed -> toast
     "এটি আর রিভিউ করা যাবে না".
   - Buttons are disabled while a review is running. A decision cannot be undone in the app.

Edge cases
- Search with only spaces behaves like an empty search.
- Search "9k48" finds TrxID 9K48X7Z2.
- A transaction with no payerNumber shows "—" and its copy button is hidden.
- Raw SMS containing <img onerror=...> shows as plain text and runs nothing.
- Expected amount smaller or larger than the SMS amount: the difference is shown as a
  positive value with "বেশি" or "কম" (e.g. "৳ 20.00 কম").
- Opening the detail of an item while its retry is running shows "পাঠানো হচ্ছে…".

Non-functional rules
- Filtering and the difference calculation are pure functions with unit tests.
- Money is int poisha only. No double anywhere.
- flutter analyze reports zero issues.

Acceptance criteria
- flutter analyze: no issues.
- Unit tests for filterTransactions: query "9k48" finds 1; query "  0181  " finds 1;
  operator bkash finds 2; statuses {mismatch, rejected} finds 1; operator rocket +
  statuses {verified} finds 0.
- Unit test for the difference: expected 45000, SMS 43000 -> "৳ 20.00 কম".
- Widget tests:
  - typing in search keeps focus and narrows the list.
  - tapping bKash then bKash again returns to all 5.
  - the review banner shows "1 টি পেমেন্টে টাকা মেলেনি — দেখুন" and tapping it shows 1 item.
  - opening item 1 shows TrxID 9K48X7Z2 and reference ORD-101; tapping ⧉ shows "কপি হয়েছে".
  - item 3 (failed) shows "⟳ এখনই পাঠান"; item 1 (sent) does not.
  - item 5 shows the review card; approve + "হ্যাঁ, নিশ্চিত" changes its chip to
    "পেমেন্ট নিশ্চিত ✓" and the review card disappears.
  - reject while offline shows "ইন্টারনেট নেই — পরে চেষ্টা করুন" and nothing changes.
  - a raw SMS containing "<b>x</b>" shows the literal text "<b>x</b>".
  - tapping a card on হোম opens the same detail sheet.
- flutter test passes in full (spec 01 and 02 tests still pass).
- flutter build apk --debug succeeds.
- I check by eye on an emulator that the list and detail match the reference.

Assumptions
- Specs 01 and 02 are done and all their tests pass.
