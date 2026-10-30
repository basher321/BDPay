import '../../domain/enums.dart';
import '../../domain/models/sms_transaction.dart';
import 'sms_uploader.dart';

/// MOCK - replaced by the server in spec 13.
/// The spec 01 send: wait 700 ms; online -> sent with code 200; offline -> failed and one more retry.
/// [markVerified] keeps spec 01's "amount > 0 -> verified" for the in-memory test mock only. The phone
/// database never gets "verified" from the device (CLAUDE.md, decision D13).
class MockSmsUploader implements SmsUploader {
  MockSmsUploader({required this.isOnline, this.markVerified = false});

  static const delay = Duration(milliseconds: 700);

  final bool Function() isOnline;
  final bool markVerified;

  @override
  Future<UploadResult> upload(SmsTransaction t) async {
    await Future<void>.delayed(delay);
    if (!isOnline()) {
      return UploadResult(
        syncStatus: SyncStatus.failed,
        verifyStatus: t.verifyStatus,
        retryCount: t.retryCount + 1,
        serverCode: t.serverCode,
        serverMessage: t.serverMessage,
      );
    }
    final verified = markVerified && t.verifyStatus == VerifyStatus.pending && t.amountPoisha > 0;
    return UploadResult(
      syncStatus: SyncStatus.sent,
      verifyStatus: verified ? VerifyStatus.verified : t.verifyStatus,
      retryCount: t.retryCount,
      serverCode: 200,
      serverMessage: t.serverMessage,
    );
  }
}
