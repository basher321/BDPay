import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/sms_transaction.dart';

void main() {
  late MockDeviceHealthRepository health;
  late MockTransactionRepository repo;

  setUp(() {
    health = MockDeviceHealthRepository();
    repo = MockTransactionRepository(health, buildSampleTransactions(DateTime.utc(2026, 10, 29, 6)));
  });

  SmsTransaction item(String id) => repo.current.firstWhere((t) => t.id == id);

  test('list is newest first', () async {
    final list = await repo.watchAll().first;
    expect(list.map((t) => t.id), ['1', '2', '3', '4', '5']);
  });

  test('retry online: sending, then sent and verified with code 200', () async {
    final done = repo.retry('4');
    expect((item('4')).syncStatus, SyncStatus.sending);
    await done;
    final t = item('4');
    expect(t.syncStatus, SyncStatus.sent);
    expect(t.verifyStatus, VerifyStatus.verified);
    expect(t.serverCode, 200);
  });

  test('retry offline: failed and retryCount + 1', () async {
    await health.setOnline(false);
    await repo.retry('3');
    final t = item('3');
    expect(t.syncStatus, SyncStatus.failed);
    expect(t.retryCount, 3);
    expect(t.verifyStatus, VerifyStatus.pending);
  });

  test('retry on a sent item does nothing', () async {
    await repo.retry('5');
    final t = item('5');
    expect(t.syncStatus, SyncStatus.sent);
    expect(t.verifyStatus, VerifyStatus.mismatch);
  });
}
