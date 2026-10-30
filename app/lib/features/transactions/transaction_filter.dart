import '../../domain/enums.dart';
import '../../domain/models/sms_transaction.dart';

/// Search (TrxID or payer number, case-insensitive, trimmed), one operator and a status set.
/// A null operator or null statuses means "all". Keeps the input order.
List<SmsTransaction> filterTransactions(
  List<SmsTransaction> list, {
  String query = '',
  MfsOperator? operator,
  Set<VerifyStatus>? statuses,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final t in list)
      if ((operator == null || t.operator == operator) &&
          (statuses == null || statuses.contains(t.verifyStatus)) &&
          (q.isEmpty || t.trxId.toLowerCase().contains(q) || (t.payerNumber ?? '').contains(q)))
        t,
  ];
}
