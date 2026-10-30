import 'package:flutter/foundation.dart';

import '../enums.dart';

@immutable
class AppSettings {
  const AppSettings({
    required this.developerMode,
    required this.autoSend,
    required this.enabledOperators,
    required this.deviceName,
  });

  final bool developerMode;
  final bool autoSend;
  final Set<MfsOperator> enabledOperators;
  final String deviceName;

  AppSettings copyWith({
    bool? developerMode,
    bool? autoSend,
    Set<MfsOperator>? enabledOperators,
    String? deviceName,
  }) {
    return AppSettings(
      developerMode: developerMode ?? this.developerMode,
      autoSend: autoSend ?? this.autoSend,
      enabledOperators: enabledOperators ?? this.enabledOperators,
      deviceName: deviceName ?? this.deviceName,
    );
  }
}
