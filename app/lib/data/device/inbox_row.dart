import 'package:flutter/foundation.dart';

/// One sms_inbox row as it comes over the channel.
@immutable
class InboxRow {
  const InboxRow({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAtMs,
    required this.simSlot,
    required this.syncStatus,
    required this.verifyStatus,
    required this.retryCount,
    this.serverCode,
    this.serverMessage,
    required this.operator,
    required this.source,
    this.serverSmsId,
    this.claimJson,
  });

  factory InboxRow.fromMap(Map<Object?, Object?> m) => InboxRow(
        id: m['id']! as String,
        sender: m['sender']! as String,
        body: m['body']! as String,
        receivedAtMs: (m['received_at_ms']! as num).toInt(),
        simSlot: m['sim_slot']! as String,
        syncStatus: m['sync_status']! as String,
        verifyStatus: m['verify_status']! as String,
        retryCount: (m['retry_count']! as num).toInt(),
        serverCode: (m['server_code'] as num?)?.toInt(),
        serverMessage: m['server_message'] as String?,
        operator: m['operator']! as String,
        source: m['source']! as String,
        serverSmsId: m['server_sms_id'] as String?,
        claimJson: m['claim_json'] as String?,
      );

  final String id;
  final String sender;
  final String body;

  /// UTC milliseconds since epoch.
  final int receivedAtMs;
  final String simSlot;
  final String syncStatus;
  final String verifyStatus;
  final int retryCount;
  final int? serverCode;
  final String? serverMessage;
  final String operator;

  /// 'sms' or 'simulated' (decision D16).
  final String source;

  /// Spec 13a: the server's id once uploaded; the claim as JSON {claimId, orderRef, expectedAmountPoisha}.
  final String? serverSmsId;
  final String? claimJson;
}
