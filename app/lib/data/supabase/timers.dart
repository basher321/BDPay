import 'dart:async';

/// A clock and repeating timers, injected so the 3 s / 60 s / 5 min rules are tested without waiting.
abstract interface class Timers {
  DateTime now();

  /// Calls [tick] every [every] until the returned handle is cancelled.
  Cancelable periodic(Duration every, void Function() tick);
}

abstract interface class Cancelable {
  void cancel();
}

class RealTimers implements Timers {
  const RealTimers();

  @override
  DateTime now() => DateTime.now().toUtc();

  @override
  Cancelable periodic(Duration every, void Function() tick) => _TimerHandle(Timer.periodic(every, (_) => tick()));
}

class _TimerHandle implements Cancelable {
  _TimerHandle(this._t);

  final Timer _t;

  @override
  void cancel() => _t.cancel();
}
