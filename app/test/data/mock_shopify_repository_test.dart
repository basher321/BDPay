import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/models/shopify_store.dart';

import 'mock_account_test_helpers.dart';

void main() {
  test('not connected at start', () async {
    final m = AccountMocks(demoSignedIn: true);
    expect(await m.store.watch().first, isNull);
  });

  test('connect waits 1 s, then saves the normalised domain with a UTC time', () async {
    final m = AccountMocks(demoSignedIn: true);
    final watch = Stopwatch()..start();
    final result = await m.store.connectShopify('MyShop');
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(1000));
    expect(result, ConnectResult.done);
    final ShopifyStore s = m.data.current!.store!;
    expect(s.shopDomain, 'myshop.myshopify.com');
    expect(s.connectedAt!.isUtc, isTrue);
  });

  test('invalid domain -> invalidDomain; offline -> offline', () async {
    final m = AccountMocks(demoSignedIn: true);
    expect(await m.store.connectShopify('myshop.com'), ConnectResult.invalidDomain);
    await m.setOnline(false);
    expect(await m.store.connectShopify('myshop'), ConnectResult.offline);
    expect(m.data.current!.store, isNull);
  });

  // Spec 13 rule 5: there is no disconnect any more (plan 13 D135).
  test('testConnection returns the online state', () async {
    final m = AccountMocks(demoSignedIn: true);
    await m.store.connectShopify('myshop');
    expect(await m.store.testConnection(), isTrue);
    await m.setOnline(false);
    expect(await m.store.testConnection(), isFalse);
  });
}
