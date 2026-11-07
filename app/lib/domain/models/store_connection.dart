import 'package:flutter/foundation.dart';

/// Spec 17 fixed platform list (same wire values as the server and the stores.platform CHECK).
/// [displayName] is the brand name, shown as is in every language.
enum StorePlatform {
  shopify('Shopify'),
  wordpress('WordPress / WooCommerce'),
  webflow('Webflow'),
  framer('Framer'),
  wix('Wix Studio'),
  squarespace('Squarespace'),
  bubble('Bubble'),
  drupal('Drupal'),
  joomla('Joomla'),
  hubspot('HubSpot CMS'),
  duda('Duda'),
  react('React.js'),
  nextjs('Next.js'),
  vue('Vue.js'),
  laravel('Laravel'),
  nodejs('Node.js'),
  django('Django'),
  ghost('Ghost'),
  magento('Magento'),
  prestashop('PrestaShop'),
  webstudio('Webstudio'),
  astro('Astro'),
  sveltekit('SvelteKit'),
  nuxt('Nuxt.js'),
  other('');

  const StorePlatform(this.displayName);

  /// Empty only for [other], whose name comes from the ARB file.
  final String displayName;

  String toWire() => name;

  static StorePlatform fromWire(String wire) {
    for (final p in values) {
      if (p.name == wire) return p;
    }
    throw FormatException('Unknown StorePlatform: "$wire"');
  }

  /// Site builders call the API from their backend or automation feature; the rest from their own server code.
  bool get isSiteBuilder => const {webflow, framer, wix, squarespace, bubble, hubspot, duda, webstudio}.contains(this);

  /// Browser-only frameworks: the guide warns that the key must stay on a server.
  bool get isBrowserFramework => this == react || this == vue;
}

enum ConnectionStatus {
  active,
  disabled,
  uninstalled;

  static ConnectionStatus fromWire(String wire) {
    for (final s in values) {
      if (s.name == wire) return s;
    }
    throw FormatException('Unknown ConnectionStatus: "$wire"');
  }
}

/// Spec 17: one connected website. Never holds the API key or any secret.
@immutable
class StoreConnection {
  const StoreConnection({
    required this.id,
    required this.platform,
    required this.siteName,
    required this.status,
    required this.connectedAt,
    this.siteUrl,
    this.webhookUrl,
    this.apiKeyPrefix,
    this.lastError,
  });

  final String id;
  final StorePlatform platform;
  final String siteName;
  final String? siteUrl;
  final String? webhookUrl;

  /// The first 12 characters of the API key, e.g. "bdp_live_3f9".
  final String? apiKeyPrefix;
  final ConnectionStatus status;
  final String? lastError;

  /// UTC.
  final DateTime connectedAt;

  bool get isApi => platform != StorePlatform.shopify;

  StoreConnection copyWith({String? webhookUrl, bool clearWebhook = false, String? apiKeyPrefix, ConnectionStatus? status}) {
    return StoreConnection(
      id: id,
      platform: platform,
      siteName: siteName,
      siteUrl: siteUrl,
      webhookUrl: clearWebhook ? null : webhookUrl ?? this.webhookUrl,
      apiKeyPrefix: apiKeyPrefix ?? this.apiKeyPrefix,
      status: status ?? this.status,
      lastError: lastError,
      connectedAt: connectedAt,
    );
  }
}

enum CreateConnectionError { invalidName, invalidUrl, duplicate }

/// What create returns: the connection plus the key and webhook secret, shown once (spec 17 rule 2).
@immutable
class NewConnectionKeys {
  const NewConnectionKeys({required this.connection, required this.apiKey, required this.webhookSecret});

  final StoreConnection connection;
  final String apiKey;
  final String webhookSecret;
}
