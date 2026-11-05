import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/features/queue/queue_logic.dart';

void main() {
  final now = DateTime.utc(2026, 10, 29, 6);
  final samples = buildSampleTransactions(now);

  test('sample data: 2 items, oldest first (Upay 95 min, then Rocket 50 min)', () {
    final items = queueItems(samples);
    expect(items.map((t) => t.operator), [MfsOperator.upay, MfsOperator.rocket]);
  });

  test('sending items are queue items too', () {
    final list = [samples[0].copyWith(syncStatus: SyncStatus.sending), ...samples.skip(1)];
    expect(queueItems(list).map((t) => t.id), ['4', '3', '1']);
  });

  test('isStale: false at 23 h 59 m, true at 24 h 1 m', () {
    final t = samples[0];
    expect(isStale(t, t.receivedAt.add(const Duration(hours: 23, minutes: 59))), isFalse);
    expect(isStale(t, t.receivedAt.add(const Duration(hours: 24, minutes: 1))), isTrue);
  });

  test('isStuck: false at 4, true at 5', () {
    expect(isStuck(samples[0].copyWith(retryCount: 4)), isFalse);
    expect(isStuck(samples[0].copyWith(retryCount: 5)), isTrue);
  });
}
