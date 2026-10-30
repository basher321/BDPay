import '../../domain/enums.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import 'mock_store.dart';

class MockSettingsRepository implements SettingsRepository {
  MockSettingsRepository({AppSettings? initial})
      : _store = MockStore(initial ??
            AppSettings(
              developerMode: false,
              autoSend: true,
              enabledOperators: MfsOperator.values.toSet(),
              deviceName: 'POS Terminal 01',
            ));

  final MockStore<AppSettings> _store;

  /// The current settings, for tests.
  AppSettings get current => _store.value;

  @override
  Stream<AppSettings> watch() => _store.watch();

  @override
  Future<void> update(AppSettings settings) async {
    _store.value = settings;
  }
}
