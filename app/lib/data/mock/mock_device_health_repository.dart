import '../../domain/models/device_health.dart';
import '../../domain/repositories/device_health_repository.dart';
import 'mock_store.dart';

class MockDeviceHealthRepository implements DeviceHealthRepository {
  /// Starting state from spec 02: battery saver not yet excluded, everything else ok.
  /// [startedAt] is app start (the first server contact); [lastSmsAt] is the newest sample.
  MockDeviceHealthRepository({
    DeviceHealth? initial,
    DateTime? startedAt,
    DateTime? lastSmsAt,
    DateTime Function()? clock,
  })  : _clock = clock ?? (() => DateTime.now().toUtc()),
        _store = MockStore(initial ??
            DeviceHealth(
              smsPermission: true,
              batteryOptimizationOff: false,
              internetOnline: true,
              monitoring: true,
              lastSmsAt: lastSmsAt,
              lastServerContactAt: startedAt,
            ));

  final DateTime Function() _clock;
  final MockStore<DeviceHealth> _store;

  /// The current health, for tests.
  DeviceHealth get current => _store.value;

  @override
  Stream<DeviceHealth> watch() => _store.watch();

  @override
  Future<void> setMonitoring(bool on) async {
    _store.value = _store.value.copyWith(monitoring: on);
  }

  @override
  Future<void> setOnline(bool on) async {
    _store.value = _store.value.copyWith(internetOnline: on);
  }

  @override
  Future<bool> pingServer() async {
    if (!_store.value.internetOnline) return false;
    _store.value = _store.value.copyWith(lastServerContactAt: _clock());
    return true;
  }

  @override
  Future<void> requestSmsPermission() async {
    _store.value = _store.value.copyWith(smsPermission: true);
  }

  @override
  Future<void> requestBatteryExemption() async {
    _store.value = _store.value.copyWith(batteryOptimizationOff: true);
  }

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> setAutoStartConfirmed(bool done) async {
    _store.value = _store.value.copyWith(autoStartConfirmed: done);
  }
}
