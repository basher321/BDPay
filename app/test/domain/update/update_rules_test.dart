import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/app_config.dart';
import 'package:verifier/domain/update/update_rules.dart';

void main() {
  test('isNewerVersion: newer, same, older, build suffix ignored, unreadable -> false', () {
    expect(isNewerVersion('1.0.1', '1.0.0+1'), isTrue);
    expect(isNewerVersion('1.1.0', '1.0.9'), isTrue);
    expect(isNewerVersion('2.0.0', '1.99.99'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0+1'), isFalse); // same version, different build
    expect(isNewerVersion('1.0.0+5', '1.0.0+1'), isFalse);
    expect(isNewerVersion('0.9.9', '1.0.0+1'), isFalse);
    expect(isNewerVersion('1.0.10', '1.0.9'), isTrue); // numbers, not text
    for (final bad in [null, '', '1.0', 'v1.0.1', '1.0.1.2', 'abc']) {
      expect(isNewerVersion(bad, '1.0.0+1'), isFalse, reason: '$bad');
    }
  });

  test('updateLink: only a newer version with an https link', () {
    const url = 'https://pay.example.com/download.html';
    expect(updateLink(latest: '1.0.1', downloadUrl: url, running: '1.0.0+1'), Uri.parse(url));
    expect(updateLink(latest: '1.0.0', downloadUrl: url, running: '1.0.0+1'), isNull);
    expect(updateLink(latest: '0.9.0', downloadUrl: url, running: '1.0.0+1'), isNull);
    for (final bad in [null, '', 'http://pay.example.com/d', 'javascript:alert(1)', 'https://u:p@pay.example.com/d']) {
      expect(updateLink(latest: '1.0.1', downloadUrl: bad, running: '1.0.0+1'), isNull, reason: '$bad');
    }
  });

  test('AppConfig.sitePage: https SITE_URL only', () {
    AppConfig site(String s) => AppConfig(supabaseUrl: '', anonKey: '', siteUrl: s);
    expect(site('https://pay.example.com').sitePage('privacy.html'), Uri.parse('https://pay.example.com/privacy.html'));
    expect(site('https://pay.example.com/').sitePage('terms.html'), Uri.parse('https://pay.example.com/terms.html'));
    for (final bad in ['', 'http://pay.example.com', 'pay.example.com', 'https://u:p@pay.example.com']) {
      expect(site(bad).sitePage('privacy.html'), isNull, reason: bad);
    }
  });
}
