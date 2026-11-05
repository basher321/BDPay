import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/theme/colors.dart';
import 'package:verifier/domain/enums.dart';
import 'package:verifier/shell/app_header.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/widgets/app_switch.dart';

import '../account_test_helpers.dart';

Future<AccountHarness> pumpSettings(WidgetTester tester, {bool storeConnected = false, List<dynamic>? items}) async {
  final h = await pumpAccountApp(tester, demoSignedIn: true, storeConnected: storeConnected, items: items?.cast());
  await openTab(tester, AppTab.settings);
  return h;
}

Future<void> openAddSheet(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('addWalletButton')));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> fillWallet(WidgetTester tester, MfsOperator op, String number, {String sim = 'sim1'}) async {
  await tester.tap(find.byKey(Key('opChip-${op.name}')));
  await tester.enterText(find.byKey(const Key('walletNumberField')), number);
  await tester.tap(find.byKey(Key('simChip-$sim')));
  await tester.pump();
}

Future<void> saveWallet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('saveWalletButton')));
  await settle(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

Finder walletRows() => find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
    (w.key! as ValueKey<String>).value.startsWith('walletRow-'));

Future<void> toggleWallet(WidgetTester tester, String id) async {
  await tapVisible(tester, find.byKey(Key('walletSwitch-$id')));
  await tester.pump(const Duration(milliseconds: 300));
}

String? walletError(WidgetTester tester) {
  final f = find.byKey(const Key('walletError'));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

void main() {
  group('wallets', () {
    testWidgets('demo shows its 4 wallets with "{account type} • {sim}"', (tester) async {
      await pumpSettings(tester);
      expect(walletRows(), findsNWidgets(4));
      expect(find.text('01700000001'), findsOneWidget);
      expect(find.text('মার্চেন্ট • সিম ১'), findsNWidgets(2));
      expect(find.text('মার্চেন্ট • সিম ২'), findsNWidgets(2));
    });

    testWidgets('adding nagad 01700000002 for demo shows "এই নম্বর আগেই যোগ করা আছে"', (tester) async {
      await pumpSettings(tester);
      await openAddSheet(tester);
      await fillWallet(tester, MfsOperator.nagad, '01700000002', sim: 'sim2');
      await saveWallet(tester);
      expect(walletError(tester), 'এই নম্বর আগেই যোগ করা আছে');
    });

    testWidgets('an invalid number shows "সঠিক নম্বর দিন (01XXXXXXXXX)"', (tester) async {
      await pumpSettings(tester);
      await openAddSheet(tester);
      await fillWallet(tester, MfsOperator.bkash, '01211222333', sim: 'unknown');
      await saveWallet(tester);
      expect(walletError(tester), 'সঠিক নম্বর দিন (01XXXXXXXXX)');
    });

    testWidgets('a second active bkash on sim1 shows simTaken; on sim2 it saves', (tester) async {
      await pumpSettings(tester);
      await openAddSheet(tester);
      expect(find.text('ব্যবসার পেমেন্ট নিতে মার্চেন্ট অ্যাকাউন্ট ব্যবহার করুন। ব্যক্তিগত অ্যাকাউন্ট সমর্থিত নয়।'),
          findsOneWidget);
      await fillWallet(tester, MfsOperator.bkash, '01811222333');
      await saveWallet(tester);
      expect(walletError(tester), 'এই সিমে এই অপারেটরের আরেকটি ওয়ালেট আছে');
      await tester.tap(find.byKey(const Key('simChip-sim2')));
      await tester.pump();
      await saveWallet(tester);
      expect(find.byKey(const Key('walletSheet')), findsNothing);
      expect(walletRows(), findsNWidgets(5));
      expect(find.text('01811222333'), findsOneWidget);
    });

    testWidgets('edit mode: operator and number are read-only; account type and label change', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.text('01700000002'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('walletNumberField')), findsNothing);
      expect(find.byKey(const Key('opChip-nagad')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('walletNumberReadOnly'))).data, '01700000002');
      await tester.tap(find.byKey(const Key('accountChip-agent')));
      await tester.enterText(find.byKey(const Key('walletLabelField')), 'দোকান');
      await saveWallet(tester);
      expect(find.text('এজেন্ট • সিম ১'), findsOneWidget);
      expect(find.text('দোকান'), findsOneWidget);
    });

    testWidgets('an inactive wallet is faded to 50%', (tester) async {
      await pumpSettings(tester);
      await toggleWallet(tester, 'w_demo_4');
      expect(tester.widget<Opacity>(find.byKey(const Key('walletRow-w_demo_4'))).opacity, 0.5);
      expect(tester.widget<Opacity>(find.byKey(const Key('walletRow-w_demo_1'))).opacity, 1);
    });

    testWidgets('turning off the last active wallet shows the confirm dialog; "না" keeps it on', (tester) async {
      await pumpSettings(tester);
      for (final id in ['w_demo_1', 'w_demo_2', 'w_demo_3']) {
        await toggleWallet(tester, id);
      }
      expect(find.byKey(const Key('confirmText')), findsNothing);
      await toggleWallet(tester, 'w_demo_4');
      expect(find.text('কোনো সক্রিয় ওয়ালেট থাকবে না — পেমেন্ট যাচাই বন্ধ হয়ে যাবে। নিশ্চিত?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmNo')));
      await settle(tester);
      expect(tester.widget<AppSwitch>(find.byKey(const Key('walletSwitch-w_demo_4'))).value, isTrue);
      await toggleWallet(tester, 'w_demo_4');
      await tester.tap(find.byKey(const Key('confirmYes')));
      await settle(tester);
      expect(tester.widget<AppSwitch>(find.byKey(const Key('walletSwitch-w_demo_4'))).value, isFalse);
    });

    testWidgets('turning on a wallet that clashes on its SIM shows the simTaken toast (D7)', (tester) async {
      await pumpSettings(tester);
      await toggleWallet(tester, 'w_demo_1');
      await openAddSheet(tester);
      await fillWallet(tester, MfsOperator.bkash, '01811222333');
      await saveWallet(tester);
      await toggleWallet(tester, 'w_demo_1');
      expect(find.text('এই সিমে এই অপারেটরের আরেকটি ওয়ালেট আছে'), findsOneWidget);
      expect(tester.widget<AppSwitch>(find.byKey(const Key('walletSwitch-w_demo_1'))).value, isFalse);
      await clearToast(tester);
    });
  });

  group('Shopify', () {
    testWidgets('invalid "myshop.com" shows "শুধু .myshopify.com ঠিকানা দিন"', (tester) async {
      await pumpSettings(tester);
      expect(find.text('আপনার Shopify স্টোরের ঠিকানা দিন'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('shopField')), 'myshop.com');
      await tester.tap(find.byKey(const Key('connectShopifyButton')));
      await settle(tester);
      expect(find.text('শুধু .myshopify.com ঠিকানা দিন'), findsOneWidget);
    });

    testWidgets('connecting while offline shows "ইন্টারনেট নেই"', (tester) async {
      final h = await pumpSettings(tester);
      await h.health.setOnline(false);
      await settle(tester);
      await tester.enterText(find.byKey(const Key('shopField')), 'myshop');
      await tester.tap(find.byKey(const Key('connectShopifyButton')));
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('ইন্টারনেট নেই'), findsOneWidget);
      expect(find.byKey(const Key('shopDomain')), findsNothing);
    });

    testWidgets('test connection toasts online / offline', (tester) async {
      final h = await pumpSettings(tester, storeConnected: true);
      await tapVisible(tester, find.byKey(const Key('testShopifyButton')));
      expect(find.text('Shopify সংযুক্ত আছে'), findsOneWidget);
      await clearToast(tester);
      await h.health.setOnline(false);
      await settle(tester);
      await tapVisible(tester, find.byKey(const Key('testShopifyButton')));
      expect(find.text('সংযোগ পাওয়া যায়নি'), findsOneWidget);
      await clearToast(tester);
    });

    // Spec 13 rule 5 replaces spec 05's confirm dialog (plan 13 D135).
    testWidgets('disconnect shows the uninstall instructions; "ঠিক আছে" closes them and keeps the store', (tester) async {
      await pumpSettings(tester, storeConnected: true);
      await tapVisible(tester, find.byKey(const Key('disconnectShopifyButton')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Shopify বিচ্ছিন্ন করতে: Shopify অ্যাডমিন > Apps > BDPay > Uninstall. এরপর নতুন অর্ডার আর যাচাই হবে না।'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('shopifyDisconnectOk')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('shopifyDisconnectSheet')), findsNothing);
      expect(find.byKey(const Key('shopDomain')), findsOneWidget);
    });
  });

  group('device, operators, developer', () {
    testWidgets('device ID is read-only; saving the name shows "সেটিংস সংরক্ষিত হয়েছে"', (tester) async {
      final h = await pumpSettings(tester);
      expect(tester.widget<Text>(find.byKey(const Key('deviceIdText'))).data, 'BDP-A1');
      await tester.enterText(find.byKey(const Key('deviceNameField')), 'কাউন্টার ২');
      await tapVisible(tester, find.byKey(const Key('saveSettingsButton')));
      expect(find.text('সেটিংস সংরক্ষিত হয়েছে'), findsOneWidget);
      expect(h.settings.current.deviceName, 'কাউন্টার ২');
      await clearToast(tester);
    });

    testWidgets('"সাথে সাথে পাঠান" saves autoSend at once', (tester) async {
      final h = await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('autoSendSwitch')));
      expect(h.settings.current.autoSend, isFalse);
    });

    testWidgets('operator switches use brand colours; turning Upay off shows "বন্ধ" on হোম', (tester) async {
      final h = await pumpSettings(tester);
      for (final op in MfsOperator.values) {
        expect(tester.widget<AppSwitch>(find.byKey(Key('opSwitch-${op.name}'))).activeColor, op.brandColor);
      }
      await tapVisible(tester, find.byKey(const Key('opSwitch-upay')));
      expect(h.settings.current.enabledOperators.contains(MfsOperator.upay), isFalse);
      await openTab(tester, AppTab.home);
      expect(find.text('বন্ধ'), findsOneWidget);
    });

    testWidgets('the offline switch appears only in developer mode; on -> "অফলাইন" in the header pill',
        (tester) async {
      await pumpSettings(tester);
      expect(find.byKey(const Key('offlineSwitch')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('devModeSwitch')));
      expect(find.byKey(const Key('offlineSwitch')), findsOneWidget);
      expect(tester.widget<AppSwitch>(find.byKey(const Key('offlineSwitch'))).activeColor, AppColors.er);
      await tapVisible(tester, find.byKey(const Key('offlineSwitch')));
      final pill = find.descendant(of: find.byType(AppHeader), matching: find.text('অফলাইন'));
      expect(pill, findsOneWidget);
    });
  });

  group('account and footer', () {
    testWidgets('shows business name and email', (tester) async {
      await pumpSettings(tester);
      expect(tester.widget<Text>(find.byKey(const Key('accountBusinessName'))).data, 'নমুনা স্টোর');
      expect(tester.widget<Text>(find.byKey(const Key('accountUsername'))).data, 'demo');
    });

    testWidgets('logout with 2 queue items shows "আগে বাকি 2 টি এসএমএস পাঠান"', (tester) async {
      await pumpSettings(tester);
      await tapVisible(tester, find.byKey(const Key('logoutButton')));
      expect(find.text('আগে বাকি 2 টি এসএমএস পাঠান'), findsOneWidget);
      expect(find.byKey(const Key('confirmText')), findsNothing);
      await clearToast(tester);
    });

    testWidgets('logout with 0 items: "না" stays, "হ্যাঁ" returns to the login screen', (tester) async {
      await pumpSettings(tester, items: const []);
      await tapVisible(tester, find.byKey(const Key('logoutButton')));
      expect(find.text('লগ আউট করবেন? এই ফোনে পেমেন্ট যাচাই বন্ধ হবে।'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirmNo')));
      await settle(tester);
      expect(find.byType(AppHeader), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('logoutButton')));
      await tester.tap(find.byKey(const Key('confirmYes')));
      await settle(tester);
      expect(find.byKey(const Key('usernameField')), findsOneWidget);
    });

    testWidgets('signing out and in again as demo shows the same data', (tester) async {
      await pumpSettings(tester, items: const []);
      await toggleWallet(tester, 'w_demo_4');
      await tapVisible(tester, find.byKey(const Key('logoutButton')));
      await tester.tap(find.byKey(const Key('confirmYes')));
      await settle(tester);
      await signIn(tester, 'demo');
      await openTab(tester, AppTab.settings);
      expect(walletRows(), findsNWidgets(4));
      expect(tester.widget<AppSwitch>(find.byKey(const Key('walletSwitch-w_demo_4'))).value, isFalse);
    });

    testWidgets('footer shows the privacy text and the version', (tester) async {
      await pumpSettings(tester);
      expect(
        find.text('এই অ্যাপ শুধু bKash, Nagad, Rocket ও Upay-এর এসএমএস পড়ে। ব্যক্তিগত মেসেজ পড়া বা পাঠানো হয় না।'),
        findsOneWidget,
      );
      expect(find.text('ভার্সন 1.0.0+1'), findsOneWidget);
    });
  });
}
