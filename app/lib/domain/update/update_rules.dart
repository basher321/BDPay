/// Spec 15: whether the update card is shown. Pure.
library;

/// "1.2.3" (anything after "+" or "-" is ignored) -> [1, 2, 3]; null when it is not three whole numbers.
List<int>? _parts(String? version) {
  if (version == null) return null;
  final core = version.trim().split(RegExp(r'[+-]')).first;
  final m = RegExp(r'^(\d{1,4})\.(\d{1,4})\.(\d{1,4})$').firstMatch(core);
  if (m == null) return null;
  return [int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!)];
}

/// True only when [latest] is a higher major.minor.patch than [running]. Unreadable versions -> false.
bool isNewerVersion(String? latest, String running) {
  final a = _parts(latest), b = _parts(running);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

/// The download page to open, or null when no card is shown: a newer version AND an https link (spec 15 edge case:
/// no APP_DOWNLOAD_URL -> no card even when a newer version exists).
Uri? updateLink({required String? latest, required String? downloadUrl, required String running}) {
  if (!isNewerVersion(latest, running)) return null;
  final uri = Uri.tryParse(downloadUrl?.trim() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  return uri;
}
