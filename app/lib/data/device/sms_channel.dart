import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/account_enums.dart';
import '../../domain/enums.dart';
import '../../domain/keep_result.dart';
import 'inbox_row.dart';

/// What getHealth() returns.
@immutable
class NativeHealth {
  const NativeHealth({
    required this.smsPermission,
    required this.batteryOptimizationOff,
    required this.internetOnline,
    required this.maker,
    required this.monitoring,
    required this.enabledOperators,
    required this.autoStartConfirmed,
    this.androidVersion = '',
  });

  final bool smsPermission;
  final bool batteryOptimizationOff;
  final bool internetOnline;
  final String maker;
  final bool monitoring;
  final Set<MfsOperator> enabledOperators;
  final bool autoStartConfirmed;

  /// Build.VERSION.RELEASE, e.g. "14" (spec 13a registration).
  final String androidVersion;
}

/// What the phone pipeline needs from the native side (spec 13a). SmsChannel implements it; tests fake it.
abstract interface class DeviceNative {
  Stream<String> get events;

  Future<String> getInstallId();

  /// base64 SPKI of the Keystore key. The private key never crosses the channel.
  Future<String> getDevicePublicKey();

  /// merchantId: plan 13a D171 (rows of another merchant are held, not uploaded).
  Future<void> setDeviceConfig({
    required String deviceId,
    required String functionsUrl,
    required String merchantId,
    String? serverTime,
  });

  Future<void> clearDeviceConfig();

  Future<void> uploadNow();

  Future<void> refreshNow();

  Future<bool> heartbeatNow();

  Future<bool> deactivateDevice();

  Future<Map<String, Object?>> getPipelineState();

  Future<NativeHealth> getHealth();
}

/// The only Dart code that knows the channel names (spec 06 contract). Never logs.
class SmsChannel implements DeviceNative {
  SmsChannel({MethodChannel? methods, EventChannel? events})
      : _methods = methods ?? const MethodChannel(methodName),
        _events = events ?? const EventChannel(eventName);

  static const methodName = 'bdpay/sms';
  static const eventName = 'bdpay/sms/events';

  final MethodChannel _methods;
  final EventChannel _events;

  /// "inbox", "online", "offline", "pipeline" or "rules". One native subscription shared by all listeners.
  @override
  late final Stream<String> events =
      _events.receiveBroadcastStream().map((e) => e as String).asBroadcastStream();

  Future<String> getParserRules() async => (await _methods.invokeMethod<String>('getParserRules'))!;

  Future<List<InboxRow>> listInbox() async {
    final list = await _methods.invokeListMethod<Object?>('listInbox') ?? const [];
    return [for (final m in list) InboxRow.fromMap(m! as Map<Object?, Object?>)];
  }

  Future<void> updateSync({
    required String id,
    required SyncStatus syncStatus,
    required VerifyStatus verifyStatus,
    required int retryCount,
    int? serverCode,
    String? serverMessage,
  }) =>
      _methods.invokeMethod<void>('updateSync', {
        'id': id,
        'syncStatus': syncStatus.toWire(),
        'verifyStatus': verifyStatus.toWire(),
        'retryCount': retryCount,
        'serverCode': serverCode,
        'serverMessage': serverMessage,
      });

  Future<KeepResult> simulateIncoming(String sender, String body, SimSlot simSlot) async {
    final wire = await _methods.invokeMethod<String>('simulateIncoming', {
      'sender': sender,
      'body': body,
      'simSlot': simSlot.toWire(),
    });
    return KeepResult.fromWire(wire!);
  }

  Future<void> setMonitoring(bool on) => _methods.invokeMethod<void>('setMonitoring', on);

  Future<void> setEnabledOperators(Set<MfsOperator> ops) =>
      _methods.invokeMethod<void>('setEnabledOperators', [for (final o in ops) o.toWire()]);

  Future<void> setAutoStartConfirmed(bool done) => _methods.invokeMethod<void>('setAutoStartConfirmed', done);

  @override
  Future<NativeHealth> getHealth() async {
    final m = (await _methods.invokeMapMethod<String, Object?>('getHealth'))!;
    return NativeHealth(
      smsPermission: m['smsPermission'] == true,
      batteryOptimizationOff: m['batteryOptimizationOff'] == true,
      internetOnline: m['internetOnline'] == true,
      maker: (m['maker'] as String?) ?? '',
      monitoring: m['monitoring'] != false,
      enabledOperators: {
        for (final o in (m['enabledOperators'] as List?) ?? const [])
          for (final op in MfsOperator.values)
            if (op.toWire() == o) op,
      },
      autoStartConfirmed: m['autoStartConfirmed'] == true,
      androidVersion: (m['androidVersion'] as String?) ?? '',
    );
  }

  Future<bool> requestSmsPermission() async => await _methods.invokeMethod<bool>('requestSmsPermission') ?? false;

  Future<void> requestBatteryExemption() => _methods.invokeMethod<void>('requestBatteryExemption');

  Future<void> openAppSettings() => _methods.invokeMethod<void>('openAppSettings');

  // Spec 13a additions.

  @override
  Future<String> getInstallId() async => (await _methods.invokeMethod<String>('getInstallId'))!;

  @override
  Future<String> getDevicePublicKey() async => (await _methods.invokeMethod<String>('getDevicePublicKey'))!;

  @override
  Future<void> setDeviceConfig({
    required String deviceId,
    required String functionsUrl,
    required String merchantId,
    String? serverTime,
  }) =>
      _methods.invokeMethod<void>('setDeviceConfig', {
        'deviceId': deviceId,
        'functionsUrl': functionsUrl,
        'merchantId': merchantId,
        'serverTime': serverTime,
      });

  @override
  Future<void> clearDeviceConfig() => _methods.invokeMethod<void>('clearDeviceConfig');

  @override
  Future<void> uploadNow() => _methods.invokeMethod<void>('uploadNow');

  @override
  Future<void> refreshNow() => _methods.invokeMethod<void>('refreshNow');

  @override
  Future<bool> heartbeatNow() async => await _methods.invokeMethod<bool>('heartbeatNow') ?? false;

  @override
  Future<bool> deactivateDevice() async => await _methods.invokeMethod<bool>('deactivateDevice') ?? false;

  @override
  Future<Map<String, Object?>> getPipelineState() async =>
      await _methods.invokeMapMethod<String, Object?>('getPipelineState') ?? const {};

  Future<void> setAutoSend(bool on) => _methods.invokeMethod<void>('setAutoSend', on);
}
