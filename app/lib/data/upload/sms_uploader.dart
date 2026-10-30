import 'package:flutter/foundation.dart';

import '../../domain/enums.dart';
import '../../domain/models/sms_transaction.dart';

/// The outcome of one upload. The repository that owns the row writes it back.
@immutable
class UploadResult {
  const UploadResult({
    required this.syncStatus,
    required this.verifyStatus,
    required this.retryCount,
    this.serverCode,
    this.serverMessage,
  });

  /// sent or failed (never sending).
  final SyncStatus syncStatus;
  final VerifyStatus verifyStatus;
  final int retryCount;
  final int? serverCode;
  final String? serverMessage;

  SmsTransaction applyTo(SmsTransaction t) => t.copyWith(
        syncStatus: syncStatus,
        verifyStatus: verifyStatus,
        retryCount: retryCount,
        serverCode: serverCode,
        serverMessage: serverMessage,
      );
}

/// Sends one SMS to the server. Spec 13 sends sender, raw body, time and SIM; the server re-parses.
abstract interface class SmsUploader {
  Future<UploadResult> upload(SmsTransaction t);
}
