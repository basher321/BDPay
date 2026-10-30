import '../../core/time.dart';
import '../../domain/enums.dart';
import '../../domain/models/device_health.dart';
import '../../domain/models/sms_transaction.dart';

/// Everything the হোম screen counts, computed from the transaction list.
class HomeSummary {
  const HomeSummary({
    required this.todayVerifiedPoisha,
    required this.verified,
    required this.pending,
    required this.mismatchOrRejected,
    required this.sendable,
    required this.perOperator,
  });

  /// Sum of verified amounts whose receivedAt is today in Asia/Dhaka.
  final int todayVerifiedPoisha;
  final int verified;
  final int pending;
  final int mismatchOrRejected;

  /// Queued + failed: what the "send pending" button sends.
  final int sendable;
  final Map<MfsOperator, int> perOperator;
}

bool isSameDhakaDay(DateTime a, DateTime b) {
  final x = toDhakaWall(a);
  final y = toDhakaWall(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

HomeSummary summarize(List<SmsTransaction> all, DateTime now) {
  var today = 0;
  var verified = 0;
  var pending = 0;
  var bad = 0;
  var sendable = 0;
  final perOperator = {for (final op in MfsOperator.values) op: 0};
  for (final t in all) {
    perOperator[t.operator] = perOperator[t.operator]! + 1;
    if (t.syncStatus.isPending) sendable++;
    switch (t.verifyStatus) {
      case VerifyStatus.verified:
        verified++;
        if (isSameDhakaDay(t.receivedAt, now)) today += t.amountPoisha;
      case VerifyStatus.pending:
        pending++;
      case VerifyStatus.mismatch:
      case VerifyStatus.rejected:
        bad++;
    }
  }
  return HomeSummary(
    todayVerifiedPoisha: today,
    verified: verified,
    pending: pending,
    mismatchOrRejected: bad,
    sendable: sendable,
    perOperator: perOperator,
  );
}

/// Phone makers that stop background apps (spec 06, rule 7).
const backgroundBlockingMakers = {
  'xiaomi', 'redmi', 'poco', 'oppo', 'realme', 'vivo', 'infinix', 'tecno', 'huawei', 'honor', //
};

/// The auto-start row is shown only for [backgroundBlockingMakers].
bool showsAutoStartRow(String? maker) => backgroundBlockingMakers.contains(maker?.trim().toLowerCase());

/// Number of health rows a-d that are not ok, plus the auto-start row until the merchant ticks "করেছি".
int healthProblemCount(DeviceHealth h) => [
      h.smsPermission,
      h.batteryOptimizationOff,
      h.internetOnline,
      h.monitoring,
      if (showsAutoStartRow(h.maker)) h.autoStartConfirmed,
      // Spec 13a rule 2: a phone the server revoked is a problem.
      !h.deviceRevoked,
    ].where((ok) => !ok).length;

/// Spec 13a rule 3 (plan D155): the server counts as reachable when the internet is up and the server answered in
/// the last 10 minutes (spec 09's deviceOnline window). Heartbeats every 5 minutes keep it green. Before the first
/// contact (not known yet) the internet state decides.
const serverContactWindow = Duration(minutes: 10);

bool serverReachable(DeviceHealth h, DateTime now) {
  final contact = h.lastServerContactAt;
  if (!h.internetOnline) return false;
  return contact == null || now.difference(contact) <= serverContactWindow;
}
