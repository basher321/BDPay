import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/data/providers.dart';
import 'package:verifier/data/sync_coordinator.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/domain/repositories/transaction_repository.dart';
import 'package:verifier/domain/review.dart';

/// Counts retryAllPending; [hold] keeps a send running until completed.
class CountingRepository implements TransactionRepository {
  CountingRepository(this.inner);

  final MockTransactionRepository inner;
  int sendAllCalls = 0;
  Completer<void>? hold;

  @override
  Stream<List<SmsTransaction>> watchAll() => inner.watchAll();

  @override
  Future<void> retry(String id) => inner.retry(id);

  @override
  Future<void> retryAllPending() async {
    sendAllCalls++;
    if (hold != null) await hold!.future;
    await inner.retryAllPending();
  }

  @override
  Future<ReviewResult> review(String id, ReviewDecision decision, String? note) => inner.review(id, decision, note);
}

void main() {
  late MockDeviceHealthRepository health;
  late MockSettingsRepository settings;
  late CountingRepository repo;
  late SyncCoordinator coordinator;
  late List<int> toasts;

  setUp(() {
    health = MockDeviceHealthRepository();
    settings = MockSettingsRepository();
    repo = CountingRepository(MockTransactionRepository(health, buildSampleTransactions(DateTime.utc(2026, 10, 29, 6))));
    // The coordinator gets its repositories through the providers.
    final container = ProviderContainer(overrides: [
      deviceHealthRepositoryProvider.overrideWithValue(health),
      settingsRepositoryProvider.overrideWithValue(settings),
      transactionRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    toasts = [];
    coordinator = container.read(syncCoordinatorProvider)..onAutoSent = toasts.add;
    coordinator.start();
  });

  Future<void> goOnlineAgain() async {
    await health.setOnline(false);
    await pumpEventQueue();
    await health.setOnline(true);
    await pumpEventQueue();
  }

  test('the first health event only sets the starting point', () async {
    await pumpEventQueue();
    expect(repo.sendAllCalls, 0);
  });

  test('offline -> online with autoSend on calls retryAllPending once and reports k', () async {
    await pumpEventQueue();
    await goOnlineAgain();
    expect(repo.sendAllCalls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await pumpEventQueue();
    expect(toasts, [2]);
  });

  test('autoSend off -> not called', () async {
    await settings.update(settings.current.copyWith(autoSend: false));
    await pumpEventQueue();
    await goOnlineAgain();
    expect(repo.sendAllCalls, 0);
  });

  test('two quick online events while a send is running call it once', () async {
    repo.hold = Completer<void>();
    await pumpEventQueue();
    await goOnlineAgain();
    await goOnlineAgain();
    expect(repo.sendAllCalls, 1);
    repo.hold!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });

  test('k = 0 -> no callback', () async {
    await pumpEventQueue();
    await repo.inner.retryAllPending(); // empties the queue first
    await pumpEventQueue();
    await goOnlineAgain();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await pumpEventQueue();
    expect(repo.sendAllCalls, 1);
    expect(toasts, isEmpty);
  });

  test('after dispose(), offline -> online calls nothing', () async {
    await pumpEventQueue();
    coordinator.dispose();
    await goOnlineAgain();
    expect(repo.sendAllCalls, 0);
  });
}
