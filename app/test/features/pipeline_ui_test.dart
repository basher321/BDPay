import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/core/theme/app_theme.dart';
import 'package:verifier/data/account_providers.dart';
import 'package:verifier/data/device/device_providers.dart';
import 'package:verifier/data/device/device_registration.dart';
import 'package:verifier/data/mock/mock_pipeline_repository.dart';
import 'package:verifier/domain/models/pipeline_state.dart';
import 'package:verifier/domain/parser/parser_rule.dart';
import 'package:verifier/features/dev_lab/dev_lab_screen.dart';
import 'package:verifier/l10n/app_localizations.dart';
import 'package:verifier/shell/app_tab.dart';

import 'account_test_helpers.dart';
import 'dev_lab/dev_lab_screen_test.dart' show fakeLab;

/// Spec 13a UI: device-limit screen, rule 2 banner, logout (spec 05 flow + deactivate), rule 4 rules version.
void main() {
  const registered = PipelineState(deviceId: 'dev-1', rulesVersion: 1);

  Future<(AccountHarness, MockPipelineRepository)> pump(
    WidgetTester tester, {
    PipelineState state = registered,
    RegistrationStatus? registration,
  }) async {
    final pipeline = MockPipelineRepository(state);
    final h = await pumpAccountApp(tester, demoSignedIn: true, items: const [], overrides: [
      pipelineRepositoryProvider.overrideWithValue(pipeline),
      if (registration != null)
        registrationStateProvider.overrideWith((ref) => Stream.value(RegistrationState(registration))),
    ]);
    return (h, pipeline);
  }

  Future<void> logout(WidgetTester tester) async {
    await openTab(tester, AppTab.settings);
    await tapVisible(tester, find.byKey(const Key('logoutButton')));
    await tester.tap(find.byKey(const Key('confirmYes')));
    await settle(tester);
  }

  group('logout', () {
    testWidgets('no internet -> blocked with "লগ আউট করতে ইন্টারনেট দরকার"; still signed in', (tester) async {
      final (_, pipeline) = await pump(tester);
      pipeline.deactivateResult = false;
      await logout(tester);
      expect(find.text('লগ আউট করতে ইন্টারনেট দরকার'), findsOneWidget);
      expect(pipeline.deactivateCalls, 1);
      expect(pipeline.clearCalls, 0);
      expect(find.byKey(const Key('usernameField')), findsNothing);
      await clearToast(tester);
    });

    testWidgets('online -> deactivate, then clear the device config, then sign out', (tester) async {
      final (_, pipeline) = await pump(tester);
      await logout(tester);
      expect(pipeline.deactivateCalls, 1);
      expect(pipeline.clearCalls, 1);
      expect(pipeline.state.deviceId, isNull);
      expect(find.byKey(const Key('usernameField')), findsOneWidget);
    });

    testWidgets('not registered -> no deactivate, but the config is still cleared (monitoring stops, D171)',
        (tester) async {
      final (_, pipeline) = await pump(tester, state: const PipelineState(rulesVersion: 1));
      await logout(tester);
      expect(pipeline.deactivateCalls, 0);
      expect(pipeline.clearCalls, 1);
      expect(find.byKey(const Key('usernameField')), findsOneWidget);
    });
  });

  group('rule 2: revoked banner', () {
    testWidgets('revoked -> red banner on হোম; "লগ আউট" skips deactivate', (tester) async {
      final (_, pipeline) = await pump(tester, state: const PipelineState(deviceId: 'dev-1', revoked: true));
      expect(find.byKey(const Key('disconnectedBanner')), findsOneWidget);
      expect(find.text('এই ফোন BDPay থেকে বিচ্ছিন্ন — আবার লগইন করুন'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('disconnectedLogout')));
      expect(pipeline.deactivateCalls, 0);
      expect(pipeline.clearCalls, 1);
      expect(find.byKey(const Key('usernameField')), findsOneWidget);
    });

    testWidgets('not revoked -> no banner', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('disconnectedBanner')), findsNothing);
    });
  });

  group('device limit', () {
    testWidgets('full screen with the spec texts; "লগ আউট" clears the config and signs out', (tester) async {
      final (_, pipeline) = await pump(tester, registration: RegistrationStatus.deviceLimit);
      expect(find.text('এই অ্যাকাউন্টে ৩টি ফোন যুক্ত আছে'), findsOneWidget);
      expect(find.text('অন্য একটি ফোন থেকে লগ আউট করে আবার চেষ্টা করুন'), findsOneWidget);
      expect(find.byKey(const Key('deviceLimitRetry')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('deviceLimitLogout')));
      expect(pipeline.clearCalls, 1);
      expect(find.byKey(const Key('usernameField')), findsOneWidget);
    });
  });

  group('rule 4: developer lab', () {
    testWidgets('shows "নিয়ম সংস্করণ: 2" from the pipeline state', (tester) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rules = parseRules(File('android/app/src/main/res/raw/parser_rules.json').readAsStringSync());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          devLabRepositoryProvider.overrideWithValue(fakeLab(rules)),
          pipelineRepositoryProvider.overrideWithValue(MockPipelineRepository(const PipelineState(rulesVersion: 2))),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          locale: const Locale('bn'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(body: DevLabScreen()),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('নিয়ম সংস্করণ: 2'), findsOneWidget);
    });
  });
}
