import 'package:flutter/foundation.dart';

/// The customer's order claim linked to a transaction.
@immutable
class ClaimInfo {
  const ClaimInfo({required this.claimId, required this.orderRef, required this.expectedAmountPoisha});

  final String claimId;
  final String orderRef;
  final int expectedAmountPoisha;
}
