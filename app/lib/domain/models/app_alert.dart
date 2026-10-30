import 'package:flutter/foundation.dart';

/// One open alert from the server (spec 11 alerts-list). title and hint are the server's Bangla texts.
@immutable
class AppAlert {
  const AppAlert({required this.id, required this.kind, required this.openedAt, required this.title, required this.hint});

  final String id;

  /// Wire name: phoneSilent, monitoringOff, noActiveDevice, shopifyReconnect, reviewWaiting or syncFailed.
  final String kind;

  /// UTC.
  final DateTime openedAt;
  final String title;
  final String hint;
}
