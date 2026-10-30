import 'dart:async';

import '../../core/validators.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/models/shopify_store.dart';
import '../../domain/repositories/store_repository.dart';
import 'app_foreground.dart';
import 'functions_gateway.dart';
import 'gateway_errors.dart';
import 'timers.dart';
import 'url_opener.dart';
import 'value_stream.dart';

/// Spec 13: the Shopify state from shopify-status; connecting opens shopify-connect-link's URL in the browser and
/// then polls every 3 s for up to 60 s. No disconnect (rule 5).
class SupabaseStoreRepository implements StoreRepository {
  SupabaseStoreRepository({
    required this._functions,
    required this._opener,
    required Stream<AuthState> auth,
    this._timers = const RealTimers(),
    this._foreground,
  }) : _authStream = auth;

  static const pollEvery = Duration(seconds: 3);
  static const pollFor = Duration(seconds: 60);

  final FunctionsGateway _functions;
  final UrlOpener _opener;
  final Stream<AuthState> _authStream;
  final Timers _timers;
  final AppForeground? _foreground;
  final _store = ValueStream<ShopifyStore?>(null);
  final _subs = <StreamSubscription<void>>[];
  bool _signedIn = false;
  Cancelable? _poll;
  DateTime? _pollStart;

  /// True while the after-connect polling runs.
  bool get polling => _poll != null;

  void start() {
    _subs.add(_authStream.listen((a) {
      final on = a.status == AuthStatus.signedIn;
      if (on == _signedIn) return;
      _signedIn = on;
      if (on) {
        unawaited(refresh());
      } else {
        _stopPolling();
        _store.value = null;
      }
    }));
    final fg = _foreground;
    if (fg != null) {
      _subs.add(fg.resumed.listen((_) {
        if (_signedIn) unawaited(refresh());
      }));
    }
  }

  Future<void> dispose() async {
    _stopPolling();
    for (final s in _subs) {
      await s.cancel();
    }
    await _store.close();
  }

  @override
  Stream<ShopifyStore?> watch() => _store.watch();

  /// Asks shopify-status; returns whether the store is connected. Errors keep the last known state.
  Future<bool> refresh() async {
    final FunctionsReply r;
    try {
      r = await _functions.call('shopify-status', get: true);
    } on OfflineException {
      return false;
    }
    if (!r.ok) return false;
    final m = r.map;
    final domain = m['shopDomain'];
    final connected = m['connected'] == true;
    final lastError = m['lastError'] is String ? m['lastError'] as String : null;
    final showStore = domain is String && (connected || lastError == ShopifyStore.reconnectNeeded);
    _store.value = showStore ? ShopifyStore(shopDomain: domain, lastError: connected ? null : lastError) : null;
    if (connected) _stopPolling();
    return connected;
  }

  @override
  Future<ConnectResult> connectShopify(String shopDomain) async {
    final domain = normalizeShopDomain(shopDomain);
    if (!isValidShopDomain(domain)) return ConnectResult.invalidDomain;
    final FunctionsReply r;
    try {
      r = await _functions.call('shopify-connect-link', body: {'shopDomain': domain});
    } on OfflineException {
      return ConnectResult.offline;
    }
    if (r.status == 400) return ConnectResult.invalidDomain;
    if (r.status == 409) return ConnectResult.shopTaken;
    final url = r.ok ? Uri.tryParse(r.map['url'] is String ? r.map['url'] as String : '') : null;
    if (url == null || url.scheme != 'https') return ConnectResult.offline;
    if (!await _opener.open(url)) return ConnectResult.offline;
    _startPolling();
    return ConnectResult.done;
  }

  @override
  Future<bool> testConnection() => refresh();

  void _startPolling() {
    _stopPolling();
    _pollStart = _timers.now();
    _poll = _timers.periodic(pollEvery, () {
      final start = _pollStart;
      if (start == null || _timers.now().difference(start) > pollFor) {
        _stopPolling();
      } else {
        unawaited(refresh());
      }
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
    _pollStart = null;
  }
}
