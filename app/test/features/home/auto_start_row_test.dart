import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/theme/app_theme.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/data/providers.dart';
import 'package:verifier/domain/models/device_health.dart';
import 'package:verifier/features/home/home_screen.dart';
import 'package:verifier/features/home/home_summary.dart';
import 'package:verifier/l10n/app_localizations.dart';

import '../../signed_in_overrides.dart';

final now = DateTime.utc(2026, 10, 29, 6);

class CountingHealth extends MockDeviceHealthRepository {
  CountingHealth(String maker)
      : super(
          initial: DeviceHealth(
            smsPermission: true,
            batteryOptimizationOff: false,
            internetOnline: true,
            monitoring: true,
            lastServerContactAt: now,
            maker: maker,
          ),
        );

  int opened = 0;

  @override
  Future<void> openAppSettings() async => opened++;
}

Future<CountingHealth> pumpWithMaker(WidgetTester tester, String maker) async {
  tester.view.physicalSize = const Size(420, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final health = CountingHealth(maker);
  final ticker = StreamController<int>.broadcast();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tickerProvider.overrideWith((ref) => ticker.stream),
        clockProvider.overrideWithValue(now),
        deviceHealthRepositoryProvider.overrideWithValue(health),
        settingsRepositoryProvider.overrideWithValue(MockSettingsRepository()),
        transactionRepositoryProvider.overrideWithValue(MockTransactionRepository(health, buildSampleTransactions(now))),
        ...signedInOverrides(),
      ],
      child: MaterialApp(
        theme: buildAppTheme(),
        locale: const Locale('bn'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const Scaffold(body: HomeScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return health;
}

void main() {
  test('the row is for the 10 listed makers only', () {
    for (final m in ['xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'vivo', 'infinix', 'tecno', 'huawei', 'honor']) {
      expect(showsAutoStartRow(m), isTrue, reason: m);
    }
    expect(showsAutoStartRow('Xiaomi'), isTrue);
    expect(showsAutoStartRow('google'), isFalse);
    expect(showsAutoStartRow('samsung'), isFalse);
    expect(showsAutoStartRow(null), isFalse);
  });

  testWidgets('other makers: no row, the spec 02 count is unchanged', (tester) async {
    await pumpWithMaker(tester, 'google');
    expect(find.byKey(const Key('autoStartRow')), findsNothing);
    expect(find.text('1 টি সমস্যা'), findsOneWidget);
  });

  testWidgets('xiaomi: row with hint and force-stop text; a problem until "করেছি"', (tester) async {
    final health = await pumpWithMaker(tester, 'xiaomi');
    expect(find.text('অটোস্টার্ট চালু করুন'), findsOneWidget);
    expect(find.text('ফোনের সেটিং-এ BDPay-এর অটোস্টার্ট ও ব্যাকগ্রাউন্ড চালু রাখুন'), findsOneWidget);
    expect(find.text('অ্যাপ জোর করে বন্ধ করবেন না'), findsOneWidget);
    expect(find.text('2 টি সমস্যা'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('autoStartMark'))).data, '!');

    await tester.tap(find.byKey(const Key('openAppSettings')));
    expect(health.opened, 1);

    await tester.tap(find.text('করেছি'));
    await tester.pump();
    await tester.pump();
    expect(find.text('1 টি সমস্যা'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('autoStartMark'))).data, '✓');
  });
}
