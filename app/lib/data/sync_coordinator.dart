import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/enums.dart';
import '../domain/models/sms_transaction.dart';
import '../domain/repositories/device_health_repository.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/repositories/transaction_repository.dart';
import 'providers.dart';

/// Sends every queued and failed item when the internet comes back (false -> true) and
/// autoSend is on. Never runs two sends at once: online events during a send are ignored.
/// It holds no UI: [onAutoSent] receives the number of items that became sent (only when > 0).
class SyncCoordinator {
  SyncCoordinator({
    required this._health,
    required this._settings,
    required this._transactions,
    this.onAutoSent,
  });

  final DeviceHealthRepository _health;
  final SettingsRepository _settings;
  final TransactionRepository _transactions;
  void Function(int sent)? onAutoSent;

  final _subs = <StreamSubscription<Object?>>[];
  bool? _wasOnline;
  bool _autoSend = true;
  List<SmsTransaction> _latest = const [];
  bool _running = false;
  bool _disposed = false;

  void start() {
    if (_subs.isNotEmpty || _disposed) return;
    _subs
      ..add(_settings.watch().listen((s) => _autoSend = s.autoSend))
      ..add(_transactions.watchAll().listen((list) => _latest = list))
      ..add(_health.watch().listen((h) {
        final came = _wasOnline == false && h.internetOnline;
        _wasOnline = h.internetOnline;
        if (came && _autoSend) _sendAll();
      }));
  }

  Future<void> _sendAll() async {
    if (_running) return;
    _running = true;
    try {
      final waiting = {for (final t in _latest) if (t.syncStatus.isPending) t.id};
      await _transactions.retryAllPending();
      // Let the list stream deliver the final states before counting.
      await Future<void>.delayed(Duration.zero);
      final sent = _latest.where((t) => waiting.contains(t.id) && t.syncStatus == SyncStatus.sent).length;
      if (sent > 0 && !_disposed) onAutoSent?.call(sent);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    health: ref.watch(deviceHealthRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    transactions: ref.watch(transactionRepositoryProvider),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
