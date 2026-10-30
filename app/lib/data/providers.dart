import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/enums.dart';
import '../domain/models/app_settings.dart';
import '../domain/models/device_health.dart';
import '../domain/models/sms_transaction.dart';
import '../domain/repositories/device_health_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/transaction_repository.dart';
import '../shell/app_tab.dart';
import 'account_providers.dart';
import 'device/device_health_repository.dart';
import 'device/device_providers.dart';
import 'device/device_transaction_repository.dart';
import 'mock/mock_settings_repository.dart';
import 'upload/native_sms_uploader.dart';

/// Emits every 30 seconds so "N মিনিট আগে" texts refresh.
final tickerProvider = StreamProvider<int>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (i) => i),
);

/// The current time in UTC, refreshed on every tick. Tests override it.
final clockProvider = Provider<DateTime>((ref) {
  ref.watch(tickerProvider);
  return DateTime.now().toUtc();
});

/// Spec 06: health from the phone (SMS permission, battery, internet, maker) through the native channel.
final deviceHealthRepositoryProvider = Provider<DeviceHealthRepository>((ref) {
  final repo = ChannelDeviceHealthRepository(
    ref.watch(smsChannelProvider),
    clock: () => ref.read(clockProvider),
    serverMode: ref.watch(appConfigProvider).isComplete, // spec 13a
  )..start();
  ref.onDispose(repo.dispose);
  return repo;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => MockSettingsRepository(),
);

/// Spec 06: real SMS from the phone's store. The mock repositories stay for tests only.
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  final functions = ref.watch(functionsGatewayProvider);
  final repo = ChannelTransactionRepository(
    channel: ref.watch(smsChannelProvider),
    rules: ref.watch(parserRulesProvider.future),
    health: ref.watch(deviceHealthRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    // Spec 13a: background upload, claim-review and the 30 s refresh when a server is configured.
    nativeUploader: functions == null ? null : NativeSmsUploader(ref.watch(smsChannelProvider)),
    functions: functions,
    inFront: () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
  );
  unawaited(repo.start());
  ref.onDispose(repo.dispose);
  return repo;
});

final transactionsProvider = StreamProvider<List<SmsTransaction>>(
  (ref) => ref.watch(transactionRepositoryProvider).watchAll(),
);

final deviceHealthProvider = StreamProvider<DeviceHealth>(
  (ref) => ref.watch(deviceHealthRepositoryProvider).watch(),
);

final settingsProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

/// Queued + failed: the number on the পাঠানো বাকি badge.
final pendingCountProvider = Provider<int>((ref) {
  final list = ref.watch(transactionsProvider).value ?? const [];
  return list.where((t) => t.syncStatus.isPending).length;
});

class SelectedTab extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;

  void select(AppTab tab) => state = tab;
}

/// The current bottom tab.
final selectedTabProvider = NotifierProvider<SelectedTab, AppTab>(SelectedTab.new);

class TransactionFilter extends Notifier<Set<VerifyStatus>?> {
  @override
  Set<VerifyStatus>? build() => null;

  void set(Set<VerifyStatus>? statuses) => state = statuses;
}

/// Status filter for the লেনদেন tab; null = all.
final transactionFilterProvider = NotifierProvider<TransactionFilter, Set<VerifyStatus>?>(TransactionFilter.new);
