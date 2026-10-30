import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time.dart';
import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/sms_transaction.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/money_text.dart';
import '../../../widgets/operator_badge.dart';
import '../../../widgets/sync_status_label.dart';
import '../../transactions/detail/show_transaction_detail.dart';
import '../queue_logic.dart';

/// One item waiting to reach the server, with its warnings and the details / send buttons.
class QueueCard extends ConsumerWidget {
  const QueueCard({super.key, required this.transaction, required this.online});

  final SmsTransaction transaction;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final t = transaction;
    final now = ref.watch(clockProvider);
    final warning = AppText.mu10.copyWith(color: AppColors.er);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OperatorBadge(t.operator),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t.parseFailed ? l.unknownFormat : l.trxLabel(t.trxId), style: AppText.title13, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              MoneyText(t.amountPoisha, style: AppText.amount15),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.queuePayerLine(t.payerNumber ?? l.noValue, timeAgo(t.receivedAt, now, l)),
            style: AppText.sm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (t.retryCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l.retryFailedLine(t.retryCount, t.serverMessage ?? l.noValue),
                key: Key('retryLine-${t.id}'),
                style: warning,
              ),
            ),
          if (isStuck(t))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(l.stuckWarning, key: Key('stuckLine-${t.id}'), style: warning),
            ),
          if (isStale(t, now))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.staleWarning,
                key: Key('staleLine-${t.id}'),
                style: AppText.mu10.copyWith(color: AppColors.wa),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: SyncStatusLabel(t.syncStatus))),
              AppButton.small(
                key: Key('details-${t.id}'),
                label: l.details,
                outlined: true,
                onPressed: () => showTransactionDetail(context, t.id),
              ),
              const SizedBox(width: 8),
              AppButton.small(
                key: Key('send-${t.id}'),
                label: l.sendOne,
                onPressed: (t.syncStatus == SyncStatus.sending || !online)
                    ? null
                    : () => ref.read(transactionRepositoryProvider).retry(t.id),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
