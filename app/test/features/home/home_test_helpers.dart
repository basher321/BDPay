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
import 'package:verifier/domain/models/app_settings.dart';
import 'package:verifier/domain/models/sms_transaction.dart';
import 'package:verifier/domain/repositories/transaction_repository.dart';
import 'package:verifier/features/home/home_screen.dart';
import 'package:verifier/l10n/app_localizations.dart';

import '../../signed_in_overrides.dart';

/// 2026-10-29 12:00 Asia/Dhaka.
final fixedNow = DateTime.utc(2026, 10, 29, 6);

/// Fresh mocks and a controllable clock for one home test.
class HomeHarness {
  HomeHarness({List<SmsTransaction>? items, AppSettings? settings}) {
    final list = items ?? buildSampleTransactions(fixedNow);
    final newest = list.isEmpty ? null : list.map((t) => t.receivedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    health = MockDeviceHealthRepository(startedAt: fixedNow, lastSmsAt: newest, clock: () => now);
    this.settings = MockSettingsRepository(initial: settings);
    transactions = MockTransactionRepository(health, list);
  }

  DateTime now = fixedNow;
  final ticker = StreamController<int>.broadcast();
  late final MockDeviceHealthRepository health;
  late final MockSettingsRepository settings;
  late final MockTransactionRepository transactions;
  late ProviderContainer container;

  /// Moves the clock and emits a tick, like the real 30 s ticker.
  Future<void> advance(WidgetTester tester, Duration d) async {
    now = now.add(d);
    ticker.add(0);
    await tester.pump();
    await tester.pump();
  }
}

/// Pumps HomeScreen alone. [repository] replaces the transaction mock (e.g. a counting fake).
/// [tall] gives the screen enough height that every section is built.
Future<HomeHarness> pumpHome(
  WidgetTester tester, {
  List<SmsTransaction>? items,
  AppSettings? settings,
  TransactionRepository? repository,
  bool tall = true,
}) async {
  if (tall) {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }
  final h = HomeHarness(items: items, settings: settings);
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
        transactionRepositoryProvider.overrideWithValue(repository ?? h.transactions),
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
  h.container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
  return h;
}

/// Pumps a few frames so stream events reach the widgets.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
