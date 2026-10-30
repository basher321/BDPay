import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/app_info.dart';
import '../../domain/account_enums.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/auth_state.dart';
import '../supabase/functions_gateway.dart';
import '../supabase/gateway_errors.dart';
import '../supabase/value_stream.dart';
import 'sms_channel.dart';

enum RegistrationStatus { idle, registering, registered, deviceLimit, offline, failed }

@immutable
class RegistrationState {
  const RegistrationState(this.status, {this.deviceId});

  static const idle = RegistrationState(RegistrationStatus.idle);

  final RegistrationStatus status;
  final String? deviceId;
}

/// Spec 13a: registers this phone with device-register while signed in - on start, after sign-in, when the device
/// name changes, and when the internet comes back after an offline try. The public key comes from the Keystore
/// through the channel; the private key never does. Never logs.
class DeviceRegistration {
  DeviceRegistration({
    required this._native,
    required this._functions,
    required Stream<AuthState> auth,
    required Stream<AppSettings> settings,
    required this._functionsUrl,
    this._appVersion = appVersion,
  })  : _authStream = auth,
        _settingsStream = settings;

  static const maxNameLength = 30;

  final DeviceNative _native;
  final FunctionsGateway _functions;
  final Stream<AuthState> _authStream;
  final Stream<AppSettings> _settingsStream;
  final String _functionsUrl;
  final String _appVersion;
  final _state = ValueStream<RegistrationState>(RegistrationState.idle);
  final _subs = <StreamSubscription<Object?>>[];
  bool _signedIn = false;
  String _deviceName = '';
  Future<void>? _running;

  Stream<RegistrationState> watch() => _state.watch();

  RegistrationState get state => _state.value;

  void start() {
    _subs
      ..add(_authStream.listen((a) {
        final on = a.status == AuthStatus.signedIn;
        if (on == _signedIn) return;
        _signedIn = on;
        if (on) {
          unawaited(register());
        } else {
          _state.value = RegistrationState.idle;
        }
      }))
      ..add(_settingsStream.listen((s) {
        final name = s.deviceName.trim();
        if (name == _deviceName) return;
        final first = _deviceName.isEmpty;
        _deviceName = name;
        if (!first && _signedIn) unawaited(register()); // same installId -> same deviceId on the server
      }))
      ..add(_native.events.listen((e) {
        final s = _state.value.status;
        if (e == 'online' && _signedIn && (s == RegistrationStatus.offline || s == RegistrationStatus.failed)) {
          unawaited(register());
        }
      }));
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _state.close();
  }

  /// One registration at a time; a second call while one runs waits for it.
  Future<void> register() => _running ??= _register().whenComplete(() => _running = null);

  Future<void> _register() async {
    if (!_signedIn) return;
    _state.value = RegistrationState(RegistrationStatus.registering, deviceId: _state.value.deviceId);
    final FunctionsReply r;
    try {
      final installId = await _native.getInstallId();
      final key = await _native.getDevicePublicKey();
      final health = await _native.getHealth();
      r = await _functions.call('device-register', body: {
        'installId': installId,
        'deviceName': _name(),
        'publicKeySpki': key,
        'appVersion': _appVersion,
        'androidVersion': health.androidVersion.isEmpty ? '?' : health.androidVersion,
      });
    } on OfflineException {
      _state.value = const RegistrationState(RegistrationStatus.offline);
      return;
    } on Exception {
      _state.value = const RegistrationState(RegistrationStatus.failed);
      return;
    }
    final deviceId = r.map['deviceId'];
    final merchantId = r.map['merchantId'];
    if (r.ok && deviceId is String && merchantId is String) {
      await _native.setDeviceConfig(
        deviceId: deviceId,
        functionsUrl: _functionsUrl,
        merchantId: merchantId,
        serverTime: r.map['serverTime'] as String?,
      );
      _state.value = RegistrationState(RegistrationStatus.registered, deviceId: deviceId);
      // SMS kept as queued while the phone was revoked or unregistered go out now.
      unawaited(_native.uploadNow().catchError((_) {}));
      return;
    }
    _state.value = RegistrationState(
      r.status == 409 ? RegistrationStatus.deviceLimit : RegistrationStatus.failed,
    );
  }

  /// 1-30 characters (spec 08); the settings default when empty.
  String _name() {
    final chars = _deviceName.isEmpty ? 'BDPay phone'.runes.toList() : _deviceName.runes.toList();
    return String.fromCharCodes(chars.take(maxNameLength));
  }
}
