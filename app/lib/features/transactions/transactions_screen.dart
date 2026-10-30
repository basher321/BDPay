import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/transaction_card.dart';
import 'detail/show_transaction_detail.dart';
import 'transactions_providers.dart';
import 'widgets/operator_chips.dart';
import 'widgets/review_banner.dart';
import 'widgets/search_box.dart';
import 'widgets/status_chips.dart';

/// The লেনদেন tab: search, operator and status chips, review banner, count and a lazy list.
class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(filteredTransactionsProvider);
    final mismatches = ref.watch(mismatchCountProvider);
    return CustomScrollView(
      key: const Key('transactionsList'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SearchBox(),
                const SizedBox(height: 10),
                const OperatorChips(),
                const SizedBox(height: 10),
                const StatusChips(),
                if (mismatches > 0) ...[
                  const SizedBox(height: 10),
                  ReviewBanner(count: mismatches),
                ],
                const SizedBox(height: 10),
                Text(
                  l.resultCount(list.length),
                  key: const Key('resultCount'),
                  style: AppText.sm.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(icon: '🔍', title: l.noResultsTitle, hint: l.noResultsHint),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverList.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => TransactionCard(
                transaction: list[i],
                onTap: () => showTransactionDetail(context, list[i].id),
              ),
            ),
          ),
      ],
    );
  }
}
