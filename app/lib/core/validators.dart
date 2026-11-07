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

/// Spec 16: the internal address domain behind a username. No email is ever sent to it.
const loginDomain = 'users.bdpay.app';

/// Spec 16: the shortest password the app sends (Supabase minimum_password_length).
const minPasswordLength = 6;

/// Trimmed and lower case.
String normalizeUsername(String s) => s.trim().toLowerCase();

final _username = RegExp(r'^[a-z0-9_]{3,20}$');

/// 3 to 20 English lower-case letters, digits or "_".
bool isValidUsername(String s) => _username.hasMatch(s);

/// "rahim" -> "rahim@users.bdpay.app".
String usernameToEmail(String username) => '$username@$loginDomain';

/// The username inside an internal address; any other address is returned as it is.
String usernameOf(String email) {
  const suffix = '@$loginDomain';
  return email.endsWith(suffix) ? email.substring(0, email.length - suffix.length) : email;
}

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

/// Spec 17: a website name, 2 to 60 characters after trimming.
bool isValidSiteName(String s) => _lengthBetween(s.trim(), 2, 60);

/// Spec 17: an https address with a real host name (no user info, no IP address, not localhost), at most 300
/// characters. Returns the trimmed address without a trailing "/" on a bare host, or null.
String? normalizeHttpsUrl(String s) {
  final t = s.trim();
  if (t.isEmpty || t.length > 300) return null;
  final u = Uri.tryParse(t);
  if (u == null || u.scheme != 'https' || u.userInfo.isNotEmpty) return null;
  final host = u.host.toLowerCase();
  if (!host.contains('.') || host == 'localhost' || host.endsWith('.localhost')) return null;
  if (RegExp(r'^[0-9.]+$').hasMatch(host) || t.contains('://[')) return null;
  final noFragment = u.removeFragment().toString();
  return (u.path.isEmpty || u.path == '/') && !u.hasQuery ? noFragment.replaceFirst(RegExp(r'/$'), '') : noFragment;
}
