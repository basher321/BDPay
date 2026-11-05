import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/theme/colors.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/features/transactions/detail/transaction_detail_sheet.dart';

import 'queue_test_helpers.dart';

void main() {
  testWidgets('header count, oldest first, Rocket card rows and its red retry line', (tester) async {
    await pumpQueue(tester);
    expect(find.text('পাঠানো বাকি (2)'), findsOneWidget);
    expect(find.text('ইন্টারনেট আছে'), findsOneWidget);
    final upay = tester.getTopLeft(find.byKey(const ValueKey('queueCard-4'))).dy;
    final rocket = tester.getTopLeft(find.byKey(const ValueKey('queueCard-3'))).dy;
    expect(upay, lessThan(rocket));

    final card = find.byKey(const ValueKey('queueCard-3'));
    expect(find.descendant(of: card, matching: find.text('Rocket')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Trx: 24010200123')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('৳ 1,500.00')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('প্রেরক: 017123456789 • 50 মিনিট আগে')), findsOneWidget);
    expect(find.text('2 বার চেষ্টা ব্যর্থ • নেটওয়ার্ক সংযোগ নেই'), findsOneWidget);
    expect(textColor(tester, 'retryLine-3'), AppColors.er);
  });

  testWidgets('offline: send all and every send button disabled; "ইন্টারনেট নেই"', (tester) async {
    final h = await pumpQueue(tester);
    await h.health.setOnline(false);
    await settle(tester);
    expect(find.text('ইন্টারনেট নেই'), findsOneWidget);
    expect(buttonByKey(tester, 'sendAll').onPressed, isNull);
    expect(buttonByKey(tester, 'send-3').onPressed, isNull);
    expect(buttonByKey(tester, 'send-4').onPressed, isNull);
  });

  testWidgets('online: send all empties the list, shows the empty state and the toast', (tester) async {
    await pumpQueue(tester);
    await tester.tap(find.byKey(const Key('sendAll')));
    await tester.pump();
    expect(buttonByKey(tester, 'sendAll').onPressed, isNull);
    await finishSend(tester);
    expect(find.byKey(const Key('queueEmpty')), findsOneWidget);
    expect(find.text('সব পাঠানো হয়েছে!'), findsOneWidget);
    expect(find.text('কোনো এসএমএস বাকি নেই।'), findsOneWidget);
    expect(find.text('সব পাঠানো হয়েছে'), findsOneWidget);
    expect(find.byKey(const Key('queueBadge')), findsNothing);
    expect(buttonByKey(tester, 'sendAll').onPressed, isNull);
    await clearToast(tester);
  });

  testWidgets('going offline during send all: items fail and stay, retryCount + 1, toast', (tester) async {
    final h = await pumpQueue(tester);
    await tester.tap(find.byKey(const Key('sendAll')));
    await tester.pump();
    await h.health.setOnline(false);
    await finishSend(tester);
    expect(find.text('2 টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে'), findsOneWidget);
    expect(find.text('পাঠানো বাকি (2)'), findsOneWidget);
    expect(find.text('3 বার চেষ্টা ব্যর্থ • নেটওয়ার্ক সংযোগ নেই'), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('"বিস্তারিত" opens the detail sheet for that item', (tester) async {
    await pumpQueue(tester);
    await tester.tap(find.byKey(const Key('details-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final sheet = find.byType(TransactionDetailSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('24010200123')), findsOneWidget);
  });

  testWidgets('stale and stuck warnings, alone and together, in amber / red', (tester) async {
    await pumpQueue(tester, items: [
      customTx(id: 'old', syncStatus: SyncStatus.queued, age: const Duration(hours: 25)),
      customTx(id: 'stuck', syncStatus: SyncStatus.failed, retryCount: 5),
      customTx(id: 'both', syncStatus: SyncStatus.failed, retryCount: 5, age: const Duration(hours: 26)),
    ]);
    expect(find.byKey(const Key('staleLine-old')), findsOneWidget);
    expect(find.byKey(const Key('stuckLine-old')), findsNothing);
    expect(find.byKey(const Key('stuckLine-stuck')), findsOneWidget);
    expect(find.byKey(const Key('staleLine-stuck')), findsNothing);
    expect(find.byKey(const Key('staleLine-both')), findsOneWidget);
    expect(find.byKey(const Key('stuckLine-both')), findsOneWidget);
    expect(find.text('২৪ ঘণ্টার বেশি পুরনো — গ্রাহকের অর্ডার বাতিল হয়ে যেতে পারে'), findsNWidgets(2));
    expect(textColor(tester, 'staleLine-old'), AppColors.wa);
    expect(textColor(tester, 'stuckLine-stuck'), AppColors.er);
  });

  testWidgets('a sending item: "পাঠানো হচ্ছে…", both buttons shown, send disabled; send all disabled', (tester) async {
    await pumpQueue(tester, items: [customTx(id: 's', syncStatus: SyncStatus.sending)]);
    final card = find.byKey(const ValueKey('queueCard-s'));
    expect(find.descendant(of: card, matching: find.text('পাঠানো হচ্ছে…')), findsOneWidget);
    expect(find.byKey(const Key('details-s')), findsOneWidget);
    expect(buttonByKey(tester, 'send-s').onPressed, isNull);
    expect(buttonByKey(tester, 'details-s').onPressed, isNotNull);
    expect(buttonByKey(tester, 'sendAll').onPressed, isNull);
  });

  testWidgets('turning autoSend off changes the info card text', (tester) async {
    final h = await pumpQueue(tester);
    expect(find.textContaining('সংযোগ ফিরলে নিজে থেকেই পাঠানো হবে।'), findsOneWidget);
    await h.settings.update(h.settings.current.copyWith(autoSend: false));
    await settle(tester);
    expect(
      find.text('ইন্টারনেট না থাকলেও এসএমএস ফোনে নিরাপদে জমা থাকে। অটো পাঠানো বন্ধ আছে — নিচের বোতাম চাপুন। '
          'একই লেনদেন দুবার গণনা হবে না।'),
      findsOneWidget,
    );
  });

  testWidgets('one card send: only that item is sent', (tester) async {
    final h = await pumpQueue(tester);
    await tester.tap(find.byKey(const Key('send-4')));
    await tester.pump();
    expect(buttonByKey(tester, 'send-4').onPressed, isNull);
    await finishSend(tester);
    expect(find.byKey(const ValueKey('queueCard-4')), findsNothing);
    expect(find.byKey(const ValueKey('queueCard-3')), findsOneWidget);
    expect(h.transactions.current.firstWhere((t) => t.id == '3').syncStatus, SyncStatus.failed);
  });
}
