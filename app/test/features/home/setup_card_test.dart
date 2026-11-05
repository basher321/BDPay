import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/widgets/app_button.dart';

import '../account_test_helpers.dart';

String mark(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('hidden when wallets and Shopify are both done', (tester) async {
    await pumpAccountApp(tester, demoSignedIn: true, storeConnected: true);
    expect(find.byKey(const Key('setupCard')), findsNothing);
  });

  testWidgets('demo without a store: wallet ✓, Shopify !; tapping a row opens সেটিংস', (tester) async {
    await pumpAccountApp(tester, demoSignedIn: true);
    expect(find.text('সেটআপ বাকি'), findsOneWidget);
    expect(mark(tester, 'setupWalletMark'), '✓');
    expect(mark(tester, 'setupShopifyMark'), '!');
    await tester.tap(find.byKey(const Key('setupShopifyRow')));
    await settle(tester);
    expect(isTabActive(tester, AppTab.settings), isTrue);
    expect(find.byKey(const Key('shopifySection')), findsOneWidget);
  });

  testWidgets('new merchant adds bkash 01811222333 sim1 -> the wallet row turns ✓', (tester) async {
    await pumpAccountApp(tester);
    await signIn(tester, 'newshop', businessName: 'আমার দোকান');
    expect(mark(tester, 'setupWalletMark'), '!');
    await tester.tap(find.byKey(const Key('setupWalletRow')));
    await settle(tester);
    await tapVisible(tester, find.byKey(const Key('addWalletButton')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('opChip-bkash')));
    await tester.enterText(find.byKey(const Key('walletNumberField')), '01811222333');
    await tester.tap(find.byKey(const Key('simChip-sim1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveWalletButton')));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('walletSheet')), findsNothing);
    await openTab(tester, AppTab.home);
    expect(mark(tester, 'setupWalletMark'), '✓');
    expect(mark(tester, 'setupShopifyMark'), '!');
  });

  testWidgets('connecting "MyShop" shows myshop.myshopify.com and the setup card disappears', (tester) async {
    await pumpAccountApp(tester, demoSignedIn: true);
    expect(find.byKey(const Key('setupCard')), findsOneWidget);
    await openTab(tester, AppTab.settings);
    await tester.enterText(find.byKey(const Key('shopField')), 'MyShop');
    await tester.tap(find.byKey(const Key('connectShopifyButton')));
    await tester.pump();
    expect(find.text('যুক্ত হচ্ছে…'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byKey(const Key('connectShopifyButton'))).onPressed, isNull);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(tester.widget<Text>(find.byKey(const Key('shopDomain'))).data, 'myshop.myshopify.com');
    expect(find.text('যুক্ত হয়েছে এইমাত্র'), findsOneWidget);
    await openTab(tester, AppTab.home);
    expect(find.byKey(const Key('setupCard')), findsNothing);
  });
}
