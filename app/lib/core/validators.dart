import '../domain/enums.dart';

const _banglaZero = 0x09E6;

/// Bangla digits (০-৯) become English digits (0-9); everything else stays.
String toEnglishDigits(String s) => String.fromCharCodes(s.runes.map(
      (r) => r >= _banglaZero && r <= _banglaZero + 9 ? r - _banglaZero + 0x30 : r,
    ));

/// Trimmed and lower case.
String normalizeEmail(String s) => s.trim().toLowerCase();

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// A simple text@text.text check.
bool isValidEmail(String s) => _email.hasMatch(s);

/// English digits, no spaces or dashes, and a leading +880 / 880 changed to 0.
String normalizeWalletNumber(String s) {
  final n = toEnglishDigits(s).replaceAll(RegExp(r'[\s-]'), '');
  if (n.startsWith('+880')) return '0${n.substring(4)}';
  if (n.startsWith('880')) return '0${n.substring(3)}';
  return n;
}

final _wallet11 = RegExp(r'^01[3-9]\d{8}$');
final _wallet12 = RegExp(r'^01[3-9]\d{9}$');

/// 01[3-9] + 8 digits; Rocket also allows one extra check digit (12 digits).
bool isValidWalletNumber(MfsOperator op, String n) =>
    _wallet11.hasMatch(n) || (op == MfsOperator.rocket && _wallet12.hasMatch(n));

/// Trimmed, lower case, no http(s)://, no path; ".myshopify.com" added when there is no dot.
String normalizeShopDomain(String s) {
  var d = s.trim().toLowerCase();
  for (final scheme in ['https://', 'http://']) {
    if (d.startsWith(scheme)) d = d.substring(scheme.length);
  }
  final slash = d.indexOf('/');
  if (slash >= 0) d = d.substring(0, slash);
  if (!d.contains('.')) d = '$d.myshopify.com';
  return d;
}

final _shop = RegExp(r'^[a-z0-9][a-z0-9-]*\.myshopify\.com$');

bool isValidShopDomain(String s) => _shop.hasMatch(s);

/// The login code: exactly 6 digits after Bangla digits are converted.
bool isCompleteCode(String s) => RegExp(r'^\d{6}$').hasMatch(toEnglishDigits(s));

/// Business name: 2 to 60 characters after trimming.
bool isValidBusinessName(String s) => _lengthBetween(s.trim(), 2, 60);

/// Device name: 1 to 30 characters after trimming.
bool isValidDeviceName(String s) => _lengthBetween(s.trim(), 1, 30);

/// Wallet label: optional, at most 30 characters.
bool isValidWalletLabel(String s) => s.trim().runes.length <= 30;

bool _lengthBetween(String s, int min, int max) {
  final n = s.runes.length;
  return n >= min && n <= max;
}
