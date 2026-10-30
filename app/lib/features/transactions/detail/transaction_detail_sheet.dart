import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/money_text.dart';
import '../../../widgets/operator_badge.dart';
import '../../../widgets/verify_status_chip.dart';
import 'detail_format.dart';
import 'widgets/detail_row.dart';
import 'widgets/raw_sms_box.dart';
import 'widgets/review_card.dart';
import 'widgets/server_reply_card.dart';

/// Full detail of one transaction. Watches the list, so it updates live while open.
class TransactionDetailSheet extends ConsumerWidget {
  const TransactionDetailSheet({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(transactionsProvider).value ?? const [];
    final matches = list.where((t) => t.id == id);
    if (matches.isEmpty) return const SizedBox.shrink();
    final t = matches.first;
    void close() => Navigator.of(context).pop();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OperatorBadge(t.operator),
                const Spacer(),
                GestureDetector(
                  key: const Key('detailClose'),
                  onTap: close,
                  child: Text('✕', style: AppText.title16.copyWith(color: AppColors.t2)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MoneyText(t.amountPoisha, style: AppText.amount28),
            const SizedBox(height: 6),
            VerifyStatusChip(t.verifyStatus),
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(color: AppColors.bd, height: 1)),
            DetailRow(label: l.detailTrxId, value: t.trxId, copyValue: t.trxId, copyKey: const Key('copyTrxId')),
            DetailRow(
              label: l.detailPayer,
              value: t.payerNumber ?? l.noValue,
              copyValue: t.payerNumber,
              copyKey: const Key('copyPayer'),
            ),
            DetailRow(label: l.detailKind, value: t.kind.label(l)),
            if (t.reference != null) DetailRow(label: l.detailReference, value: t.reference!),
            if (t.balancePoisha != null) DetailRow(label: l.detailBalance, value: formatPoisha(t.balancePoisha!)),
            DetailRow(label: l.detailTime, value: dhakaDateTime(t.receivedAt)),
            const SizedBox(height: 12),
            if (t.verifyStatus == VerifyStatus.mismatch) ...[
              ReviewCard(transaction: t),
              const SizedBox(height: 12),
            ],
            ServerReplyCard(transaction: t),
            const SizedBox(height: 14),
            RawSmsBox(body: t.rawBody),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: AppButton.outline(key: const Key('closeButton'), label: l.close, onPressed: close)),
                if (t.syncStatus.isPending) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton.primary(
                      key: const Key('sendNowButton'),
                      label: l.sendNow,
                      onPressed: () {
                        ref.read(transactionRepositoryProvider).retry(t.id);
                        close();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
