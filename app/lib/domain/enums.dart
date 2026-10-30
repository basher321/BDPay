import 'dart:ui';

import '../core/theme/colors.dart';
import '../l10n/app_localizations.dart';

/// Wire name = Dart name. Unknown wire values throw, so bad server data fails loudly.
T _fromWire<T extends Enum>(List<T> values, String wire, String type) {
  for (final v in values) {
    if (v.name == wire) return v;
  }
  throw FormatException('Unknown $type: "$wire"');
}

enum MfsOperator {
  bkash(AppColors.bkash, AppColors.bkashText),
  nagad(AppColors.nagad, AppColors.nagadText),
  rocket(AppColors.rocket, AppColors.rocketText),
  upay(AppColors.upay, AppColors.upayText);

  const MfsOperator(this.brandColor, this.textColor);

  final Color brandColor;
  final Color textColor;

  String toWire() => name;
  static MfsOperator fromWire(String wire) => _fromWire(values, wire, 'MfsOperator');

  String label(AppLocalizations l) => switch (this) {
        bkash => l.opBkash,
        nagad => l.opNagad,
        rocket => l.opRocket,
        upay => l.opUpay,
      };
}

enum VerifyStatus {
  pending(AppColors.wa),
  verified(AppColors.ok),
  mismatch(AppColors.er),
  rejected(AppColors.er);

  const VerifyStatus(this.color);

  final Color color;

  String toWire() => name;
  static VerifyStatus fromWire(String wire) => _fromWire(values, wire, 'VerifyStatus');

  String label(AppLocalizations l) => switch (this) {
        pending => l.verifyPending,
        verified => l.verifyVerified,
        mismatch => l.verifyMismatch,
        rejected => l.verifyRejected,
      };
}

enum SyncStatus {
  queued(AppColors.wa),
  sending(AppColors.t3),
  sent(AppColors.ok),
  failed(AppColors.er);

  const SyncStatus(this.color);

  final Color color;

  /// Waiting to be sent: counted in the পাঠানো বাকি badge.
  bool get isPending => this == queued || this == failed;

  String toWire() => name;
  static SyncStatus fromWire(String wire) => _fromWire(values, wire, 'SyncStatus');

  String label(AppLocalizations l) => switch (this) {
        queued => l.syncQueued,
        sending => l.syncSending,
        sent => l.syncSent,
        failed => l.syncFailed,
      };
}

enum TxKind {
  payment,
  received;

  String toWire() => name;
  static TxKind fromWire(String wire) => _fromWire(values, wire, 'TxKind');

  String label(AppLocalizations l) => switch (this) {
        payment => l.kindPayment,
        received => l.kindReceived,
      };
}
