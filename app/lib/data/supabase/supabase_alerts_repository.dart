import 'dart:async';

import '../../domain/account_enums.dart';
import '../../domain/models/app_alert.dart';
import '../../domain/models/auth_state.dart';
import '../../domain/repositories/alerts_repository.dart';
import 'app_foreground.dart';
import 'functions_gateway.dart';
import 'gateway_errors.dart';
import 'rows.dart';
import 'timers.dart';
import 'value_stream.dart';

/// Spec 13: open alerts from alerts-list, newest first. Refreshed after sign-in, when the app comes to the front,
/// and every 5 minutes while signed in. Errors keep the last list.
class SupabaseAlertsRepository implements AlertsRepository {
  SupabaseAlertsRepository({
    required this._functions,
    required Stream<AuthState> auth,
    this._timers = const RealTimers(),
    this._foreground,
  }) : _authStream = auth;

  static const refreshEvery = Duration(minutes: 5);

  final FunctionsGateway _functions;
  final Stream<AuthState> _authStream;
  final Timers _timers;
  final AppForeground? _foreground;
  final _alerts = ValueStream<List<AppAlert>>(const []);
  final _subs = <StreamSubscription<void>>[];
  bool _signedIn = false;
  Cancelable? _every;

  void start() {
    _subs.add(_authStream.listen((a) {
      final on = a.status == AuthStatus.signedIn;
      if (on == _signedIn) return;
      _signedIn = on;
      _every?.cancel();
      _every = null;
      if (on) {
        unawaited(refresh());
        _every = _timers.periodic(refreshEvery, () => unawaited(refresh()));
      } else {
        _alerts.value = const [];
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
    _every?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    await _alerts.close();
  }

  @override
  Stream<List<AppAlert>> watch() => _alerts.watch();

  @override
  Future<void> refresh() async {
    if (!_signedIn) return;
    final FunctionsReply r;
    try {
      r = await _functions.call('alerts-list', get: true);
    } on OfflineException {
      return;
    }
    final list = r.ok ? r.map['alerts'] : null;
    if (list is! List) return;
    final alerts = [for (final j in list) ?alertFromJson(j)]..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    _alerts.value = List.unmodifiable(alerts);
  }
}
