import 'dart:async';

import 'package:flutter/widgets.dart';

/// "The app came to the front" - the repositories refresh on it (spec 13).
abstract interface class AppForeground {
  Stream<void> get resumed;
}

class LifecycleForeground implements AppForeground {
  LifecycleForeground() {
    _listener = AppLifecycleListener(onResume: () => _resumed.add(null));
  }

  late final AppLifecycleListener _listener;
  final _resumed = StreamController<void>.broadcast();

  @override
  Stream<void> get resumed => _resumed.stream;

  void dispose() {
    _listener.dispose();
    _resumed.close();
  }
}
