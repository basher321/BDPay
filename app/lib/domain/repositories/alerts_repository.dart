import '../models/app_alert.dart';

/// Spec 13: the merchant's open alerts, newest first.
abstract interface class AlertsRepository {
  Stream<List<AppAlert>> watch();

  Future<void> refresh();
}
