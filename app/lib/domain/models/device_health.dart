import 'package:flutter/foundation.dart';

@immutable
class DeviceHealth {
  const DeviceHealth({
    required this.smsPermission,
    required this.batteryOptimizationOff,
    required this.internetOnline,
    required this.monitoring,
    this.lastSmsAt,
    this.lastServerContactAt,
    this.maker,
    this.autoStartConfirmed = false,
    this.deviceRevoked = false,
  });

  final bool smsPermission;
  final bool batteryOptimizationOff;
  final bool internetOnline;
  final bool monitoring;
  final DateTime? lastSmsAt;
  final DateTime? lastServerContactAt;

  /// Phone maker in lower case (spec 06, rule 7); null when unknown.
  final String? maker;

  /// The merchant ticked "করেছি" on the auto-start row (decision D12).
  final bool autoStartConfirmed;

  /// Spec 13a rule 2: the server revoked this phone; counts as a health problem.
  final bool deviceRevoked;

  DeviceHealth copyWith({
    bool? smsPermission,
    bool? batteryOptimizationOff,
    bool? internetOnline,
    bool? monitoring,
    DateTime? lastSmsAt,
    DateTime? lastServerContactAt,
    String? maker,
    bool? autoStartConfirmed,
    bool? deviceRevoked,
  }) {
    return DeviceHealth(
      smsPermission: smsPermission ?? this.smsPermission,
      batteryOptimizationOff: batteryOptimizationOff ?? this.batteryOptimizationOff,
      internetOnline: internetOnline ?? this.internetOnline,
      monitoring: monitoring ?? this.monitoring,
      lastSmsAt: lastSmsAt ?? this.lastSmsAt,
      lastServerContactAt: lastServerContactAt ?? this.lastServerContactAt,
      maker: maker ?? this.maker,
      autoStartConfirmed: autoStartConfirmed ?? this.autoStartConfirmed,
      deviceRevoked: deviceRevoked ?? this.deviceRevoked,
    );
  }
}
