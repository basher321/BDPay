import 'package:flutter/foundation.dart';

@immutable
class ShopifyStore {
  const ShopifyStore({required this.shopDomain, this.connectedAt, this.lastError});

  final String shopDomain;

  /// UTC. null when the server does not say (spec 13: shopify-status has no time - plan D133 C).
  final DateTime? connectedAt;

  /// The server's last error code, e.g. "reconnectNeeded" (spec 13).
  final String? lastError;

  static const reconnectNeeded = 'reconnectNeeded';

  bool get needsReconnect => lastError == reconnectNeeded;

  ShopifyStore copyWith({String? shopDomain, DateTime? connectedAt, String? lastError}) {
    return ShopifyStore(
      shopDomain: shopDomain ?? this.shopDomain,
      connectedAt: connectedAt ?? this.connectedAt,
      lastError: lastError ?? this.lastError,
    );
  }
}
