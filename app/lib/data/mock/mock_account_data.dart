import '../../domain/account_enums.dart';
import '../../domain/enums.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/models/merchant.dart';
import '../../domain/models/shopify_store.dart';
import '../../domain/models/wallet.dart';
import '../../domain/repositories/device_health_repository.dart';
import 'mock_store.dart';

// MOCK - replaced in spec 13: accounts, wallets and stores live on the server.

const demoEmail = 'demo@bdpay.test';

/// One merchant's in-memory data.
class MockMerchantData {
  MockMerchantData({required this.merchant, required this.deviceId, List<Wallet>? wallets, this.store})
      : wallets = wallets ?? [];

  final Merchant merchant;
  final String deviceId;
  List<Wallet> wallets;
  ShopifyStore? store;
}

/// The demo merchant: "নমুনা স্টোর", device BDP-A1, four active wallets, no store.
MockMerchantData buildDemoMerchant() => MockMerchantData(
      merchant: const Merchant(id: 'm_demo', businessName: 'নমুনা স্টোর'),
      deviceId: 'BDP-A1',
      wallets: const [
        Wallet(
          id: 'w_demo_1',
          operator: MfsOperator.bkash,
          walletNumber: '01700000001',
          accountType: AccountType.merchant,
          simSlot: SimSlot.sim1,
          isActive: true,
        ),
        Wallet(
          id: 'w_demo_2',
          operator: MfsOperator.nagad,
          walletNumber: '01700000002',
          accountType: AccountType.merchant,
          simSlot: SimSlot.sim1,
          isActive: true,
        ),
        Wallet(
          id: 'w_demo_3',
          operator: MfsOperator.rocket,
          walletNumber: '017000000031',
          accountType: AccountType.merchant,
          simSlot: SimSlot.sim2,
          isActive: true,
        ),
        Wallet(
          id: 'w_demo_4',
          operator: MfsOperator.upay,
          walletNumber: '01700000004',
          accountType: AccountType.merchant,
          simSlot: SimSlot.sim2,
          isActive: true,
        ),
      ],
    );

/// Shared state behind the mock auth, wallet and Shopify repositories.
/// Data is kept per email for the app's life, so signing out and in shows the same data.
class MockAccountData {
  MockAccountData({required DeviceHealthRepository health, DateTime Function()? clock})
      : clock = clock ?? (() => DateTime.now().toUtc()) {
    // Lives as long as the mock (the app's life).
    health.watch().listen((h) => _online = h.internetOnline);
  }

  /// Starts signed in as the demo merchant (for tests), optionally with a connected store.
  factory MockAccountData.demoSignedIn({
    required DeviceHealthRepository health,
    DateTime Function()? clock,
    bool storeConnected = false,
  }) {
    final data = MockAccountData(health: health, clock: clock);
    final demo = buildDemoMerchant();
    if (storeConnected) {
      demo.store = ShopifyStore(shopDomain: 'demo.myshopify.com', connectedAt: data.clock());
    }
    data.accounts[demoEmail] = demo;
    data.auth.value = AuthState(
      status: AuthStatus.signedIn,
      email: demoEmail,
      merchant: demo.merchant,
      deviceId: demo.deviceId,
    );
    return data;
  }

  final DateTime Function() clock;
  final auth = MockStore<AuthState>(AuthState.signedOut);
  final accounts = <String, MockMerchantData>{};

  /// Bumped on every wallet or store change, so watchers re-read.
  final revision = MockStore<int>(0);

  bool _online = true;
  int _nextId = 1;

  bool get online => _online;

  /// The signed-in merchant's data, or null.
  MockMerchantData? get current {
    final a = auth.value;
    if (a.status != AuthStatus.signedIn || a.email == null) return null;
    return accounts[a.email];
  }

  String newId(String prefix) => '${prefix}_${_nextId++}';

  void changed() => revision.value = revision.value + 1;
}
