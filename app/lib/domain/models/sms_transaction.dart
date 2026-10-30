import 'package:flutter/foundation.dart';

import '../account_enums.dart';
import '../enums.dart';
import 'claim_info.dart';

@immutable
class SmsTransaction {
  const SmsTransaction({
    required this.id,
    required this.operator,
    required this.sender,
    required this.trxId,
    required this.amountPoisha,
    this.payerNumber,
    required this.kind,
    required this.verifyStatus,
    required this.syncStatus,
    required this.receivedAt,
    required this.rawBody,
    this.reference,
    this.balancePoisha,
    this.serverCode,
    this.serverMessage,
    this.retryCount = 0,
    this.claim,
    this.simSlot = SimSlot.unknown,
    this.parseFailed = false,
    this.serverSmsId,
  });

  final String id;
  final MfsOperator operator;
  final String sender;
  final String trxId;
  final int amountPoisha;
  final String? payerNumber;
  final TxKind kind;
  final VerifyStatus verifyStatus;
  final SyncStatus syncStatus;

  /// Always UTC.
  final DateTime receivedAt;
  final String rawBody;
  final String? reference;
  final int? balancePoisha;
  final int? serverCode;
  final String? serverMessage;
  final int retryCount;

  /// The linked order claim; null when no order is linked yet.
  final ClaimInfo? claim;

  /// The SIM that received the SMS (spec 06).
  final SimSlot simSlot;

  /// The phone could not read a TrxID or amount; shown as "অজানা ফরম্যাট". The server parses it again.
  final bool parseFailed;

  /// The server's id for this SMS (spec 13a); null until uploaded. Used for claim-review, never shown.
  final String? serverSmsId;

  SmsTransaction copyWith({
    VerifyStatus? verifyStatus,
    SyncStatus? syncStatus,
    int? serverCode,
    String? serverMessage,
    int? retryCount,
    ClaimInfo? claim,
  }) {
    return SmsTransaction(
      id: id,
      operator: operator,
      sender: sender,
      trxId: trxId,
      amountPoisha: amountPoisha,
      payerNumber: payerNumber,
      kind: kind,
      verifyStatus: verifyStatus ?? this.verifyStatus,
      syncStatus: syncStatus ?? this.syncStatus,
      receivedAt: receivedAt,
      rawBody: rawBody,
      reference: reference,
      balancePoisha: balancePoisha,
      serverCode: serverCode ?? this.serverCode,
      serverMessage: serverMessage ?? this.serverMessage,
      retryCount: retryCount ?? this.retryCount,
      claim: claim ?? this.claim,
      simSlot: simSlot,
      parseFailed: parseFailed,
      serverSmsId: serverSmsId,
    );
  }
}
