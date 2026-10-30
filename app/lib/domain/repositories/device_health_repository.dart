import '../models/device_health.dart';

abstract interface class DeviceHealthRepository {
  Stream<DeviceHealth> watch();

  Future<void> setMonitoring(bool on);

  /// Mock only: used by developer mode to simulate losing the internet.
  Future<void> setOnline(bool on);

  /// True when the server answered; also updates lastServerContactAt.
  Future<bool> pingServer();

  Future<void> requestSmsPermission();

  Future<void> requestBatteryExemption();

  /// Opens the app's Android settings page (auto-start row, spec 06).
  Future<void> openAppSettings();

  /// Saves the merchant's "করেছি" on the auto-start row (decision D12).
  Future<void> setAutoStartConfirmed(bool done);
}
