import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/device/device_registration.dart';
import 'package:verifier/data/device/sms_channel.dart';
import 'package:verifier/domain/account_enums.dart';
import 'package:verifier/domain/models/auth_state.dart';
import 'package:verifier/domain/models/merchant.dart';
import 'package:verifier/data/mock/mock_settings_repository.dart';

import '../supabase/fakes.dart';

/// The native side as DeviceRegistration sees it.
class FakeDeviceNative implements DeviceNative {
  final _events = StreamController<String>.broadcast();
  final configs = <(String, String, String?)>[];
  final merchants = <String>[];
  int uploads = 0;

  @override
  Stream<String> get events => _events.stream;

  void send(String e) => _events.add(e);

  @override
  Future<String> getInstallId() async => 'install-1';

  @override
  Future<String> getDevicePublicKey() async => 'PUBLIC-SPKI';

  @override
  Future<NativeHealth> getHealth() async => const NativeHealth(
        smsPermission: true,
        batteryOptimizationOff: true,
        internetOnline: true,
        maker: 'google',
        monitoring: true,
        enabledOperators: {},
        autoStartConfirmed: false,
        androidVersion: '14',
      );

  @override
  Future<void> setDeviceConfig({
    required String deviceId,
    required String functionsUrl,
    required String merchantId,
    String? serverTime,
  }) async {
    configs.add((deviceId, functionsUrl, serverTime));
    merchants.add(merchantId);
  }

  @override
  Future<void> uploadNow() async => uploads++;

  @override
  Future<void> clearDeviceConfig() async {}

  @override
  Future<void> refreshNow() async {}

  @override
  Future<bool> heartbeatNow() async => true;

  @override
  Future<bool> deactivateDevice() async => true;

  @override
  Future<Map<String, Object?>> getPipelineState() async => const {};
}

const _signedIn = AuthState(
  status: AuthStatus.signedIn,
  email: 'a@b.co',
  merchant: Merchant(id: 'm-1', businessName: 'দোকান'),
);

final _ok = reply(200, {
  'ok': true,
  'deviceId': 'dev-uuid-1',
  'merchantId': 'm-1',
  'serverTime': '2026-10-30T06:00:00.000Z',
  'rulesVersion': 1,
});

void main() {
  late FakeDeviceNative native;
  late FakeFunctionsGateway fn;
  late StreamController<AuthState> auth;
  late MockSettingsRepository settings;
  late DeviceRegistration reg;

  setUp(() {
    native = FakeDeviceNative();
    fn = FakeFunctionsGateway();
    auth = StreamController<AuthState>.broadcast();
    settings = MockSettingsRepository();
    reg = DeviceRegistration(
      native: native,
      functions: fn,
      auth: auth.stream,
      settings: settings.watch(),
      functionsUrl: 'http://10.0.2.2:54321/functions/v1',
    )..start();
  });

  Future<void> signIn() async {
    auth.add(_signedIn);
    await pumpEventQueue();
  }

  test('success: device-register with installId, key, name and versions; deviceId + serverTime saved; upload starts', () async {
    fn.answer('device-register', _ok);
    await signIn();
    final body = fn.calls.single.$3!;
    expect(body['installId'], 'install-1');
    expect(body['publicKeySpki'], 'PUBLIC-SPKI');
    expect(body['deviceName'], 'POS Terminal 01');
    expect(body['androidVersion'], '14');
    expect(native.configs.single, ('dev-uuid-1', 'http://10.0.2.2:54321/functions/v1', '2026-10-30T06:00:00.000Z'));
    expect(native.merchants.single, 'm-1'); // plan 13a D171
    expect(reg.state.status, RegistrationStatus.registered);
    expect(reg.state.deviceId, 'dev-uuid-1');
    expect(native.uploads, 1, reason: 'SMS queued while unregistered or revoked go out now');
  });

  test('runs again when the device name changes (same installId)', () async {
    fn.answer('device-register', _ok);
    await signIn();
    final s = await settings.watch().first;
    await settings.update(s.copyWith(deviceName: 'কাউন্টার ২'));
    await pumpEventQueue();
    expect(fn.count('device-register'), 2);
    expect(fn.calls.last.$3!['deviceName'], 'কাউন্টার ২');
    expect(fn.calls.last.$3!['installId'], 'install-1');
  });

  test('runs on every app start while signed in (a new instance registers again)', () async {
    fn.answer('device-register', _ok);
    await signIn();
    final again = DeviceRegistration(
      native: native,
      functions: fn,
      auth: Stream.value(_signedIn),
      settings: settings.watch(),
      functionsUrl: 'u',
    )..start();
    await pumpEventQueue();
    expect(fn.count('device-register'), 2);
    expect(again.state.status, RegistrationStatus.registered);
  });

  test('409 -> deviceLimit; retry works once a phone was logged out elsewhere', () async {
    fn.answer('device-register', reply(409, {'ok': false, 'error': 'deviceLimit'}));
    fn.answer('device-register', _ok);
    await signIn();
    expect(reg.state.status, RegistrationStatus.deviceLimit);
    expect(native.configs, isEmpty);
    await reg.register();
    expect(reg.state.status, RegistrationStatus.registered);
  });

  test('offline -> offline; the internet returns -> registered', () async {
    fn.answer('device-register', offline);
    fn.answer('device-register', _ok);
    await signIn();
    expect(reg.state.status, RegistrationStatus.offline);
    native.send('online');
    await pumpEventQueue();
    expect(reg.state.status, RegistrationStatus.registered);
  });

  test('a long name is cut to 30 characters', () async {
    fn.answer('device-register', _ok);
    final s = await settings.watch().first;
    await settings.update(s.copyWith(deviceName: 'ক' * 40));
    await signIn();
    expect((fn.calls.last.$3!['deviceName'] as String).runes.length, 30);
  });

  test('sign-out -> idle; nothing registers while signed out', () async {
    fn.answer('device-register', _ok);
    await signIn();
    auth.add(AuthState.signedOut);
    await pumpEventQueue();
    expect(reg.state.status, RegistrationStatus.idle);
    native.send('online');
    await pumpEventQueue();
    expect(fn.count('device-register'), 1);
  });
}
