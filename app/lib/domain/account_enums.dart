import '../l10n/app_localizations.dart';

/// Wire name = Dart name. Unknown wire values throw, so bad server data fails loudly.
T _fromWire<T extends Enum>(List<T> values, String wire, String type) {
  for (final v in values) {
    if (v.name == wire) return v;
  }
  throw FormatException('Unknown $type: "$wire"');
}

/// Only business accounts are supported; personal accounts are not.
enum AccountType {
  merchant,
  agent;

  String toWire() => name;
  static AccountType fromWire(String wire) => _fromWire(values, wire, 'AccountType');

  String label(AppLocalizations l) => switch (this) {
        merchant => l.accountMerchant,
        agent => l.accountAgent,
      };
}

/// The SIM that receives a wallet's SMS. unknown = the merchant doesn't know.
enum SimSlot {
  sim1,
  sim2,
  unknown;

  String toWire() => name;
  static SimSlot fromWire(String wire) => _fromWire(values, wire, 'SimSlot');

  String label(AppLocalizations l) => switch (this) {
        sim1 => l.simSlot1,
        sim2 => l.simSlot2,
        unknown => l.simUnknown,
      };
}

enum AuthStatus {
  signedOut,
  needsBusinessName,
  signedIn;

  String toWire() => name;
  static AuthStatus fromWire(String wire) => _fromWire(values, wire, 'AuthStatus');
}

enum AuthResult {
  done,
  invalidUsername,
  weakPassword,
  wrongPassword,
  usernameTaken,
  notConfirmed,
  offline,
  tooSoon;

  String toWire() => name;
  static AuthResult fromWire(String wire) => _fromWire(values, wire, 'AuthResult');
}

enum AddWalletResult {
  done,
  invalidNumber,
  duplicate,
  simTaken;

  String toWire() => name;
  static AddWalletResult fromWire(String wire) => _fromWire(values, wire, 'AddWalletResult');
}

enum ConnectResult {
  done,
  invalidDomain,
  offline,

  /// Spec 13: the shop already belongs to another BDPay account.
  shopTaken;

  String toWire() => name;
  static ConnectResult fromWire(String wire) => _fromWire(values, wire, 'ConnectResult');
}
