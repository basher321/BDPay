import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/domain/review.dart';

void main() {
  late MockDeviceHealthRepository health;
  late MockTransactionRepository repo;

  setUp(() {
    health = MockDeviceHealthRepository();
    repo = MockTransactionRepository(health, buildSampleTransactions(DateTime.utc(2026, 10, 29, 6)));
  });

  SmsTransaction item(String id) => repo.current.firstWhere((t) => t.id == id);

  test('sample item 5 has its claim', () {
    final c = item('5').claim!;
    expect([c.claimId, c.orderRef, c.expectedAmountPoisha], ['clm_demo_5', '#1045', 45000]);
  });

  test('not mismatch -> notAllowed, nothing changes', () async {
    expect(await repo.review('1', ReviewDecision.reject, null), ReviewResult.notAllowed);
    expect(item('1').verifyStatus, VerifyStatus.verified);
  });

  test('offline -> offline, nothing changes', () async {
    await health.setOnline(false);
    await Future<void>.delayed(Duration.zero);
    expect(await repo.review('5', ReviewDecision.approve, null), ReviewResult.offline);
    expect(item('5').verifyStatus, VerifyStatus.mismatch);
  });

  test('approve -> verified with message', () async {
    expect(await repo.review('5', ReviewDecision.approve, 'ok'), ReviewResult.done);
    expect(item('5').verifyStatus, VerifyStatus.verified);
    expect(item('5').serverMessage, 'ম্যানুয়ালি অনুমোদিত');
  });

  test('reject -> rejected with message; a second review is notAllowed', () async {
    expect(await repo.review('5', ReviewDecision.reject, null), ReviewResult.done);
    expect(item('5').verifyStatus, VerifyStatus.rejected);
    expect(item('5').serverMessage, 'ম্যানুয়ালি বাতিল');
    expect(await repo.review('5', ReviewDecision.approve, null), ReviewResult.notAllowed);
  });

  test('ReviewDecision wire names', () {
    for (final d in ReviewDecision.values) {
      expect(ReviewDecision.fromWire(d.toWire()), d);
    }
    expect(() => ReviewDecision.fromWire('maybe'), throwsFormatException);
  });
}
