import '../models/store_connection.dart';

/// Spec 17: the merchant's website connections. Writes throw OfflineError when there is no network
/// (nothing changed) and [ConnectionInputError] for a rejected value.
abstract interface class ConnectionsRepository {
  /// All connections (Shopify and API), oldest first.
  Stream<List<StoreConnection>> watch();

  Future<NewConnectionKeys> create(StorePlatform platform, String siteName, String siteUrl);

  /// null or empty clears the webhook URL.
  Future<StoreConnection> updateWebhook(String id, String? webhookUrl);

  /// The new API key, shown once. The old key stops working at once.
  Future<String> rotateKey(String id);

  Future<StoreConnection> disable(String id);
}

class ConnectionInputError implements Exception {
  const ConnectionInputError(this.kind);

  final CreateConnectionError kind;

  @override
  String toString() => 'ConnectionInputError($kind)';
}
