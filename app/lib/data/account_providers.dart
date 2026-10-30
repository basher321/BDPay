import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_config.dart';
import '../domain/models/app_alert.dart';
import '../domain/models/auth_state.dart';
import '../domain/models/pipeline_state.dart';
import '../domain/models/shopify_store.dart';
import '../domain/models/wallet.dart';
import '../domain/repositories/alerts_repository.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/pipeline_repository.dart';
import '../domain/repositories/store_repository.dart';
import '../domain/repositories/wallet_repository.dart';
import 'device/channel_pipeline_repository.dart';
import 'device/device_providers.dart';
import 'device/device_registration.dart';
import 'mock/mock_account_data.dart';
import 'mock/mock_alerts_repository.dart';
import 'mock/mock_pipeline_repository.dart';
import 'mock/mock_auth_repository.dart';
import 'mock/mock_shopify_repository.dart';
import 'mock/mock_wallet_repository.dart';
import 'providers.dart';
import 'supabase/app_foreground.dart';
import 'supabase/functions_gateway.dart';
import 'supabase/supabase_setup.dart';
import 'supabase/url_opener.dart';

/// Spec 13: the dart-define configuration. Without it (tests, or a build without --dart-define) the mock
/// repositories are used; main.dart shows the "not configured" screen in a real run.
final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromDefines);

/// Spec 15: opens a web page (download page, privacy, terms) in the phone's browser. Screens use this instead of
/// lib/data/supabase/ directly; tests override it. The link is never logged.
final linkOpenerProvider = Provider<Future<bool> Function(Uri url)>((ref) => const UrlLauncherOpener().open);

bool _real(Ref ref) => ref.watch(appConfigProvider).isComplete;

final appForegroundProvider = Provider<AppForeground>((ref) {
  final f = LifecycleForeground();
  ref.onDispose(f.dispose);
  return f;
});

/// Shared state of the three mock repositories. Tests override it (e.g. with demoSignedIn).
final mockAccountDataProvider = Provider<MockAccountData>(
  (ref) => MockAccountData(
    health: ref.watch(deviceHealthRepositoryProvider),
    clock: () => ref.read(clockProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!_real(ref)) return MockAuthRepository(ref.watch(mockAccountDataProvider));
  final repo = buildAuthRepository();
  unawaited(repo.start());
  ref.onDispose(repo.dispose);
  return repo;
});

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  if (!_real(ref)) return MockWalletRepository(ref.watch(mockAccountDataProvider));
  final repo = buildWalletRepository(ref.watch(authRepositoryProvider).watch(), ref.watch(appForegroundProvider))
    ..start();
  ref.onDispose(repo.dispose);
  return repo;
});

final storeRepositoryProvider = Provider<StoreRepository>((ref) {
  if (!_real(ref)) return MockShopifyRepository(ref.watch(mockAccountDataProvider));
  final repo = buildStoreRepository(ref.watch(authRepositoryProvider).watch(), ref.watch(appForegroundProvider))
    ..start();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Spec 13: open alerts (alerts-list). The mock has none unless a test sets them.
final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  if (!_real(ref)) return MockAlertsRepository();
  final repo = buildAlertsRepository(ref.watch(authRepositoryProvider).watch(), ref.watch(appForegroundProvider))
    ..start();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Edge Functions with the user token; null when no server is configured (tests).
final functionsGatewayProvider = Provider<FunctionsGateway?>(
  (ref) => _real(ref) ? buildFunctionsGateway() : null,
);

/// Spec 13a: the phone pipeline (native) when a server is configured; the mock otherwise.
final pipelineRepositoryProvider = Provider<PipelineRepository>((ref) {
  if (!_real(ref)) return MockPipelineRepository();
  final repo = ChannelPipelineRepository(ref.watch(smsChannelProvider))..start();
  ref.onDispose(repo.dispose);
  return repo;
});

final pipelineStateProvider = StreamProvider<PipelineState>(
  (ref) => ref.watch(pipelineRepositoryProvider).watch(),
);

/// Spec 13a: registers this phone while signed in. Without a server it reports the mock auth deviceId.
final deviceRegistrationProvider = Provider<DeviceRegistration?>((ref) {
  if (!_real(ref)) return null;
  final reg = DeviceRegistration(
    native: ref.watch(smsChannelProvider),
    functions: ref.watch(functionsGatewayProvider)!,
    auth: ref.watch(authRepositoryProvider).watch(),
    settings: ref.watch(settingsRepositoryProvider).watch(),
    functionsUrl: ref.watch(appConfigProvider).functionsUrl,
  )..start();
  ref.onDispose(reg.dispose);
  return reg;
});

final registrationStateProvider = StreamProvider<RegistrationState>((ref) {
  final reg = ref.watch(deviceRegistrationProvider);
  if (reg != null) return reg.watch();
  return ref.watch(authRepositoryProvider).watch().map(
        (a) => a.deviceId == null
            ? RegistrationState.idle
            : RegistrationState(RegistrationStatus.registered, deviceId: a.deviceId),
      );
});

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(authRepositoryProvider).watch(),
);

final walletsProvider = StreamProvider<List<Wallet>>(
  (ref) => ref.watch(walletRepositoryProvider).watch(),
);

final shopifyStoreProvider = StreamProvider<ShopifyStore?>(
  (ref) => ref.watch(storeRepositoryProvider).watch(),
);

final alertsProvider = StreamProvider<List<AppAlert>>(
  (ref) => ref.watch(alertsRepositoryProvider).watch(),
);
