import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/claim_info.dart';
import 'package:verifier/domain/review.dart';
import 'package:verifier/features/transactions/detail/transaction_detail_sheet.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/widgets/app_button.dart';

import 'transactions_test_helpers.dart';

Finder inSheet(Finder f) => find.descendant(of: find.byType(TransactionDetailSheet), matching: f);

AppButton button(WidgetTester tester, String key) => tester.widget<AppButton>(find.byKey(Key(key)));

Future<void> confirm(WidgetTester tester, String buttonKey) async {
  await tester.tap(find.byKey(Key(buttonKey)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byKey(const Key('confirmYes')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await settle(tester);
}

void main() {
  testWidgets('item 1: TrxID, reference, copy', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpAppAt(tester);
    await openDetail(tester, '1');
    expect(inSheet(find.text('9K48X7Z2')), findsOneWidget);
    expect(inSheet(find.text('ORD-101')), findsOneWidget);
    expect(inSheet(find.text('৳ 15,340.50')), findsOneWidget);
    expect(inSheet(find.text('29 Oct 2026, 11:55 AM')), findsOneWidget);
    await tester.tap(find.byKey(const Key('copyTrxId')));
    await settle(tester);
    expect(find.text('কপি হয়েছে'), findsOneWidget);
    expect(copied, '9K48X7Z2');
    await clearToast(tester);
  });

  testWidgets('send now: shown for failed item 3, not for sent item 1; it retries and closes', (tester) async {
    final h = await pumpAppAt(tester);
    await openDetail(tester, '1');
    expect(find.byKey(const Key('sendNowButton')), findsNothing);
    await tester.tap(find.byKey(const Key('closeButton')));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailSheet), findsNothing);

    await openDetail(tester, '3');
    expect(find.text('⟳ এখনই পাঠান'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sendNowButton')));
    await tester.pump();
    expect(h.transactions.current.firstWhere((t) => t.id == '3').syncStatus, SyncStatus.sending);
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailSheet), findsNothing);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('✕ closes the sheet', (tester) async {
    await pumpAppAt(tester);
    await openDetail(tester, '2');
    await tester.tap(find.byKey(const Key('detailClose')));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailSheet), findsNothing);
  });

  testWidgets('item 5 review: approve -> verified chip, card gone, toast, no undo', (tester) async {
    await pumpAppAt(tester);
    await openDetail(tester, '5');
    expect(find.byKey(const Key('reviewCard')), findsOneWidget);
    expect(inSheet(find.text('অর্ডার #1045')), findsOneWidget);
    expect(inSheet(find.text('৳ 20.00 কম')), findsOneWidget);

    await tester.tap(find.byKey(const Key('approveButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The dialog repeats both amounts and limits the note.
    final dialog = find.byType(Dialog);
    expect(find.descendant(of: dialog, matching: find.text('৳ 450.00')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('৳ 430.00')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('noteField'))).maxLength, 200);
    await tester.enterText(find.byKey(const Key('noteField')), 'ক্যাশে বাকি নেওয়া হয়েছে');
    await tester.tap(find.byKey(const Key('confirmYes')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await settle(tester);

    expect(inSheet(find.text('পেমেন্ট নিশ্চিত ✓')), findsOneWidget);
    expect(find.byKey(const Key('reviewCard')), findsNothing);
    expect(find.byKey(const Key('approveButton')), findsNothing);
    expect(find.text('অনুমোদন দেওয়া হয়েছে'), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('reject done -> "বাতিল করা হয়েছে"', (tester) async {
    await pumpAppAt(tester);
    await openDetail(tester, '5');
    await confirm(tester, 'rejectButton');
    expect(find.text('বাতিল করা হয়েছে'), findsOneWidget);
    expect(inSheet(find.text('বাতিল')), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('"না" in the dialog changes nothing', (tester) async {
    final h = await pumpAppAt(tester);
    await openDetail(tester, '5');
    await tester.tap(find.byKey(const Key('approveButton')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('confirmNo')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.transactions.current.firstWhere((t) => t.id == '5').verifyStatus, VerifyStatus.mismatch);
  });

  testWidgets('reject while offline -> toast and nothing changes', (tester) async {
    final h = await pumpAppAt(tester);
    await h.health.setOnline(false);
    await settle(tester);
    await openDetail(tester, '5');
    await confirm(tester, 'rejectButton');
    expect(find.text('ইন্টারনেট নেই — পরে চেষ্টা করুন'), findsOneWidget);
    expect(h.transactions.current.firstWhere((t) => t.id == '5').verifyStatus, VerifyStatus.mismatch);
    expect(find.byKey(const Key('reviewCard')), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('notAllowed -> "এটি আর রিভিউ করা যাবে না"', (tester) async {
    late ControlledReviewRepository repo;
    await pumpAppAt(tester, wrap: (mock) => repo = ControlledReviewRepository(mock));
    repo.forcedResult = ReviewResult.notAllowed;
    await openDetail(tester, '5');
    await confirm(tester, 'approveButton');
    expect(find.text('এটি আর রিভিউ করা যাবে না'), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('review buttons are disabled while a review is running', (tester) async {
    late ControlledReviewRepository repo;
    await pumpAppAt(tester, wrap: (mock) => repo = ControlledReviewRepository(mock));
    repo.hold = Completer<void>();
    await openDetail(tester, '5');
    await confirm(tester, 'approveButton');
    expect(button(tester, 'approveButton').onPressed, isNull);
    expect(button(tester, 'rejectButton').onPressed, isNull);
    repo.hold!.complete();
    await settle(tester);
    await clearToast(tester);
  });

  testWidgets('raw SMS with markup shows as literal text', (tester) async {
    await pumpAppAt(tester, items: [
      customTx(id: 'b', rawBody: '<b>x</b>'),
      customTx(id: 'img', rawBody: '<img src=x onerror=alert(1)>', age: const Duration(minutes: 2)),
    ]);
    await openDetail(tester, 'b');
    expect(inSheet(find.text('<b>x</b>')), findsOneWidget);
    await tester.tap(find.byKey(const Key('closeButton')));
    await tester.pumpAndSettle();
    await openDetail(tester, 'img');
    expect(inSheet(find.text('<img src=x onerror=alert(1)>')), findsOneWidget);
    expect(inSheet(find.byType(Image)), findsNothing);
  });

  testWidgets('no payer -> "—" and no copy button', (tester) async {
    await pumpAppAt(tester, items: [customTx(id: 'np', payerNumber: null)]);
    await openDetail(tester, 'np');
    expect(inSheet(find.text('—')), findsWidgets);
    expect(find.byKey(const Key('copyPayer')), findsNothing);
    expect(find.byKey(const Key('copyTrxId')), findsOneWidget);
  });

  testWidgets('server card: code "—" and "এখনো উত্তর আসেনি" when empty (item 4)', (tester) async {
    await pumpAppAt(tester);
    await openDetail(tester, '4');
    expect(inSheet(find.text('এখনো উত্তর আসেনি')), findsOneWidget);
    expect(inSheet(find.text('—')), findsOneWidget);
    expect(inSheet(find.text('ORD-101')), findsNothing);
  });

  testWidgets('sheet updates live and shows "পাঠানো হচ্ছে…" while retrying', (tester) async {
    final h = await pumpAppAt(tester);
    final done = h.transactions.retry('4');
    await settle(tester);
    await openDetail(tester, '4');
    expect(inSheet(find.text('পাঠানো হচ্ছে…')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    await done;
    await settle(tester);
    expect(inSheet(find.text('পাঠানো হয়েছে')), findsOneWidget);
    expect(inSheet(find.text('পেমেন্ট নিশ্চিত ✓')), findsOneWidget);
  });

  testWidgets('mismatch with no claim -> "কোনো অর্ডারের সাথে যুক্ত নয়", no buttons', (tester) async {
    await pumpAppAt(tester, items: [customTx(id: 'nc', verifyStatus: VerifyStatus.mismatch)]);
    await openDetail(tester, 'nc');
    expect(inSheet(find.text('কোনো অর্ডারের সাথে যুক্ত নয়')), findsOneWidget);
    expect(find.byKey(const Key('approveButton')), findsNothing);
  });

  testWidgets('claim larger than SMS shows "বেশি" the other way round', (tester) async {
    await pumpAppAt(tester, items: [
      customTx(
        id: 'more',
        verifyStatus: VerifyStatus.mismatch,
        claim: const ClaimInfo(claimId: 'c', orderRef: '#1', expectedAmountPoisha: 8000),
      ),
    ]);
    await openDetail(tester, 'more');
    expect(inSheet(find.text('৳ 20.00 বেশি')), findsOneWidget);
  });

  testWidgets('tapping a card on হোম opens the same detail sheet', (tester) async {
    await pumpAppAt(tester, tab: AppTab.home);
    await openDetail(tester, '1');
    expect(find.byType(TransactionDetailSheet), findsOneWidget);
    expect(inSheet(find.text('ORD-101')), findsOneWidget);
  });
}
