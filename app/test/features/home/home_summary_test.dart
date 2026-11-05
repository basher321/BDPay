import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/money.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/device_health.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/features/home/home_summary.dart';

/// 2026-10-29 12:00 Asia/Dhaka.
final now = DateTime.utc(2026, 10, 29, 6);

SmsTransaction verifiedAt(DateTime utc, int poisha) => SmsTransaction(
      id: 'x${utc.millisecondsSinceEpoch}',
      operator: MfsOperator.bkash,
      sender: 'bKash',
      trxId: 'T',
      amountPoisha: poisha,
      kind: TxKind.payment,
      verifyStatus: VerifyStatus.verified,
      syncStatus: SyncStatus.sent,
      receivedAt: utc,
      rawBody: '',
    );

void main() {
  test('sample data: total ৳ 3,750.00 and counts 2 / 2 / 1', () {
    final s = summarize(buildSampleTransactions(now), now);
    expect(formatPoisha(s.todayVerifiedPoisha), '৳ 3,750.00');
    expect(s.verified, 2);
    expect(s.pending, 2);
    expect(s.mismatchOrRejected, 1);
    expect(s.sendable, 2);
    expect(s.perOperator[MfsOperator.bkash], 2);
  });

  test('2026-10-28 23:59 Dhaka is excluded, 2026-10-29 00:00 Dhaka is included', () {
    final before = verifiedAt(DateTime.utc(2026, 10, 28, 17, 59), 100);
    final after = verifiedAt(DateTime.utc(2026, 10, 28, 18), 1000);
    expect(summarize([before], now).todayVerifiedPoisha, 0);
    expect(summarize([after], now).todayVerifiedPoisha, 1000);
  });

  test('no transactions: total 0 and all counts 0', () {
    final s = summarize(const [], now);
    expect(formatPoisha(s.todayVerifiedPoisha), '৳ 0.00');
    expect([s.verified, s.pending, s.mismatchOrRejected, s.sendable], [0, 0, 0, 0]);
  });

  test('health problem count covers rows a-d', () {
    const h = DeviceHealth(smsPermission: true, batteryOptimizationOff: false, internetOnline: true, monitoring: true);
    expect(healthProblemCount(h), 1);
    expect(healthProblemCount(h.copyWith(internetOnline: false)), 2);
    expect(healthProblemCount(h.copyWith(batteryOptimizationOff: true)), 0);
  });
}
