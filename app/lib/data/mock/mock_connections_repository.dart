import 'dart:math';

import '../../core/validators.dart';
import '../../domain/models/store_connection.dart';
import '../../domain/repositories/connections_repository.dart';
import '../../domain/repositories/repository_errors.dart';
import '../supabase/value_stream.dart';
import 'mock_account_data.dart';

/// MOCK - tests and the demo build (spec 17). Keys are random fake values that only work here.
class MockConnectionsRepository implements ConnectionsRepository {
  MockConnectionsRepository(this._data);

  final MockAccountData _data;
  final _list = ValueStream<List<StoreConnection>>(const []);
  final _random = Random.secure();
  int _next = 1;

  @override
  Stream<List<StoreConnection>> watch() => _list.watch();

  String _token(String prefix) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    return prefix + List.generate(43, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  void _check() {
    if (!_data.online) throw const OfflineError();
  }

  @override
  Future<NewConnectionKeys> create(StorePlatform platform, String siteName, String siteUrl) async {
    _check();
    if (!isValidSiteName(siteName)) throw const ConnectionInputError(CreateConnectionError.invalidName);
    final url = normalizeHttpsUrl(siteUrl);
    if (url == null) throw const ConnectionInputError(CreateConnectionError.invalidUrl);
    final taken = _list.value.any(
      (c) => c.platform == platform && c.siteUrl == url && c.status == ConnectionStatus.active,
    );
    if (taken) throw const ConnectionInputError(CreateConnectionError.duplicate);
    final apiKey = _token('bdp_live_');
    final c = StoreConnection(
      id: 'conn-${_next++}',
      platform: platform,
      siteName: siteName.trim(),
      siteUrl: url,
      apiKeyPrefix: apiKey.substring(0, 12),
      status: ConnectionStatus.active,
      connectedAt: _data.clock(),
    );
    _list.value = List.unmodifiable([..._list.value, c]);
    return NewConnectionKeys(connection: c, apiKey: apiKey, webhookSecret: _token('whsec_'));
  }

  StoreConnection _replace(String id, StoreConnection Function(StoreConnection) change) {
    final i = _list.value.indexWhere((c) => c.id == id);
    if (i < 0) throw StateError('Unknown connection');
    final updated = change(_list.value[i]);
    _list.value = List.unmodifiable([..._list.value]..[i] = updated);
    return updated;
  }

  @override
  Future<StoreConnection> updateWebhook(String id, String? webhookUrl) async {
    _check();
    final raw = webhookUrl?.trim() ?? '';
    if (raw.isEmpty) return _replace(id, (c) => c.copyWith(clearWebhook: true));
    final url = normalizeHttpsUrl(raw);
    if (url == null) throw const ConnectionInputError(CreateConnectionError.invalidUrl);
    return _replace(id, (c) => c.copyWith(webhookUrl: url));
  }

  @override
  Future<String> rotateKey(String id) async {
    _check();
    final apiKey = _token('bdp_live_');
    _replace(id, (c) => c.copyWith(apiKeyPrefix: apiKey.substring(0, 12)));
    return apiKey;
  }

  @override
  Future<StoreConnection> disable(String id) async {
    _check();
    return _replace(id, (c) => c.copyWith(status: ConnectionStatus.disabled));
  }
}
