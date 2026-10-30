import 'package:flutter/foundation.dart';

import '../account_enums.dart';
import '../enums.dart';

/// One MFS wallet of the merchant. walletNumber is a digit string (never a number).
@immutable
class Wallet {
  const Wallet({
    required this.id,
    required this.operator,
    required this.walletNumber,
    required this.accountType,
    this.label,
    required this.simSlot,
    required this.isActive,
  });

  final String id;
  final MfsOperator operator;
  final String walletNumber;
  final AccountType accountType;
  final String? label;
  final SimSlot simSlot;
  final bool isActive;

  Wallet copyWith({
    String? id,
    MfsOperator? operator,
    String? walletNumber,
    AccountType? accountType,
    String? label,
    SimSlot? simSlot,
    bool? isActive,
  }) {
    return Wallet(
      id: id ?? this.id,
      operator: operator ?? this.operator,
      walletNumber: walletNumber ?? this.walletNumber,
      accountType: accountType ?? this.accountType,
      label: label ?? this.label,
      simSlot: simSlot ?? this.simSlot,
      isActive: isActive ?? this.isActive,
    );
  }
}
