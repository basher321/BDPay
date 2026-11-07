import 'dart:async';

import '../../domain/account_enums.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/models/store_connection.dart';
import '../../domain/repositories/connections_repository.dart';
import '../../domain/repositories/repository_errors.dart';
import 'app_foreground.dart';
import 'functions_gateway.dart';
import 'gateway_errors.dart';
import 'value_stream.dart';

/// Spec 17: website connections through the store-connections function. Refreshed after sign-in and when the
/// app comes to the front. The API key and webhook secret are returned to the screen once and never kept here.
class SupabaseConnectionsRepository implements ConnectionsRepository {
  SupabaseConnectionsRepository({required this._functions, required Stream<AuthState> auth, this._foreground})
      : _authStream = auth;

  static const _fn = 'store-connections';

  final FunctionsGateway _functions;
  final Stream<AuthState> _authStream;
  final AppForeground? _foreground;
  final _list = ValueStream<List<StoreConnection>>(const []);
  final _subs = <StreamSubscription<void>>[];
  bool _signedIn = false;

  void start() {
    _subs.add(_authStream.listen((a) {
      final on = a.status == AuthStatus.signedIn;
      if (on == _signedIn) return;
      _signedIn = on;
      if (on) {
        unawaited(refresh());
      } else {
        _list.value = const [];
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
    for (final s in _subs) {
      await s.cancel();
    }
    await _list.close();
  }

  @override
  Stream<List<StoreConnection>> watch() => _list.watch();

  /// Errors keep the last list.
  Future<void> refresh() async {
    if (!_signedIn) return;
    final FunctionsReply r;
    try {
      r = await _functions.call(_fn, get: true);
    } on OfflineException {
      return;
    }
    final list = r.ok ? r.map['connections'] : null;
    if (list is! List) return;
    _list.value = List.unmodifiable([for (final j in list) ?connectionFromJson(j)]);
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final FunctionsReply r;
    try {
      r = await _functions.call(_fn, body: body);
    } on OfflineException {
      throw const OfflineError();
    }
    if (r.ok) return r.map;
    final error = r.map['error'];
    throw switch (error) {
      'invalidName' => const ConnectionInputError(CreateConnectionError.invalidName),
      'invalidUrl' => const ConnectionInputError(CreateConnectionError.invalidUrl),
      'duplicate' => const ConnectionInputError(CreateConnectionError.duplicate),
      // Any other answer (not deployed, server error): nothing was changed; the screen says so.
      _ => const OfflineError(),
    };
  }

  StoreConnection _upsert(Object? json) {
    final c = connectionFromJson(json);
    if (c == null) throw const OfflineError();
    final i = _list.value.indexWhere((x) => x.id == c.id);
    _list.value = List.unmodifiable(i < 0 ? [..._list.value, c] : ([..._list.value]..[i] = c));
    return c;
  }

  @override
  Future<NewConnectionKeys> create(StorePlatform platform, String siteName, String siteUrl) async {
    final m = await _post({'action': 'create', 'platform': platform.toWire(), 'siteName': siteName, 'siteUrl': siteUrl});
    final key = m['apiKey'];
    final secret = m['webhookSecret'];
    if (key is! String || secret is! String) throw const OfflineError();
    return NewConnectionKeys(connection: _upsert(m['connection']), apiKey: key, webhookSecret: secret);
  }

  @override
  Future<StoreConnection> updateWebhook(String id, String? webhookUrl) async {
    final url = webhookUrl?.trim() ?? '';
    final m = await _post({'action': 'updateWebhook', 'id': id, 'webhookUrl': url.isEmpty ? null : url});
    return _upsert(m['connection']);
  }

  @override
  Future<String> rotateKey(String id) async {
    final m = await _post({'action': 'rotateKey', 'id': id});
    final key = m['apiKey'];
    if (key is! String) throw const OfflineError();
    _upsert(m['connection']);
    return key;
  }

  @override
  Future<StoreConnection> disable(String id) async {
    final m = await _post({'action': 'disable', 'id': id});
    return _upsert(m['connection']);
  }
}

/// One connection from the server's JSON; null when a field is missing or unknown (never throws).
StoreConnection? connectionFromJson(Object? json) {
  if (json is! Map) return null;
  try {
    final id = json['id'];
    final name = json['siteName'];
    final at = DateTime.tryParse('${json['connectedAt']}');
    if (id is! String || name is! String || at == null) return null;
    String? text(String k) => json[k] is String ? json[k] as String : null;
    return StoreConnection(
      id: id,
      platform: StorePlatform.fromWire('${json['platform']}'),
      siteName: name,
      siteUrl: text('siteUrl'),
      webhookUrl: text('webhookUrl'),
      apiKeyPrefix: text('apiKeyPrefix'),
      status: ConnectionStatus.fromWire('${json['status']}'),
      lastError: text('lastError'),
      connectedAt: at.toUtc(),
    );
  } on FormatException {
    return null;
  }
}
