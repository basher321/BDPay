import 'package:flutter_test/flutter_test.dart';
import 'package:verifier/data/device/device_health_repository.dart';
import 'package:verifier/data/device/sms_channel.dart';

import 'fake_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNative native;
  late ChannelDeviceHealthRepository repo;
  final now = DateTime.utc(2026, 10, 29, 6);

  Future<void> start() async {
    repo = ChannelDeviceHealthRepository(SmsChannel(), clock: () => now, listenLifecycle: false)..start();
    await flush();
  }

  setUp(() => native = FakeNative());
  tearDown(() {
    repo.dispose();
    native.dispose();
  });

  test('reads getHealth at start; lastSmsAt = newest row', () async {
    native.health = {...native.health, 'maker': 'xiaomi', 'monitoring': false, 'autoStartConfirmed': true};
    native.rows
      ..add(FakeNative.row(id: 'a', sender: '16216', body: 'x', receivedAtMs: 1000))
      ..add(FakeNative.row(id: 'b', sender: '16216', body: 'y', receivedAtMs: 5000));
    await start();
    final h = repo.current!;
    expect(h.smsPermission, isTrue);
    expect(h.batteryOptimizationOff, isFalse);
    expect(h.internetOnline, isTrue);
    expect(h.monitoring, isFalse);
    expect(h.maker, 'xiaomi');
    expect(h.autoStartConfirmed, isTrue);
    expect(h.lastSmsAt, DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true));
    expect(h.lastServerContactAt, now);
  });

  test('no rows -> lastSmsAt null', () async {
    await start();
    expect(repo.current!.lastSmsAt, isNull);
  });

  test('"offline" / "online" events re-read health', () async {
    await start();
    native.health = {...native.health, 'internetOnline': false};
    native.send('offline');
    await flush();
    expect(repo.current!.internetOnline, isFalse);
    native.health = {...native.health, 'internetOnline': true};
    native.send('online');
    await flush();
    expect(repo.current!.internetOnline, isTrue);
  });

  test('an "inbox" event updates lastSmsAt', () async {
    await start();
    native.rows.add(FakeNative.row(id: 'a', sender: '16216', body: 'x', receivedAtMs: 9000));
    native.send('inbox');
    await flush();
    expect(repo.current!.lastSmsAt, DateTime.fromMillisecondsSinceEpoch(9000, isUtc: true));
  });

  test('fix buttons call the channel and re-read', () async {
    native.health = {...native.health, 'smsPermission': false};
    await start();
    expect(repo.current!.smsPermission, isFalse);
    final reads = native.callsOf('getHealth').length;
    await repo.requestSmsPermission();
    expect(native.callsOf('requestSmsPermission'), hasLength(1));
    expect(native.callsOf('getHealth').length, reads + 1);
    expect(repo.current!.smsPermission, isTrue);
    await repo.requestBatteryExemption();
    expect(native.callsOf('requestBatteryExemption'), hasLength(1));
    expect(native.callsOf('getHealth').length, reads + 2);
  });

  test('setMonitoring and setAutoStartConfirmed are saved natively', () async {
    await start();
    await repo.setMonitoring(false);
    expect(native.callsOf('setMonitoring').single.arguments, false);
    expect(repo.current!.monitoring, isFalse);
    await repo.setAutoStartConfirmed(true);
    expect(native.callsOf('setAutoStartConfirmed').single.arguments, true);
    expect(repo.current!.autoStartConfirmed, isTrue);
    await repo.openAppSettings();
    expect(native.callsOf('openAppSettings'), hasLength(1));
  });

  test('developer "offline" forces offline without touching the network', () async {
    await start();
    await repo.setOnline(false);
    expect(repo.current!.internetOnline, isFalse);
    expect(await repo.pingServer(), isFalse);
    await repo.setOnline(true);
    expect(repo.current!.internetOnline, isTrue);
  });
}
