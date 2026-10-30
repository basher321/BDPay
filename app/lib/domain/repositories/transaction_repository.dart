import '../models/sms_transaction.dart';
import '../review.dart';

abstract interface class TransactionRepository {
  /// All transactions, newest first.
  Stream<List<SmsTransaction>> watchAll();

  Future<void> retry(String id);

  /// Retries every queued or failed transaction.
  Future<void> retryAllPending();

  /// Manual decision on a mismatch payment. [note] is optional (max 200 characters).
  Future<ReviewResult> review(String id, ReviewDecision decision, String? note);
}
