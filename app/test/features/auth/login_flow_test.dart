import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/mock/mock_auth_repository.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/models/auth_state.dart';
import 'package:verifier/domain/repositories/auth_repository.dart';
import 'package:verifier/shell/app_header.dart';
import 'package:verifier/shell/app_tab.dart';
import 'package:verifier/widgets/app_button.dart';

import '../account_test_helpers.dart';

/// Counts signIn calls and passes everything to the mock.
class CountingAuth implements AuthRepository {
  CountingAuth(this.inner);

  final MockAuthRepository inner;
  final signIns = <String>[];

  @override
  Stream<AuthState> watch() => inner.watch();

  @override
  Future<AuthResult> signIn(String username, String password) {
    signIns.add(username);
    return inner.signIn(username, password);
  }

  @override
  Future<AuthResult> signUp(String username, String password) => inner.signUp(username, password);

  @override
  Future<void> createMerchant(String businessName) => inner.createMerchant(businessName);

  @override
  Future<void> signOut() => inner.signOut();
}

AppButton button(WidgetTester tester, String key) => tester.widget<AppButton>(find.byKey(Key(key)));

Future<void> fill(WidgetTester tester, String username, String password) async {
  await tester.enterText(find.byKey(const Key('usernameField')), username);
  await tester.enterText(find.byKey(const Key('passwordField')), password);
  await tester.pump();
}

void main() {
  testWidgets('app start shows the login screen; the password is hidden', (tester) async {
    await pumpAccountApp(tester);
    expect(find.text('লগইন করুন'), findsOneWidget);
    expect(find.text('BDPay'), findsOneWidget);
    expect(find.byType(AppHeader), findsNothing);
    final pw = tester.widget<TextField>(find.byKey(const Key('passwordField')));
    expect(pw.obscureText, isTrue);
  });

  testWidgets('demo / 123456 shows the হোম tab', (tester) async {
    await pumpAccountApp(tester);
    await signIn(tester, 'demo');
    expect(find.byType(AppHeader), findsOneWidget);
    expect(isTabActive(tester, AppTab.home), isTrue);
  });

  testWidgets('wrong password shows "ইউজারনেম বা পাসওয়ার্ড ভুল" and keeps the username', (tester) async {
    await pumpAccountApp(tester);
    await signIn(tester, 'demo', password: '999999');
    expect(find.text('ইউজারনেম বা পাসওয়ার্ড ভুল'), findsOneWidget);
    expect(find.byType(AppHeader), findsNothing);
    expect(tester.widget<TextField>(find.byKey(const Key('usernameField'))).controller!.text, 'demo');
  });

  testWidgets('a bad username shows the username rule', (tester) async {
    await pumpAccountApp(tester);
    await fill(tester, 'a!', '123456');
    await tester.tap(find.byKey(const Key('loginButton')));
    await settle(tester);
    expect(find.text('ইউজারনেম: ইংরেজি ছোট অক্ষর, সংখ্যা বা _ — ৩ থেকে ২০টি'), findsOneWidget);
  });

  testWidgets('username is sent trimmed and lower case; two fast taps send one request', (tester) async {
    late CountingAuth counting;
    await pumpAccountApp(tester, wrapAuth: (m) => counting = CountingAuth(m));
    await fill(tester, ' Demo ', '123456');
    await tester.tap(find.byKey(const Key('loginButton')));
    await tester.tap(find.byKey(const Key('loginButton')), warnIfMissed: false);
    await settle(tester);
    expect(counting.signIns, ['demo']);
    expect(find.byType(AppHeader), findsOneWidget);
  });

  testWidgets('offline shows "ইন্টারনেট নেই"', (tester) async {
    final h = await pumpAccountApp(tester);
    await h.health.setOnline(false);
    await settle(tester);
    await fill(tester, 'demo', '123456');
    await tester.tap(find.byKey(const Key('loginButton')));
    await settle(tester);
    expect(find.text('ইন্টারনেট নেই'), findsOneWidget);
  });

  testWidgets('forgot password shows the support help line', (tester) async {
    await pumpAccountApp(tester);
    expect(find.byKey(const Key('forgotHelp')), findsNothing);
    await tester.tap(find.byKey(const Key('forgotPassword')));
    await tester.pump();
    expect(find.byKey(const Key('forgotHelp')), findsOneWidget);
  });

  testWidgets('new account: a taken username and a short password show their errors', (tester) async {
    await pumpAccountApp(tester);
    await tester.tap(find.byKey(const Key('toggleMode')));
    await tester.pump();
    expect(find.text('নতুন অ্যাকাউন্ট খুলুন'), findsWidgets);
    await fill(tester, 'demo', '123456');
    await tester.tap(find.byKey(const Key('loginButton')));
    await settle(tester);
    expect(find.text('এই ইউজারনেম আগেই নেওয়া হয়েছে'), findsOneWidget);
    await fill(tester, 'newshop', '123');
    await tester.tap(find.byKey(const Key('loginButton')));
    await settle(tester);
    expect(find.text('পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের দিন'), findsOneWidget);
  });

  testWidgets('a new account goes to the business name screen, then to হোম with both setup rows as !',
      (tester) async {
    await pumpAccountApp(tester);
    await signIn(tester, 'newshop');
    expect(find.text('আপনার ব্যবসার নাম'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('businessNameField')), 'a');
    await tester.pump();
    expect(button(tester, 'startButton').onPressed, isNull);
    await tester.enterText(find.byKey(const Key('businessNameField')), 'আমার দোকান');
    await tester.pump();
    await tester.tap(find.byKey(const Key('startButton')));
    await settle(tester);
    expect(isTabActive(tester, AppTab.home), isTrue);
    expect(find.text('সেটআপ বাকি'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('setupWalletMark'))).data, '!');
    expect(tester.widget<Text>(find.byKey(const Key('setupShopifyMark'))).data, '!');
  });
}
