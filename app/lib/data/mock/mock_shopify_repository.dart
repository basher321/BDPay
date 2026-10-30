import '../../core/validators.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/shopify_store.dart';
import '../../domain/repositories/store_repository.dart';
import 'mock_account_data.dart';

/// MOCK - kept for tests; the app uses SupabaseStoreRepository when a server is configured (spec 13).
class MockShopifyRepository implements StoreRepository {
  MockShopifyRepository(this._data);

  static const connectDelay = Duration(seconds: 1);

  final MockAccountData _data;

  @override
  Stream<ShopifyStore?> watch() => _data.revision.watch().map((_) => _data.current?.store);

  @override
  Future<ConnectResult> connectShopify(String shopDomain) async {
    final domain = normalizeShopDomain(shopDomain);
    if (!isValidShopDomain(domain)) return ConnectResult.invalidDomain;
    await Future<void>.delayed(connectDelay);
    if (!_data.online) return ConnectResult.offline;
    final account = _data.current;
    if (account == null) throw StateError('Not signed in');
    account.store = ShopifyStore(shopDomain: domain, connectedAt: _data.clock());
    _data.changed();
    return ConnectResult.done;
  }

  @override
  Future<bool> testConnection() async => _data.online;
}
