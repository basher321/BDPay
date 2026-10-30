import '../../domain/models/app_alert.dart';
import '../../domain/repositories/alerts_repository.dart';
import 'mock_store.dart';

/// MOCK - used by tests and when no server is configured. No alerts unless a test sets them.
class MockAlertsRepository implements AlertsRepository {
  MockAlertsRepository([List<AppAlert> alerts = const []]) : _alerts = MockStore(alerts);

  final MockStore<List<AppAlert>> _alerts;

  int refreshes = 0;

  set alerts(List<AppAlert> next) => _alerts.value = next;

  @override
  Stream<List<AppAlert>> watch() => _alerts.watch();

  @override
  Future<void> refresh() async => refreshes++;
}
