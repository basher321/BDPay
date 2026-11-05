import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/app.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/data/providers.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/claim_info.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/domain/repositories/transaction_repository.dart';
import 'package:verifier/domain/review.dart';
import 'package:verifier/shell/app_shell.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/widgets/transaction_card.dart';

import '../../signed_in_overrides.dart';

/// 2026-10-29 12:00 Asia/Dhaka.
final fixedNow = DateTime.utc(2026, 10, 29, 6);

/// A transaction for special cases, based on sample item 1.
SmsTransaction customTx({
  required String id,
  String? trxId,
  String? payerNumber = '01700000000',
  String rawBody = 'raw',
  VerifyStatus verifyStatus = VerifyStatus.verified,
  SyncStatus syncStatus = SyncStatus.sent,
  ClaimInfo? claim,
  Duration age = const Duration(minutes: 1),
  int retryCount = 0,
}) =>
    SmsTransaction(
      id: id,
      operator: MfsOperator.bkash,
      sender: 'bKash',
      trxId: trxId ?? 'TRX$id',
      amountPoisha: 10000,
      payerNumber: payerNumber,
      kind: TxKind.received,
      verifyStatus: verifyStatus,
      syncStatus: syncStatus,
      receivedAt: fixedNow.subtract(age),
      rawBody: rawBody,
      claim: claim,
      retryCount: retryCount,
    );

/// Passes everything to the mock, but review() can be held open or forced to a result.
class ControlledReviewRepository implements TransactionRepository {
  ControlledReviewRepository(this.inner);

  final MockTransactionRepository inner;
  Completer<void>? hold;
  ReviewResult? forcedResult;

  @override
  Stream<List<SmsTransaction>> watchAll() => inner.watchAll();

  @override
  Future<void> retry(String id) => inner.retry(id);

  @override
  Future<void> retryAllPending() => inner.retryAllPending();

  @override
  Future<ReviewResult> review(String id, ReviewDecision decision, String? note) async {
    if (hold != null) await hold!.future;
    return forcedResult ?? inner.review(id, decision, note);
  }
}

class AppHarness {
  AppHarness({List<SmsTransaction>? items}) {
    health = MockDeviceHealthRepository(startedAt: fixedNow, clock: () => fixedNow);
    transactions = MockTransactionRepository(health, items ?? buildSampleTransactions(fixedNow));
  }

  final ticker = StreamController<int>.broadcast();
  late final MockDeviceHealthRepository health;
  final settings = MockSettingsRepository();
  late final MockTransactionRepository transactions;
  late ProviderContainer container;
}

/// Pumps the whole app with a fixed clock and opens [tab].
Future<AppHarness> pumpAppAt(
  WidgetTester tester, {
  AppTab tab = AppTab.transactions,
  List<SmsTransaction>? items,
  TransactionRepository Function(MockTransactionRepository mock)? wrap,
}) async {
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = AppHarness(items: items);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tickerProvider.overrideWith((ref) => h.ticker.stream),
        clockProvider.overrideWithValue(fixedNow),
        deviceHealthRepositoryProvider.overrideWithValue(h.health),
        settingsRepositoryProvider.overrideWithValue(h.settings),
        transactionRepositoryProvider.overrideWithValue(wrap == null ? h.transactions : wrap(h.transactions)),
        ...signedInOverrides(),
      ],
      child: const BdpayApp(),
    ),
  );
  await tester.pump();
  h.container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  h.container.read(selectedTabProvider.notifier).select(tab);
  await settle(tester);
  return h;
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Finder cardFor(String id) => find.byWidgetPredicate((w) => w is TransactionCard && w.transaction.id == id);

List<String> cardIds(WidgetTester tester) =>
    tester.widgetList<TransactionCard>(find.byType(TransactionCard)).map((c) => c.transaction.id).toList();

/// Taps a card and waits for the bottom sheet to open.
Future<void> openDetail(WidgetTester tester, String id) async {
  await tester.tap(cardFor(id));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Waits for a toast to disappear so no timer is left at the end of a test.
Future<void> clearToast(WidgetTester tester) => tester.pump(const Duration(seconds: 2));
