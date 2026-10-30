/// Thrown by a repository write when there is no network; nothing was changed. Screens show "ইন্টারনেট নেই".
class OfflineError implements Exception {
  const OfflineError();

  @override
  String toString() => 'OfflineError';
}
