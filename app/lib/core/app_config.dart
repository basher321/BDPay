/// Spec 13: the server address and the public anon key come only from --dart-define. Nothing is hard-coded and
/// neither value is ever logged.
class AppConfig {
  const AppConfig({required this.supabaseUrl, required this.anonKey, this.siteUrl = ''});

  /// The values given at build time (`--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`).
  static const fromDefines = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    anonKey: String.fromEnvironment('SUPABASE_ANON_KEY'),
    siteUrl: String.fromEnvironment('SITE_URL'),
  );

  /// No server: the mock repositories are used (tests, and the "not configured" screen in a real run).
  static const none = AppConfig(supabaseUrl: '', anonKey: '');

  final String supabaseUrl;
  final String anonKey;

  /// Spec 15 (plan D219): the public site, for example `https://pay.<domain>`. Empty -> no legal links.
  final String siteUrl;

  /// SITE_URL + "/" + [file] when SITE_URL is an https address, else null.
  Uri? sitePage(String file) {
    final uri = Uri.tryParse(siteUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
    final base = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: '$base$file', query: null, fragment: null);
  }

  /// Both values present and the URL is an http(s) address.
  bool get isComplete {
    if (anonKey.isEmpty) return false;
    final uri = Uri.tryParse(supabaseUrl);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  String get _base => supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl;

  /// SUPABASE_URL + "/functions/v1".
  String get functionsUrl => '$_base/functions/v1';
}
