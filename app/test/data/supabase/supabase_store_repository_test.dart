import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/supabase/supabase_store_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/models/auth_state.dart';
import 'package:verifier/domain/models/merchant.dart';
import 'package:verifier/domain/models/shopify_store.dart';

import 'fakes.dart';

const _signedIn = AuthState(
  status: AuthStatus.signedIn,
  email: 'a@b.co',
  merchant: Merchant(id: 'm-1', businessName: 'দোকান'),
);

void main() {
  late FakeFunctionsGateway fn;
  late FakeUrlOpener opener;
  late FakeTimers timers;
  late FakeForeground fg;
  late StreamController<AuthState> auth;
  late SupabaseStoreRepository repo;

  final notConnected = reply(200, {'connected': false, 'shopDomain': null, 'lastError': null});
  final connected = reply(200, {'connected': true, 'shopDomain': 'myshop.myshopify.com', 'lastError': null});

  setUp(() async {
    fn = FakeFunctionsGateway();
    opener = FakeUrlOpener();
    timers = FakeTimers();
    fg = FakeForeground();
    auth = StreamController<AuthState>.broadcast();
    repo = SupabaseStoreRepository(functions: fn, opener: opener, auth: auth.stream, timers: timers, foreground: fg)
      ..start();
  });

  Future<void> signIn() async {
    auth.add(_signedIn);
    await pumpEventQueue();
  }

  test('status after sign-in and when the app comes to the front', () async {
    fn.answer('shopify-status', notConnected);
    await signIn();
    expect(fn.count('shopify-status'), 1);
    expect(fn.calls.single.$2, isTrue, reason: 'GET');
    fg.resume();
    await pumpEventQueue();
    expect(fn.count('shopify-status'), 2);
    expect(await repo.watch().first, isNull);
  });

  test('connected -> the store; reconnectNeeded -> the store with lastError; other errors -> not connected', () async {
    fn.answer('shopify-status', connected);
    fn.answer('shopify-status', reply(200, {'connected': false, 'shopDomain': 'myshop.myshopify.com', 'lastError': 'reconnectNeeded'}));
    fn.answer('shopify-status', reply(200, {'connected': false, 'shopDomain': 'myshop.myshopify.com', 'lastError': null}));
    await signIn();
    final s1 = await repo.watch().first;
    expect(s1?.shopDomain, 'myshop.myshopify.com');
    expect(s1?.needsReconnect, isFalse);
    expect(s1?.connectedAt, isNull, reason: 'D133 C: shopify-status has no time');
    await repo.refresh();
    expect((await repo.watch().first)?.lastError, ShopifyStore.reconnectNeeded);
    await repo.refresh();
    expect(await repo.watch().first, isNull);
  });

  test('a failed status call keeps the last known state', () async {
    fn.answer('shopify-status', connected);
    fn.answer('shopify-status', offline);
    await signIn();
    expect(await repo.refresh(), isFalse);
    expect((await repo.watch().first)?.shopDomain, 'myshop.myshopify.com');
  });

  group('connectShopify', () {
    setUp(() async {
      fn.answer('shopify-status', notConnected);
      await signIn();
    });

    test('opens the returned URL in the browser -> done, and polls', () async {
      fn.answer('shopify-connect-link', reply(200, {'url': 'https://myshop.myshopify.com/admin/oauth/authorize?x=1'}));
      expect(await repo.connectShopify('MyShop'), ConnectResult.done);
      expect(fn.calls.last.$3, {'shopDomain': 'myshop.myshopify.com'});
      expect(opener.opened.single.host, 'myshop.myshopify.com');
      expect(repo.polling, isTrue);
    });

    test('invalid input -> invalidDomain without a call; server 400 -> invalidDomain', () async {
      expect(await repo.connectShopify('myshop.com'), ConnectResult.invalidDomain);
      expect(fn.count('shopify-connect-link'), 0);
      fn.answer('shopify-connect-link', reply(400, {'ok': false, 'error': 'invalidDomain'}));
      expect(await repo.connectShopify('myshop'), ConnectResult.invalidDomain);
    });

    test('409 shopTaken -> shopTaken', () async {
      fn.answer('shopify-connect-link', reply(409, {'ok': false, 'error': 'shopTaken'}));
      expect(await repo.connectShopify('myshop'), ConnectResult.shopTaken);
      expect(opener.opened, isEmpty);
    });

    test('offline, 5xx, a non-https URL or a browser that does not open -> offline', () async {
      fn.answer('shopify-connect-link', offline);
      expect(await repo.connectShopify('myshop'), ConnectResult.offline);
      fn.answers['shopify-connect-link'] = [reply(503)];
      expect(await repo.connectShopify('myshop'), ConnectResult.offline);
      fn.answers['shopify-connect-link'] = [reply(200, {'url': 'http://myshop.myshopify.com/x'})];
      expect(await repo.connectShopify('myshop'), ConnectResult.offline);
      fn.answers['shopify-connect-link'] = [reply(200, {'url': 'https://myshop.myshopify.com/x'})];
      opener.result = false;
      expect(await repo.connectShopify('myshop'), ConnectResult.offline);
      expect(repo.polling, isFalse);
    });

    test('polling: every 3 s, stops as soon as connected', () async {
      fn.answer('shopify-connect-link', reply(200, {'url': 'https://myshop.myshopify.com/x'}));
      fn.answers['shopify-status'] = [notConnected, notConnected, connected];
      final before = fn.count('shopify-status');
      await repo.connectShopify('myshop');
      await timers.elapse(const Duration(seconds: 9));
      expect(fn.count('shopify-status') - before, 3);
      expect(repo.polling, isFalse);
      expect((await repo.watch().first)?.shopDomain, 'myshop.myshopify.com');
      await timers.elapse(const Duration(seconds: 30));
      expect(fn.count('shopify-status') - before, 3);
    });

    test('polling: stops after 60 s when never connected', () async {
      fn.answer('shopify-connect-link', reply(200, {'url': 'https://myshop.myshopify.com/x'}));
      final before = fn.count('shopify-status');
      await repo.connectShopify('myshop');
      await timers.elapse(const Duration(seconds: 120));
      expect(fn.count('shopify-status') - before, 20, reason: '3 s .. 60 s');
      expect(repo.polling, isFalse);
      expect(timers.active, 0);
    });
  });

  test('testConnection = shopify-status connected', () async {
    fn.answer('shopify-status', connected);
    await signIn();
    expect(await repo.testConnection(), isTrue);
  });

  test('sign-out clears the store and stops polling', () async {
    fn.answer('shopify-status', connected);
    await signIn();
    auth.add(AuthState.signedOut);
    await pumpEventQueue();
    expect(await repo.watch().first, isNull);
  });
}
