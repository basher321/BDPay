import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../domain/models/sms_transaction.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/app_tab.dart';
import '../../../widgets/transaction_card.dart';
import '../../transactions/detail/show_transaction_detail.dart';

/// Section 8: the newest 5 transactions and "সব দেখুন (N)".
class LatestTransactions extends ConsumerWidget {
  const LatestTransactions({super.key, required this.all});

  final List<SmsTransaction> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l.latestTitle, style: AppText.h3)),
            GestureDetector(
              key: const Key('seeAll'),
              onTap: () {
                ref.read(transactionFilterProvider.notifier).set(null);
                ref.read(selectedTabProvider.notifier).select(AppTab.transactions);
              },
              child: Text(
                l.seeAll(all.length),
                style: AppText.body12.copyWith(color: AppColors.em, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text(l.latestEmpty, style: AppText.sm)),
          )
        else
          for (final t in all.take(5)) ...[
            TransactionCard(transaction: t, onTap: () => showTransactionDetail(context, t.id)),
            const SizedBox(height: 14),
          ],
      ],
    );
  }
}
