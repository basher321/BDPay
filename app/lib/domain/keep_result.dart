import '../l10n/app_localizations.dart';

/// The native keep-rule result (spec 06). Wire name = Dart name = the Kotlin KeepResult name.
enum KeepResult {
  stored,
  duplicate,
  monitoringOff,
  senderNotTrusted,
  operatorOff,
  blocked,
  notIncoming;

  String toWire() => name;

  static KeepResult fromWire(String wire) {
    for (final v in values) {
      if (v.name == wire) return v;
    }
    throw FormatException('Unknown KeepResult: "$wire"');
  }

  String label(AppLocalizations l) => switch (this) {
        stored => l.keepStored,
        duplicate => l.keepDuplicate,
        monitoringOff => l.keepMonitoringOff,
        senderNotTrusted => l.keepSenderNotTrusted,
        operatorOff => l.keepOperatorOff,
        blocked => l.keepBlocked,
        notIncoming => l.keepNotIncoming,
      };
}
