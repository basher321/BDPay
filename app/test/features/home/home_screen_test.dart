import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/data/providers.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/domain/repositories/transaction_repository.dart';
import 'package:verifier/domain/review.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/widgets/app_button.dart';
import 'package:verifier/widgets/transaction_card.dart';

import '../../test_helpers.dart';
import 'home_test_helpers.dart';

/// Counts retryAllPending calls and passes everything to the mock.
class CountingRepository implements TransactionRepository {
  CountingRepository(this.inner);

  final MockTransactionRepository inner;
  int sendAllCalls = 0;

  @override
  Stream<List<SmsTransaction>> watchAll() => inner.watchAll();

  @override
  Future<void> retry(String id) => inner.retry(id);

  @override
  Future<void> retryAllPending() {
    sendAllCalls++;
    return inner.retryAllPending();
  }

  @override
  Future<ReviewResult> review(String id, ReviewDecision decision, String? note) => inner.review(id, decision, note);
}

SmsTransaction extra(int i) => buildSampleTransactions(fixedNow)[0].withId('extra$i');

extension on SmsTransaction {
  SmsTransaction withId(String newId) => SmsTransaction(
        id: newId,
        operator: operator,
        sender: sender,
        trxId: '$trxId$newId',
        amountPoisha: amountPoisha,
        payerNumber: payerNumber,
        kind: kind,
        verifyStatus: verifyStatus,
        syncStatus: syncStatus,
        receivedAt: receivedAt.subtract(const Duration(hours: 3)),
        rawBody: rawBody,
      );
}

AppButton sendButton(WidgetTester tester) => tester.widget<AppButton>(find.byKey(const Key('sendPending')));

/// Lets the 700 ms mock send finish, the list stream deliver, and the toast go away.
Future<void> finishSend(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 750));
  await tester.pump();
  await tester.pump();
}

Future<void> clearToast(WidgetTester tester) => tester.pump(const Duration(seconds: 2));

void main() {
  testWidgets('sections are in spec order', (tester) async {
    final h = await pumpHome(tester);
    await h.settings.update(h.settings.current.copyWith(developerMode: true));
    await settle(tester);
    final keys = ['deviceCard', 'healthCard', 'todayTotalCard', 'countVerified', 'sendPending', 'devLabButton', 'op-bkash', 'seeAll'];
    final ys = [for (final k in keys) tester.getTopLeft(find.byKey(Key(k))).dy];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i], greaterThan(ys[i - 1]), reason: '${keys[i]} should be below ${keys[i - 1]}');
    }
  });

  testWidgets('today total and operator counts from sample data', (tester) async {
    await pumpHome(tester);
    expect(find.text('৳ 3,750.00'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('op-bkash')), matching: find.text('2 টি')), findsOneWidget);
  });

  testWidgets('health header 1 problem; battery fix -> all ok', (tester) async {
    await pumpHome(tester);
    expect(find.text('1 টি সমস্যা'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fixBattery')));
    await settle(tester);
    expect(find.text('সব ঠিক আছে ✓'), findsOneWidget);
    expect(find.byKey(const Key('fixBattery')), findsNothing);
  });

  testWidgets('offline: server row, internet row and 2 problems', (tester) async {
    final h = await pumpHome(tester);
    await h.health.setOnline(false);
    await settle(tester);
    expect(find.textContaining('সার্ভারে সংযোগ নেই'), findsOneWidget);
    expect(find.text('2 টি সমস্যা'), findsOneWidget);
    expect(find.text('নেই — এসএমএস ফোনে জমা থাকবে'), findsOneWidget);
  });

  testWidgets('offline in the full app also turns the pill red', (tester) async {
    final mocks = await pumpApp(tester);
    await mocks.health.setOnline(false);
    await tester.pump();
    await tester.pump();
    expect(find.text('অফলাইন'), findsOneWidget);
    expect(find.textContaining('সার্ভারে সংযোগ নেই'), findsOneWidget);
  });

  testWidgets('monitoring switch off changes the subtitle and icon', (tester) async {
    await pumpHome(tester);
    expect(find.text('◉'), findsOneWidget);
    await tester.tap(find.byKey(const Key('monitoringSwitch')));
    await settle(tester);
    expect(find.text('মনিটরিং বন্ধ — নতুন পেমেন্ট ধরা হবে না'), findsOneWidget);
    expect(find.text('⊘'), findsOneWidget);
    expect(find.text('বন্ধ আছে'), findsOneWidget);
  });

  testWidgets('send button: label, disabled while running, gone after (online), toast', (tester) async {
    await pumpHome(tester);
    expect(find.textContaining('বাকি 2 টি এখনই পাঠান'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sendPending')));
    await tester.pump();
    expect(sendButton(tester).onPressed, isNull);
    await finishSend(tester);
    expect(find.byKey(const Key('sendPending')), findsNothing);
    expect(find.text('সব পাঠানো হয়েছে'), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('send while offline -> some failed toast', (tester) async {
    final h = await pumpHome(tester);
    await h.health.setOnline(false);
    await settle(tester);
    await tester.tap(find.byKey(const Key('sendPending')));
    await finishSend(tester);
    expect(find.text('2 টি পাঠানো যায়নি — পরে আবার চেষ্টা হবে'), findsOneWidget);
    expect(find.byKey(const Key('sendPending')), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('double tap on send runs retryAllPending once', (tester) async {
    final h = HomeHarness();
    final counting = CountingRepository(h.transactions);
    await pumpHome(tester, repository: counting);
    await tester.tap(find.byKey(const Key('sendPending')));
    await tester.tap(find.byKey(const Key('sendPending')), warnIfMissed: false);
    await finishSend(tester);
    expect(counting.sendAllCalls, 1);
    await clearToast(tester);
  });

  testWidgets('developer button only in developer mode; opens পরীক্ষা', (tester) async {
    final h = await pumpHome(tester);
    expect(find.byKey(const Key('devLabButton')), findsNothing);
    await h.settings.update(h.settings.current.copyWith(developerMode: true));
    await settle(tester);
    expect(find.byKey(const Key('devLabButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('devLabButton')));
    await settle(tester);
    expect(h.container.read(selectedTabProvider), AppTab.devLab);
  });

  testWidgets('disabling Upay shows বন্ধ on its tile', (tester) async {
    final h = await pumpHome(tester);
    final ops = {...h.settings.current.enabledOperators}..remove(MfsOperator.upay);
    await h.settings.update(h.settings.current.copyWith(enabledOperators: ops));
    await settle(tester);
    expect(find.descendant(of: find.byKey(const Key('op-upay')), matching: find.text('বন্ধ')), findsOneWidget);
    expect(tester.widget<Opacity>(find.byKey(const Key('op-upay'))).opacity, 0.5);
  });

  testWidgets('count cards set the filter and switch to লেনদেন; সব দেখুন clears it', (tester) async {
    final h = await pumpHome(tester);
    await tester.tap(find.byKey(const Key('countVerified')));
    await settle(tester);
    expect(h.container.read(transactionFilterProvider), {VerifyStatus.verified});
    expect(h.container.read(selectedTabProvider), AppTab.transactions);

    await tester.tap(find.byKey(const Key('countPending')));
    await settle(tester);
    expect(h.container.read(transactionFilterProvider), {VerifyStatus.pending});

    await tester.tap(find.byKey(const Key('countBad')));
    await settle(tester);
    expect(h.container.read(transactionFilterProvider), {VerifyStatus.mismatch, VerifyStatus.rejected});

    h.container.read(selectedTabProvider.notifier).select(AppTab.home);
    await tester.tap(find.byKey(const Key('seeAll')));
    await settle(tester);
    expect(h.container.read(transactionFilterProvider), isNull);
    expect(h.container.read(selectedTabProvider), AppTab.transactions);
  });

  testWidgets('latest list shows at most 5 cards', (tester) async {
    await pumpHome(tester, items: [...buildSampleTransactions(fixedNow), extra(1)]);
    expect(find.byType(TransactionCard), findsNWidgets(5));
    expect(find.text('সব দেখুন (6)'), findsOneWidget);
  });

  testWidgets('no transactions: ৳ 0.00, counts 0, no send button, empty text', (tester) async {
    await pumpHome(tester, items: const []);
    expect(find.text('৳ 0.00'), findsOneWidget);
    expect(find.byKey(const Key('sendPending')), findsNothing);
    expect(find.text('এখনো কোনো লেনদেন নেই'), findsOneWidget);
    expect(find.text('এখনো আসেনি'), findsOneWidget);
    for (final k in ['countVerified', 'countPending', 'countBad']) {
      expect(find.descendant(of: find.byKey(Key(k)), matching: find.text('0')), findsOneWidget);
    }
  });

  testWidgets('"N মিনিট আগে" texts refresh on each tick', (tester) async {
    final h = await pumpHome(tester);
    expect(find.textContaining('শেষ সংযোগ এইমাত্র'), findsOneWidget);
    await h.advance(tester, const Duration(minutes: 2));
    expect(find.textContaining('শেষ সংযোগ 2 মিনিট আগে'), findsOneWidget);
  });

  testWidgets('ping: online -> connected toast and fresh contact; offline -> no connection toast', (tester) async {
    final h = await pumpHome(tester);
    await h.advance(tester, const Duration(minutes: 3));
    await tester.tap(find.byKey(const Key('pingButton')));
    await settle(tester);
    expect(find.text('সার্ভার সংযুক্ত আছে'), findsOneWidget);
    expect(find.textContaining('শেষ সংযোগ এইমাত্র'), findsOneWidget);
    await clearToast(tester);

    await h.health.setOnline(false);
    await settle(tester);
    await tester.tap(find.byKey(const Key('pingButton')));
    await settle(tester);
    expect(find.text('সার্ভারে সংযোগ নেই'), findsOneWidget);
    await clearToast(tester);
  });

  testWidgets('the screen scrolls to the latest list', (tester) async {
    await pumpHome(tester, tall: false);
    expect(find.byType(Scrollable), findsWidgets);
    await tester.scrollUntilVisible(find.byKey(const Key('seeAll')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('seeAll')), findsOneWidget);
  });

  testWidgets('a very long device name does not overflow', (tester) async {
    final h = HomeHarness();
    await pumpHome(tester, settings: h.settings.current.copyWith(deviceName: 'POS ' * 80));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card with no payer shows "প্রেরক: —"', (tester) async {
    final t = buildSampleTransactions(fixedNow)[0];
    await pumpHome(tester, items: [
      SmsTransaction(
        id: 'nopayer',
        operator: t.operator,
        sender: t.sender,
        trxId: t.trxId,
        amountPoisha: t.amountPoisha,
        kind: t.kind,
        verifyStatus: t.verifyStatus,
        syncStatus: t.syncStatus,
        receivedAt: t.receivedAt,
        rawBody: t.rawBody,
      ),
    ]);
    expect(find.text('প্রেরক: — • পেমেন্ট'), findsOneWidget);
  });

  testWidgets('a long TrxID and payer in a card do not overflow', (tester) async {
    final long = buildSampleTransactions(fixedNow)[0];
    await pumpHome(tester, items: [
      SmsTransaction(
        id: 'long',
        operator: long.operator,
        sender: long.sender,
        trxId: 'X' * 200,
        amountPoisha: long.amountPoisha,
        payerNumber: '0' * 200,
        kind: long.kind,
        verifyStatus: long.verifyStatus,
        syncStatus: long.syncStatus,
        receivedAt: long.receivedAt,
        rawBody: long.rawBody,
      ),
    ]);
    expect(tester.takeException(), isNull);
  });
}
