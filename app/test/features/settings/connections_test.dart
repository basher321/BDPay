import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/validators.dart';
import 'package:verifier/data/supabase/functions_gateway.dart';
import 'package:verifier/data/supabase/gateway_errors.dart';
import 'package:verifier/data/supabase/supabase_connections_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/models/auth_state.dart';
import 'package:verifier/domain/models/store_connection.dart';
import 'package:verifier/domain/repositories/connections_repository.dart';
import 'package:verifier/domain/repositories/repository_errors.dart';
import 'package:verifier/shell/app_tab.dart';

import '../account_test_helpers.dart';

Future<AccountHarness> pumpSettings(WidgetTester tester) async {
  final h = await pumpAccountApp(tester, demoSignedIn: true);
  await openTab(tester, AppTab.settings);
  return h;
}

Future<void> openAdd(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('addStoreButton')));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> addSite(WidgetTester tester, String platform, String name, String url) async {
  await openAdd(tester);
  await tapVisible(tester, find.byKey(Key('platform-$platform')));
  await tester.enterText(find.byKey(const Key('siteNameField')), name);
  await tester.enterText(find.byKey(const Key('siteUrlField')), url);
  await tester.pump();
  await tapVisible(tester, find.byKey(const Key('createConnectionButton')));
}

String? errorText(WidgetTester tester, String key) {
  final f = find.byKey(Key(key));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

/// A gateway that answers from a list and records calls.
class FakeGateway implements FunctionsGateway {
  FakeGateway(this.replies);

  final List<Object> replies;
  final calls = <Map<String, dynamic>?>[];

  @override
  Future<FunctionsReply> call(String name, {bool get = false, Map<String, dynamic>? body}) async {
    calls.add(body);
    final next = replies.removeAt(0);
    if (next is OfflineException) throw next;
    return next as FunctionsReply;
  }
}

Map<String, dynamic> connJson({String status = 'active', String? webhook}) => {
      'id': 'c1',
      'merchantId': 'm1',
      'platform': 'laravel',
      'kind': 'api',
      'siteName': 'আমার দোকান',
      'siteUrl': 'https://shop.example.com',
      'webhookUrl': webhook,
      'apiKeyPrefix': 'bdp_live_abc',
      'status': status,
      'lastError': null,
      'connectedAt': '2026-11-07T03:00:00.000Z',
    };

void main() {
  group('validators', () {
    test('site name 2 to 60; https URL rules', () {
      expect(isValidSiteName(' a '), isFalse);
      expect(isValidSiteName('ab'), isTrue);
      expect(isValidSiteName('x' * 61), isFalse);
      expect(normalizeHttpsUrl('https://Shop.example.com/'), 'https://shop.example.com');
      expect(normalizeHttpsUrl('https://shop.example.com/a?b=1#c'), 'https://shop.example.com/a?b=1');
      for (final bad in ['http://shop.example.com', 'https://localhost', 'https://10.0.0.1', 'shop.com', '']) {
        expect(normalizeHttpsUrl(bad), isNull, reason: bad);
      }
    });

    test('platform wire values match the server list', () {
      expect(StorePlatform.values.map((p) => p.toWire()).toList(), [
        'shopify', 'wordpress', 'webflow', 'framer', 'wix', 'squarespace', 'bubble', 'drupal', 'joomla', //
        'hubspot', 'duda', 'react', 'nextjs', 'vue', 'laravel', 'nodejs', 'django', 'ghost', 'magento', //
        'prestashop', 'webstudio', 'astro', 'sveltekit', 'nuxt', 'other',
      ]);
      expect(() => StorePlatform.fromWire('daraz'), throwsFormatException);
    });
  });

  group('settings section', () {
    testWidgets('empty section with the add button; the picker lists every platform and searches', (tester) async {
      await pumpSettings(tester);
      expect(find.text('স্টোর / ওয়েবসাইট'), findsOneWidget);
      expect(find.byKey(const Key('connectionsEmpty')), findsOneWidget);
      expect(find.byKey(const Key('shopifySection')), findsOneWidget);
      await openAdd(tester);
      for (final p in StorePlatform.values) {
        expect(find.byKey(Key('platform-${p.name}')), findsOneWidget, reason: p.name);
      }
      await tester.enterText(find.byKey(const Key('platformSearch')), 'next');
      await tester.pump();
      expect(find.byKey(const Key('platform-nextjs')), findsOneWidget);
      expect(find.byKey(const Key('platform-laravel')), findsNothing);
      await tester.enterText(find.byKey(const Key('platformSearch')), 'zzz');
      await tester.pump();
      expect(find.byKey(const Key('platformNoMatch')), findsOneWidget);
    });

    testWidgets('Shopify in the picker points to the Shopify section (no API key)', (tester) async {
      await pumpSettings(tester);
      await openAdd(tester);
      await tapVisible(tester, find.byKey(const Key('platform-shopify')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('platformPicker')), findsNothing);
      expect(find.text('Shopify স্টোর নিচের "Shopify স্টোর" অংশ থেকে যুক্ত করুন'), findsOneWidget);
      await clearToast(tester);
    });

    testWidgets('create shows the key and webhook secret once, copy works, then the row appears', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpSettings(tester);
      await addSite(tester, 'laravel', 'আমার দোকান', 'https://shop.example.com/');
      expect(find.byKey(const Key('connectionKeys')), findsOneWidget);
      expect(find.byKey(const Key('keyShownOnce')), findsOneWidget);
      expect(find.byKey(const Key('connectionGuide')), findsOneWidget);
      expect(find.textContaining('Laravel: কলটি আপনার সার্ভারের কোড থেকে করুন'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('copyApiKey')));
      expect(copied, startsWith('bdp_live_'));
      await clearToast(tester);
      await tapVisible(tester, find.byKey(const Key('connectionDoneButton')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('connectionsEmpty')), findsNothing);
      expect(find.text('আমার দোকান'), findsOneWidget);
      expect(find.text('চালু'), findsOneWidget);
      // The key is never shown again.
      expect(find.textContaining(copied!), findsNothing);
    });

    testWidgets('form errors: short name, http address, the same site twice', (tester) async {
      await pumpSettings(tester);
      await addSite(tester, 'django', 'a', 'https://shop.example.com');
      expect(errorText(tester, 'connectionError'), 'নাম ২ থেকে ৬০ অক্ষরের দিন');
      await tester.enterText(find.byKey(const Key('siteNameField')), 'My shop');
      await tester.enterText(find.byKey(const Key('siteUrlField')), 'http://shop.example.com');
      await tapVisible(tester, find.byKey(const Key('createConnectionButton')));
      expect(errorText(tester, 'connectionError'), 'https:// দিয়ে শুরু হওয়া সঠিক ঠিকানা দিন');
      await tester.enterText(find.byKey(const Key('siteUrlField')), 'https://shop.example.com');
      await tapVisible(tester, find.byKey(const Key('createConnectionButton')));
      await tapVisible(tester, find.byKey(const Key('connectionDoneButton')));
      await tester.pump(const Duration(milliseconds: 400));
      await addSite(tester, 'django', 'Again', 'https://shop.example.com');
      expect(errorText(tester, 'connectionError'), 'এই ওয়েবসাইট এই প্ল্যাটফর্মে আগেই যুক্ত আছে');
    });

    testWidgets('offline create shows "ইন্টারনেট নেই" and keeps the typed values', (tester) async {
      final h = await pumpSettings(tester);
      await h.health.setOnline(false);
      await settle(tester);
      await addSite(tester, 'wix', 'Wix shop', 'https://wix.example.com');
      expect(errorText(tester, 'connectionError'), 'ইন্টারনেট নেই');
      expect(find.text('Wix shop'), findsOneWidget);
    });

    testWidgets('detail: save webhook, new key after confirm, disable after confirm', (tester) async {
      await pumpSettings(tester);
      await addSite(tester, 'nextjs', 'Next shop', 'https://next.example.com');
      await tapVisible(tester, find.byKey(const Key('connectionDoneButton')));
      await tester.pump(const Duration(milliseconds: 400));
      await tapVisible(tester, find.byKey(const Key('connection-conn-1')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('connectionDetail')), findsOneWidget);
      final before = tester.widget<Text>(find.byKey(const Key('keyPrefix'))).data;

      await tester.enterText(find.byKey(const Key('webhookField')), 'http://bad.example.com');
      await tapVisible(tester, find.byKey(const Key('saveWebhookButton')));
      expect(errorText(tester, 'webhookError'), 'https:// দিয়ে শুরু হওয়া সঠিক ঠিকানা দিন');
      await tester.enterText(find.byKey(const Key('webhookField')), 'https://next.example.com/hook');
      await tapVisible(tester, find.byKey(const Key('saveWebhookButton')));
      expect(find.text('ওয়েবহুক সংরক্ষিত হয়েছে'), findsOneWidget);
      await clearToast(tester);

      await tapVisible(tester, find.byKey(const Key('rotateKeyButton')));
      await tester.tap(find.byKey(const Key('confirmNo')));
      await settle(tester);
      expect(find.byKey(const Key('copyNewKey')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('rotateKeyButton')));
      await tester.tap(find.byKey(const Key('confirmYes')));
      await settle(tester);
      expect(find.byKey(const Key('copyNewKey')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('keyPrefix'))).data, isNot(before));

      await tapVisible(tester, find.byKey(const Key('disableConnButton')));
      await tester.tap(find.byKey(const Key('confirmYes')));
      await settle(tester);
      expect(find.text('বন্ধ'), findsWidgets);
      expect(find.byKey(const Key('disableConnButton')), findsNothing);
    });
  });

  group('SupabaseConnectionsRepository', () {
    Future<SupabaseConnectionsRepository> started(FakeGateway g) async {
      final repo = SupabaseConnectionsRepository(
        functions: g,
        auth: Stream.value(const AuthState(status: AuthStatus.signedIn)),
      )..start();
      await Future<void>.delayed(Duration.zero);
      return repo;
    }

    test('loads the list after sign-in; create returns the keys once and adds the row', () async {
      final g = FakeGateway([
        FunctionsReply(200, {'ok': true, 'connections': <Object>[]}),
        FunctionsReply(200, {'ok': true, 'connection': connJson(), 'apiKey': 'bdp_live_x', 'webhookSecret': 'whsec_y'}),
      ]);
      final repo = await started(g);
      final keys = await repo.create(StorePlatform.laravel, 'আমার দোকান', 'https://shop.example.com');
      expect(keys.apiKey, 'bdp_live_x');
      expect(keys.webhookSecret, 'whsec_y');
      expect(g.calls.last, {
        'action': 'create',
        'platform': 'laravel',
        'siteName': 'আমার দোকান',
        'siteUrl': 'https://shop.example.com',
      });
      final list = await repo.watch().first;
      expect(list.single.platform, StorePlatform.laravel);
      expect(list.single.connectedAt, DateTime.utc(2026, 11, 7, 3));
    });

    test('server errors map to input errors; offline and unknown answers to OfflineError', () async {
      final g = FakeGateway([
        FunctionsReply(200, {'ok': true, 'connections': <Object>[]}),
        FunctionsReply(409, {'ok': false, 'error': 'duplicate'}),
        FunctionsReply(400, {'ok': false, 'error': 'invalidUrl'}),
        const OfflineException(),
        FunctionsReply(404, {'code': 'NOT_FOUND'}),
      ]);
      final repo = await started(g);
      Future<void> create() => repo.create(StorePlatform.vue, 'Vue shop', 'https://vue.example.com');
      await expectLater(
        create(),
        throwsA(isA<ConnectionInputError>().having((e) => e.kind, 'kind', CreateConnectionError.duplicate)),
      );
      await expectLater(
        create(),
        throwsA(isA<ConnectionInputError>().having((e) => e.kind, 'kind', CreateConnectionError.invalidUrl)),
      );
      await expectLater(create(), throwsA(isA<OfflineError>()));
      await expectLater(create(), throwsA(isA<OfflineError>()));
    });

    test('rotate, webhook and disable update the row; an unknown platform row is skipped', () async {
      final bad = {...connJson(), 'id': 'c2', 'platform': 'daraz'};
      final g = FakeGateway([
        FunctionsReply(200, {'ok': true, 'connections': [connJson(), bad]}),
        FunctionsReply(200, {'ok': true, 'connection': connJson(webhook: 'https://shop.example.com/h')}),
        FunctionsReply(200, {'ok': true, 'connection': {...connJson(), 'apiKeyPrefix': 'bdp_live_new'}, 'apiKey': 'k2'}),
        FunctionsReply(200, {'ok': true, 'connection': connJson(status: 'disabled')}),
      ]);
      final repo = await started(g);
      expect((await repo.watch().first).length, 1);
      expect((await repo.updateWebhook('c1', ' https://shop.example.com/h ')).webhookUrl, 'https://shop.example.com/h');
      expect(g.calls.last, {'action': 'updateWebhook', 'id': 'c1', 'webhookUrl': 'https://shop.example.com/h'});
      expect(await repo.rotateKey('c1'), 'k2');
      expect((await repo.watch().first).single.apiKeyPrefix, 'bdp_live_new');
      expect((await repo.disable('c1')).status, ConnectionStatus.disabled);
    });
  });
}
