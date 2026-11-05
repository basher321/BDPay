import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/account_providers.dart';
import 'package:verifier/data/mock/mock_alerts_repository.dart';
import 'package:verifier/data/mock/mock_store.dart';
import 'package:verifier/data/mock/mock_wallet_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/domain/models/app_alert.dart';
import 'package:verifier/domain/models/shopify_store.dart';
import 'package:verifier/domain/models/wallet.dart';
import 'package:verifier/domain/repositories/repository_errors.dart';
import 'package:verifier/domain/repositories/store_repository.dart';
import 'package:verifier/domain/repositories/wallet_repository.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/shell/not_configured_screen.dart';

import 'account_test_helpers.dart';

/// A store repository the test drives: connectShopify answers [nextResult]; the test sets the store.
class DrivenStoreRepository implements StoreRepository {
  DrivenStoreRepository([ShopifyStore? store]) : state = MockStore(store);

  final MockStore<ShopifyStore?> state;
  ConnectResult nextResult = ConnectResult.done;
  final connected = <String>[];

  @override
  Stream<ShopifyStore?> watch() => state.watch();

  @override
  Future<ConnectResult> connectShopify(String shopDomain) async {
    connected.add(shopDomain);
    return nextResult;
  }

  @override
  Future<bool> testConnection() async => state.value != null;
}

/// Wraps the mock wallet repository and can be told to fail with no network.
class OfflineWallets implements WalletRepository {
  OfflineWallets(this.inner);

  final WalletRepository inner;
  bool offline = true;

  @override
  Stream<List<Wallet>> watch() => inner.watch();

  @override
  Future<AddWalletResult> add(Wallet w) => offline ? Future.error(const OfflineError()) : inner.add(w);

  @override
  Future<AddWalletResult> update(Wallet w) => offline ? Future.error(const OfflineError()) : inner.update(w);

  @override
  Future<AddWalletResult> setActive(String id, bool on) =>
      offline ? Future.error(const OfflineError()) : inner.setActive(id, on);
}

const _shop = ShopifyStore(shopDomain: 'myshop.myshopify.com');

Future<DrivenStoreRepository> pumpWithStore(WidgetTester tester, ShopifyStore? store) async {
  final repo = DrivenStoreRepository(store);
  await pumpAccountApp(tester, demoSignedIn: true, overrides: [storeRepositoryProvider.overrideWithValue(repo)]);
  await openTab(tester, AppTab.settings);
  return repo;
}

void main() {
  group('Shopify section (rules 4 and 5)', () {
    testWidgets('reconnectNeeded: amber line and "আবার যুক্ত করুন" (same connect flow); no test button, no guide',
        (tester) async {
      final repo = await pumpWithStore(tester, const ShopifyStore(shopDomain: 'myshop.myshopify.com', lastError: 'reconnectNeeded'));
      expect(find.text('Shopify-এর সংযোগ শেষ হয়ে গেছে'), findsOneWidget);
      expect(find.byKey(const Key('testShopifyButton')), findsNothing);
      expect(find.byKey(const Key('shopifyGuide')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('reconnectShopifyButton')));
      expect(repo.connected, ['myshop.myshopify.com']);
      expect(find.text('যুক্ত হচ্ছে…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
    });

    testWidgets('setup guide only when connected; it opens with the 5 steps', (tester) async {
      final repo = await pumpWithStore(tester, null);
      expect(find.byKey(const Key('shopifyGuide')), findsNothing);
      repo.state.value = _shop;
      await settle(tester);
      expect(find.byKey(const Key('shopifyGuide')), findsOneWidget);
      expect(find.byKey(const Key('shopifyGuideStep0')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('shopifyGuideToggle')));
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('shopifyGuideStep$i')), findsOneWidget);
      }
      expect(find.textContaining('Check the Shopify menu names'), findsNothing);
    });

    testWidgets('connected view without a connected time (D133 C)', (tester) async {
      await pumpWithStore(tester, _shop);
      expect(find.byKey(const Key('shopDomain')), findsOneWidget);
      expect(find.textContaining('যুক্ত হয়েছে'), findsNothing);
      expect(find.byKey(const Key('testShopifyButton')), findsOneWidget);
    });

    testWidgets('rule 4: "যুক্ত হচ্ছে…" after the link opens, then the connected view when status says connected',
        (tester) async {
      final repo = await pumpWithStore(tester, null);
      await tester.enterText(find.byKey(const Key('shopField')), 'myshop');
      await tapVisible(tester, find.byKey(const Key('connectShopifyButton')));
      expect(find.text('যুক্ত হচ্ছে…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('যুক্ত হচ্ছে…'), findsOneWidget);
      repo.state.value = _shop;
      await settle(tester);
      expect(find.byKey(const Key('shopDomain')), findsOneWidget);
      expect(find.byKey(const Key('shopField')), findsNothing);
    });

    testWidgets('rule 4: after 60 s without connecting -> "এখনো যুক্ত হয়নি — আবার চেষ্টা করুন" and the button works again',
        (tester) async {
      await pumpWithStore(tester, null);
      await tester.enterText(find.byKey(const Key('shopField')), 'myshop');
      await tapVisible(tester, find.byKey(const Key('connectShopifyButton')));
      await tester.pump(const Duration(seconds: 59));
      expect(find.text('এখনো যুক্ত হয়নি — আবার চেষ্টা করুন'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('এখনো যুক্ত হয়নি — আবার চেষ্টা করুন'), findsOneWidget);
      expect(find.text('Shopify যুক্ত করুন'), findsOneWidget);
    });

    testWidgets('shopTaken -> "এই স্টোর অন্য একটি BDPay অ্যাকাউন্টে যুক্ত"', (tester) async {
      final repo = await pumpWithStore(tester, null);
      repo.nextResult = ConnectResult.shopTaken;
      await tester.enterText(find.byKey(const Key('shopField')), 'myshop');
      await tapVisible(tester, find.byKey(const Key('connectShopifyButton')));
      expect(find.text('এই স্টোর অন্য একটি BDPay অ্যাকাউন্টে যুক্ত'), findsOneWidget);
    });

    testWidgets('disconnect instructions sheet', (tester) async {
      await pumpWithStore(tester, _shop);
      await tapVisible(tester, find.byKey(const Key('disconnectShopifyButton')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('shopifyDisconnectSheet')), findsOneWidget);
      expect(find.text('ঠিক আছে'), findsOneWidget);
    });
  });

  group('alerts card (rule 6)', () {
    AppAlert alert(String id, int hour) => AppAlert(
          id: id,
          kind: 'phoneSilent',
          openedAt: DateTime.utc(2026, 10, 29, hour),
          title: 'শিরোনাম $id',
          hint: 'পরামর্শ $id',
        );

    testWidgets('two alerts newest first, between the setup card and the device card', (tester) async {
      final alerts = MockAlertsRepository([alert('old', 3), alert('new', 5)]);
      await pumpAccountApp(tester, demoSignedIn: true, overrides: [alertsRepositoryProvider.overrideWithValue(alerts)]);
      expect(find.byKey(const Key('alertsCard')), findsOneWidget);
      final newY = tester.getTopLeft(find.byKey(const Key('alert-new'))).dy;
      final oldY = tester.getTopLeft(find.byKey(const Key('alert-old'))).dy;
      expect(newY, lessThan(oldY));
      final setupY = tester.getTopLeft(find.byKey(const Key('setupCard'))).dy;
      final deviceY = tester.getTopLeft(find.byKey(const Key('deviceCard'))).dy;
      expect(setupY, lessThan(newY));
      expect(oldY, lessThan(deviceY));
      expect(find.text('শিরোনাম new'), findsOneWidget);
      expect(find.text('পরামর্শ old'), findsOneWidget);
    });

    testWidgets('hidden when there are none', (tester) async {
      await pumpAccountApp(tester, demoSignedIn: true);
      expect(find.byKey(const Key('alertsCard')), findsNothing);
    });
  });

  group('wallet sheet errors (rule 3)', () {
    testWidgets('no network -> "ইন্টারনেট নেই", nothing saved, typed values kept', (tester) async {
      late OfflineWallets wallets;
      final h = await pumpAccountApp(tester, demoSignedIn: true, overrides: [
        walletRepositoryProvider.overrideWith((ref) {
          wallets = OfflineWallets(MockWalletRepository(ref.watch(mockAccountDataProvider)));
          return wallets;
        }),
      ]);
      await openTab(tester, AppTab.settings);
      await tapVisible(tester, find.byKey(const Key('addWalletButton')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(Key('opChip-${MfsOperator.upay.name}')));
      await tester.enterText(find.byKey(const Key('walletNumberField')), '01811222333');
      await tester.enterText(find.byKey(const Key('walletLabelField')), 'কাউন্টার');
      await tester.tap(find.byKey(const Key('saveWalletButton')));
      await settle(tester);
      expect(find.text('ইন্টারনেট নেই'), findsOneWidget);
      expect(find.text('01811222333'), findsOneWidget);
      expect(find.text('কাউন্টার'), findsOneWidget);
      expect(h.data.current!.wallets.length, 4);
    });

    testWidgets('after duplicate the typed number stays', (tester) async {
      await pumpAccountApp(tester, demoSignedIn: true);
      await openTab(tester, AppTab.settings);
      await tapVisible(tester, find.byKey(const Key('addWalletButton')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(Key('opChip-${MfsOperator.bkash.name}')));
      await tester.enterText(find.byKey(const Key('walletNumberField')), '01700000001');
      await tester.tap(find.byKey(const Key('saveWalletButton')));
      await settle(tester);
      expect(find.text('এই নম্বর আগেই যোগ করা আছে'), findsOneWidget);
      expect(find.text('01700000001'), findsWidgets);
    });
  });

  testWidgets('missing dart-define -> only "অ্যাপ কনফিগার করা হয়নি"', (tester) async {
    await tester.pumpWidget(const NotConfiguredApp());
    await tester.pump();
    expect(find.text('অ্যাপ কনফিগার করা হয়নি'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
