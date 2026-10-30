import '../models/app_settings.dart';

abstract interface class SettingsRepository {
  Stream<AppSettings> watch();

  Future<void> update(AppSettings settings);
}
