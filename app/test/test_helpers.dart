import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/app.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';
import 'package:verifier/data/mock/mock_transaction_repository.dart';
import 'package:verifier/data/mock/sample_transactions.dart';
import 'package:verifier/data/providers.dart';

import 'signed_in_overrides.dart';

/// Fresh mock repositories for one test.
class TestMocks {
  TestMocks() {
    transactions = MockTransactionRepository(health, buildSampleTransactions(DateTime.now().toUtc()));
  }

  final health = MockDeviceHealthRepository();
  final settings = MockSettingsRepository();
  late final MockTransactionRepository transactions;
}

/// Pumps the whole app with fresh mocks and returns them.
Future<TestMocks> pumpApp(WidgetTester tester) async {
  final mocks = TestMocks();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceHealthRepositoryProvider.overrideWithValue(mocks.health),
        settingsRepositoryProvider.overrideWithValue(mocks.settings),
        transactionRepositoryProvider.overrideWithValue(mocks.transactions),
        ...signedInOverrides(),
      ],
      child: const BdpayApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
  return mocks;
}
