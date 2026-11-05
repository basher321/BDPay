import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/data/upload/mock_sms_uploader.dart';
import 'package:verifier/domain/enums.dart';

void main() {
  // Sample item 4: Upay, pending, queued.
  final t = buildSampleTransactions(DateTime.utc(2026, 10, 29, 6))[3];

  test('online -> sent, code 200, verify stays pending (D13)', () async {
    final r = await MockSmsUploader(isOnline: () => true).upload(t);
    expect(r.syncStatus, SyncStatus.sent);
    expect(r.serverCode, 200);
    expect(r.verifyStatus, VerifyStatus.pending);
    expect(r.retryCount, t.retryCount);
  });

  test('offline -> failed with one more retry', () async {
    final r = await MockSmsUploader(isOnline: () => false).upload(t);
    expect(r.syncStatus, SyncStatus.failed);
    expect(r.retryCount, t.retryCount + 1);
    expect(r.verifyStatus, VerifyStatus.pending);
  });

  test('the in-memory test mock keeps spec 01 "verified"', () async {
    final r = await MockSmsUploader(isOnline: () => true, markVerified: true).upload(t);
    expect(r.verifyStatus, VerifyStatus.verified);
  });

  test('takes about 700 ms', () async {
    final w = Stopwatch()..start();
    await MockSmsUploader(isOnline: () => true).upload(t);
    expect(w.elapsedMilliseconds, greaterThanOrEqualTo(700));
  });
}
