import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/app.dart';
import 'package:verifier/data/account_providers.dart';
import 'package:verifier/data/mock/mock_account_data.dart';
import 'package:verifier/data/mock/mock_auth_repository.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/data/providers.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/domain/repositories/auth_repository.dart';
import 'package:verifier/shell/app_bottom_nav.dart';
import 'package:verifier/shell/app_shell.dart';
import 'package:verifier/shell/app_tab.dart';

/// 2026-10-29 12:00 Asia/Dhaka.
final fixedNow = DateTime.utc(2026, 10, 29, 6);

/// Fresh mocks and a movable clock for one spec 05 test.
class AccountHarness {
  AccountHarness({bool demoSignedIn = false, bool storeConnected = false, List<SmsTransaction>? items}) {
    health = MockDeviceHealthRepository(startedAt: fixedNow, clock: () => now);
    transactions = MockTransactionRepository(health, items ?? buildSampleTransactions(fixedNow));
    data = demoSignedIn
        ? MockAccountData.demoSignedIn(health: health, clock: () => now, storeConnected: storeConnected)
        : MockAccountData(health: health, clock: () => now);
  }

  DateTime now = fixedNow;
  final ticker = StreamController<int>.broadcast();
  late final MockDeviceHealthRepository health;
  final settings = MockSettingsRepository();
  late final MockTransactionRepository transactions;
  late final MockAccountData data;
  late ProviderContainer container;
}

/// Pumps the whole app. Signed out unless [demoSignedIn]. [wrapAuth] can replace the auth repository.
Future<AccountHarness> pumpAccountApp(
  WidgetTester tester, {
  bool demoSignedIn = false,
  bool storeConnected = false,
  List<SmsTransaction>? items,
  AuthRepository Function(MockAuthRepository mock)? wrapAuth,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = AccountHarness(demoSignedIn: demoSignedIn, storeConnected: storeConnected, items: items);
  final auth = MockAuthRepository(h.data);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tickerProvider.overrideWith((ref) => h.ticker.stream),
        clockProvider.overrideWith((ref) {
          ref.watch(tickerProvider);
          return h.now;
        }),
        deviceHealthRepositoryProvider.overrideWithValue(h.health),
        settingsRepositoryProvider.overrideWithValue(h.settings),
        transactionRepositoryProvider.overrideWithValue(h.transactions),
        mockAccountDataProvider.overrideWithValue(h.data),
        authRepositoryProvider.overrideWithValue(wrapAuth == null ? auth : wrapAuth(auth)),
        ...overrides,
      ],
      child: const BdpayApp(),
    ),
  );
  await settle(tester);
  h.container = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
  return h;
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// Spec 16: "demo" logs in (password 123456); any other username opens a new account (password secret123),
/// then the business name when given.
Future<void> signIn(WidgetTester tester, String username, {String? password, String? businessName}) async {
  final demo = username == 'demo';
  if (!demo) {
    await tester.tap(find.byKey(const Key('toggleMode')));
    await tester.pump();
  }
  await tester.enterText(find.byKey(const Key('usernameField')), username);
  await tester.enterText(find.byKey(const Key('passwordField')), password ?? (demo ? '123456' : 'secret123'));
  await tester.pump();
  await tester.tap(find.byKey(const Key('loginButton')));
  await settle(tester);
  if (businessName != null) {
    await tester.enterText(find.byKey(const Key('businessNameField')), businessName);
    await tester.pump();
    await tester.tap(find.byKey(const Key('startButton')));
    await settle(tester);
  }
}

bool isTabActive(WidgetTester tester, AppTab tab) =>
    tester.widget<NavItem>(find.byKey(ValueKey('nav-${tab.name}'))).active;

Future<void> openTab(WidgetTester tester, AppTab tab) async {
  await tester.tap(find.byKey(ValueKey('nav-${tab.name}')));
  await settle(tester);
}

/// Scrolls [finder] into view inside the current scrollable, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// Waits for a toast to disappear so no timer is left at the end of a test.
Future<void> clearToast(WidgetTester tester) => tester.pump(const Duration(seconds: 2));
