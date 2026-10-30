import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../domain/enums.dart';
import '../../domain/models/sms_transaction.dart';
import 'transaction_filter.dart';

// These live outside the screen, so search and operator stay set when switching tabs.

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(SearchQuery.new);

class OperatorFilter extends Notifier<MfsOperator?> {
  @override
  MfsOperator? build() => null;

  /// Selects [operator]; tapping the selected one again (or null) returns to "all".
  void toggle(MfsOperator? operator) => state = (operator == null || operator == state) ? null : operator;
}

final operatorFilterProvider = NotifierProvider<OperatorFilter, MfsOperator?>(OperatorFilter.new);

/// The লেনদেন list after search, operator and status filters; newest first.
final filteredTransactionsProvider = Provider<List<SmsTransaction>>((ref) {
  return filterTransactions(
    ref.watch(transactionsProvider).value ?? const [],
    query: ref.watch(searchQueryProvider),
    operator: ref.watch(operatorFilterProvider),
    statuses: ref.watch(transactionFilterProvider),
  );
});

final mismatchCountProvider = Provider<int>((ref) {
  final all = ref.watch(transactionsProvider).value ?? const [];
  return all.where((t) => t.verifyStatus == VerifyStatus.mismatch).length;
});
