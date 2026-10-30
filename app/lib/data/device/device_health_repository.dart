import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../domain/models/device_health.dart';
import '../../domain/models/pipeline_state.dart';
import '../../domain/repositories/device_health_repository.dart';
import 'sms_channel.dart';

/// Device health from the native side: read at start, when the app comes to the front, on
/// "online"/"offline" events and after the fix buttons. lastSmsAt = the newest row's time.
class ChannelDeviceHealthRepository implements DeviceHealthRepository {
  ChannelDeviceHealthRepository(
    this._channel, {
    DateTime Function()? clock,
    this._listenLifecycle = true,
    this._serverMode = false,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  /// Spec 13a: the server row and pingServer use the real pipeline (heartbeatNow, lastServerContactMs, revoked).
  final bool _serverMode;
  PipelineState? _pipeline;

  final SmsChannel _channel;
  final DateTime Function() _clock;
  final bool _listenLifecycle;
  final _changes = StreamController<DeviceHealth>.broadcast();
  StreamSubscription<String>? _events;
  AppLifecycleListener? _lifecycle;
  DeviceHealth? _current;
  bool _simulatedOffline = false;
  bool _nativeOnline = true;
  bool _started = false;

  /// The latest state (null until the first read).
  DeviceHealth? get current => _current;

  /// Online, including the developer "offline" switch.
  bool get isOnline => _nativeOnline && !_simulatedOffline;

  void start() {
    if (_started) return;
    _started = true;
    _events = _channel.events.listen((e) {
      if (e == 'online' || e == 'offline') refresh();
      if (e == 'inbox') _refreshLastSms();
      if (e == 'pipeline' && _serverMode) _refreshPipeline();
    });
    if (_listenLifecycle) _lifecycle = AppLifecycleListener(onResume: refresh);
    refresh();
  }

  void dispose() {
    _events?.cancel();
    _lifecycle?.dispose();
  }

  void _emit(DeviceHealth h) {
    _current = h;
    _changes.add(h);
  }

  /// Reads getHealth() and the newest row. Channel errors keep the last state.
  Future<void> refresh() async {
    try {
      final n = await _channel.getHealth();
      final rows = await _channel.listInbox();
      if (_serverMode) _pipeline = PipelineState.fromMap(await _channel.getPipelineState());
      _nativeOnline = n.internetOnline;
      final old = _current;
      _emit(DeviceHealth(
        smsPermission: n.smsPermission,
        batteryOptimizationOff: n.batteryOptimizationOff,
        internetOnline: isOnline,
        monitoring: n.monitoring,
        lastSmsAt: rows.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(rows.first.receivedAtMs, isUtc: true),
        lastServerContactAt: _serverMode
            ? _pipeline?.lastServerContactAt
            : old?.lastServerContactAt ?? (isOnline ? _clock() : null),
        maker: n.maker,
        autoStartConfirmed: n.autoStartConfirmed,
        deviceRevoked: _serverMode && (_pipeline?.revoked ?? false),
      ));
    } on Exception {
      // Keep the last state; nothing is logged.
    }
  }

  Future<void> _refreshPipeline() async {
    try {
      final p = PipelineState.fromMap(await _channel.getPipelineState());
      _pipeline = p;
      final c = _current;
      if (c != null) {
        _emit(DeviceHealth(
          smsPermission: c.smsPermission,
          batteryOptimizationOff: c.batteryOptimizationOff,
          internetOnline: c.internetOnline,
          monitoring: c.monitoring,
          lastSmsAt: c.lastSmsAt,
          lastServerContactAt: p.lastServerContactAt,
          maker: c.maker,
          autoStartConfirmed: c.autoStartConfirmed,
          deviceRevoked: p.revoked,
        ));
      }
    } on Exception {
      // Keep the last state.
    }
  }

  Future<void> _refreshLastSms() async {
    final c = _current;
    if (c == null) return;
    try {
      final rows = await _channel.listInbox();
      if (rows.isEmpty) return;
      _emit(c.copyWith(lastSmsAt: DateTime.fromMillisecondsSinceEpoch(rows.first.receivedAtMs, isUtc: true)));
    } on Exception {
      // Keep the last state.
    }
  }

  @override
  Stream<DeviceHealth> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _changes.stream;
  }

  @override
  Future<void> setMonitoring(bool on) async {
    await _channel.setMonitoring(on);
    final c = _current;
    if (c != null) _emit(c.copyWith(monitoring: on));
  }

  /// Developer "অফলাইন সিমুলেট": forces offline without touching the real network.
  @override
  Future<void> setOnline(bool on) async {
    _simulatedOffline = !on;
    final c = _current;
    if (c != null) _emit(c.copyWith(internetOnline: isOnline));
  }

  /// Spec 13a: a heartbeat now (server mode). Without a server: "reachable" = online (the spec 06 mock).
  @override
  Future<bool> pingServer() async {
    if (_serverMode) {
      try {
        final ok = await _channel.heartbeatNow();
        await _refreshPipeline();
        return ok;
      } on Exception {
        return false;
      }
    }
    final c = _current;
    if (!isOnline) return false;
    if (c != null) _emit(c.copyWith(lastServerContactAt: _clock()));
    return true;
  }

  @override
  Future<void> requestSmsPermission() async {
    await _channel.requestSmsPermission();
    await refresh();
  }

  @override
  Future<void> requestBatteryExemption() async {
    await _channel.requestBatteryExemption();
    await refresh();
  }

  @override
  Future<void> openAppSettings() => _channel.openAppSettings();

  @override
  Future<void> setAutoStartConfirmed(bool done) async {
    await _channel.setAutoStartConfirmed(done);
    final c = _current;
    if (c != null) _emit(c.copyWith(autoStartConfirmed: done));
  }
}
