import '../account_enums.dart';
import '../models/shopify_store.dart';

abstract interface class StoreRepository {
  /// null when no store is connected.
  Stream<ShopifyStore?> watch();

  Future<ConnectResult> connectShopify(String shopDomain);

  Future<bool> testConnection();

  // Spec 13 rule 5: no disconnect - the merchant uninstalls the app in Shopify admin.
}
