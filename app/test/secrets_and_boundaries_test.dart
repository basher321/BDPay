import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec 13 non-functional rules, checked on the source files:
/// - screens talk only to repository interfaces (no Supabase or url_launcher outside lib/data/supabase/);
/// - no anon key, server URL or token in source files, and no logging in the server code.
List<File> _dart(String dir) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _rel(File f) => f.path.replaceAll(r'\', '/');

void main() {
  final lib = _dart('lib');

  test('supabase_flutter is imported only in lib/data/supabase/', () {
    final bad = [
      for (final f in lib)
        if (f.readAsStringSync().contains('package:supabase_flutter') && !_rel(f).contains('lib/data/supabase/')) _rel(f),
    ];
    expect(bad, isEmpty);
  });

  test('url_launcher is imported only in url_opener.dart', () {
    final bad = [
      for (final f in lib)
        if (f.readAsStringSync().contains('package:url_launcher') && !_rel(f).endsWith('lib/data/supabase/url_opener.dart'))
          _rel(f),
    ];
    expect(bad, isEmpty);
  });

  test('screens, shell and widgets never import lib/data/supabase/', () {
    final bad = [
      for (final f in lib)
        if (RegExp(r'lib/(features|shell|widgets)/').hasMatch(_rel(f)) && f.readAsStringSync().contains('data/supabase/'))
          _rel(f),
    ];
    expect(bad, isEmpty);
  });

  test('no print / debugPrint / log in the server code and the phone pipeline (spec 13a)', () {
    final bad = [
      for (final f in lib)
        if (RegExp(r'lib/data/(supabase|device|upload)/').hasMatch(_rel(f)) &&
            RegExp(r'\b(print|debugPrint|log)\s*\(').hasMatch(f.readAsStringSync()))
          _rel(f),
    ];
    expect(bad, isEmpty);
  });

  test('no JWT-shaped key, local server address or Supabase host in lib/ or test/', () {
    final jwt = RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}');
    final bad = <String>[];
    for (final f in [...lib, ..._dart('test')]) {
      final s = f.readAsStringSync();
      if (jwt.hasMatch(s)) bad.add('${_rel(f)}: jwt');
      if (!_rel(f).startsWith('test/') && (s.contains(':54321') || s.contains('supabase.co'))) bad.add('${_rel(f)}: url');
    }
    expect(bad, isEmpty);
  });

  test('new spec 13 widgets take colours from the theme file only', () {
    const files = [
      'lib/features/home/widgets/alerts_card.dart',
      'lib/features/settings/widgets/shopify_section.dart',
      'lib/features/settings/widgets/shopify_setup_guide.dart',
      'lib/features/settings/widgets/shopify_disconnect_sheet.dart',
      'lib/shell/not_configured_screen.dart',
    ];
    for (final p in files) {
      expect(File(p).readAsStringSync().contains('Color('), isFalse, reason: p);
    }
  });
}
