import '../../domain/enums.dart';
import '../../domain/models/sms_transaction.dart';

/// Everything not yet on the server (queued, sending or failed), oldest first:
/// the order they will be sent.
List<SmsTransaction> queueItems(List<SmsTransaction> all) =>
    all.where((t) => t.syncStatus != SyncStatus.sent).toList()..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

/// More than 24 hours old: the customer's order may already be cancelled.
bool isStale(SmsTransaction t, DateTime now) => now.difference(t.receivedAt) > const Duration(hours: 24);

/// Failed 5 times or more.
bool isStuck(SmsTransaction t) => t.retryCount >= 5;
