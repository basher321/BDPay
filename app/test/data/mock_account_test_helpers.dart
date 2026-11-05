import 'package:verifier/data/mock/mock_account_data.dart';
import 'package:verifier/data/mock/mock_auth_repository.dart';
import 'package:verifier/data/mock/mock_device_health_repository.dart';
import 'package:verifier/data/mock/mock_shopify_repository.dart';
import 'package:verifier/data/mock/mock_wallet_repository.dart';

/// The three mock account repositories on one shared state, with a movable clock.
class AccountMocks {
  AccountMocks({bool demoSignedIn = false}) {
    data = demoSignedIn
        ? MockAccountData.demoSignedIn(health: health, clock: () => now)
        : MockAccountData(health: health, clock: () => now);
    auth = MockAuthRepository(data);
    wallets = MockWalletRepository(data);
    store = MockShopifyRepository(data);
  }

  DateTime now = DateTime.utc(2026, 10, 29, 6);
  final health = MockDeviceHealthRepository();
  late final MockAccountData data;
  late final MockAuthRepository auth;
  late final MockWalletRepository wallets;
  late final MockShopifyRepository store;

  /// Lets the health stream deliver, so the mocks see the online state.
  Future<void> setOnline(bool on) async {
    await health.setOnline(on);
    await Future<void>.delayed(Duration.zero);
  }

  /// "demo" logs in with the demo password; any other username opens a new account.
  Future<void> signIn(String username) async {
    if (username == 'demo') {
      await auth.signIn(username, '123456');
    } else {
      await auth.signUp(username, 'secret123');
    }
  }
}
