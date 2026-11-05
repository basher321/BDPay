import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/app_config.dart';
import 'package:verifier/data/account_providers.dart';
import 'package:verifier/data/mock/mock_pipeline_repository.dart';
import 'package:verifier/domain/models/pipeline_state.dart';
import 'package:verifier/shell/app_tab.dart';

import 'account_test_helpers.dart';

/// Spec 15: the update card on হোম and the privacy / terms links in settings.
void main() {
  const download = 'https://pay.example.com/download.html';

  Future<List<Uri>> pump(WidgetTester tester, {String? latest, String? url, String siteUrl = ''}) async {
    final opened = <Uri>[];
    await pumpAccountApp(tester, demoSignedIn: true, items: const [], overrides: [
      pipelineRepositoryProvider.overrideWithValue(MockPipelineRepository(
        PipelineState(deviceId: 'dev-1', rulesVersion: 1, latestAppVersion: latest, appDownloadUrl: url),
      )),
      linkOpenerProvider.overrideWithValue((u) async {
        opened.add(u);
        return true;
      }),
      if (siteUrl.isNotEmpty)
        appConfigProvider.overrideWithValue(AppConfig(supabaseUrl: '', anonKey: '', siteUrl: siteUrl)),
    ]);
    return opened;
  }

  group('update card', () {
    testWidgets('newer version -> emerald card "নতুন ভার্সন 1.0.1 এসেছে"; "ডাউনলোড করুন" opens the page', (tester) async {
      final opened = await pump(tester, latest: '1.0.1', url: download);
      expect(find.byKey(const Key('updateCard')), findsOneWidget);
      expect(find.text('নতুন ভার্সন 1.0.1 এসেছে'), findsOneWidget);
      expect(find.text('ডাউনলোড করুন'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('updateDownload')));
      expect(opened, [Uri.parse(download)]);
    });

    testWidgets('same version -> no card', (tester) async {
      await pump(tester, latest: '1.0.0', url: download);
      expect(find.byKey(const Key('updateCard')), findsNothing);
    });

    testWidgets('older version -> no card', (tester) async {
      await pump(tester, latest: '0.9.0', url: download);
      expect(find.byKey(const Key('updateCard')), findsNothing);
    });

    testWidgets('missing download URL -> no card even for a newer version', (tester) async {
      await pump(tester, latest: '1.0.1');
      expect(find.byKey(const Key('updateCard')), findsNothing);
    });

    testWidgets('no update info (older server) -> no card', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('updateCard')), findsNothing);
    });
  });

  group('privacy and terms links', () {
    testWidgets('with SITE_URL: "গোপনীয়তা নীতি" and "শর্তাবলি" open the two pages', (tester) async {
      final opened = await pump(tester, siteUrl: 'https://pay.example.com');
      await openTab(tester, AppTab.settings);
      expect(find.text('গোপনীয়তা নীতি'), findsOneWidget);
      expect(find.text('শর্তাবলি'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('privacyLink')));
      await tapVisible(tester, find.byKey(const Key('termsLink')));
      expect(opened, [
        Uri.parse('https://pay.example.com/privacy.html'),
        Uri.parse('https://pay.example.com/terms.html'),
      ]);
    });

    testWidgets('without SITE_URL: no links, the footer still shows the version', (tester) async {
      await pump(tester);
      await openTab(tester, AppTab.settings);
      expect(find.byKey(const Key('privacyLink')), findsNothing);
      expect(find.byKey(const Key('termsLink')), findsNothing);
      expect(find.byKey(const Key('appVersion')), findsOneWidget);
    });
  });
}
