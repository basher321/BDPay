import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/time.dart';
import '../domain/models/sms_transaction.dart';
import '../l10n/app_localizations.dart';
import 'app_card.dart';
import 'money_text.dart';
import 'operator_badge.dart';
import 'sync_status_label.dart';
import 'verify_status_chip.dart';

/// One transaction row, like the reference card: badge, TrxID, payer, status and time
/// on the left; amount and sync label on the right.
class TransactionCard extends StatelessWidget {
  const TransactionCard({super.key, required this.transaction, this.onTap});

  final SmsTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = transaction;
    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    OperatorBadge(t.operator),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        // Spec 06: a row the phone could not parse.
                        t.parseFailed ? l.unknownFormat : l.trxLabel(t.trxId),
                        style: AppText.title13,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l.payerLine(t.payerNumber ?? l.noValue, t.kind.label(l)),
                  style: AppText.sm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Flexible(child: VerifyStatusChip(t.verifyStatus)),
                    const SizedBox(width: 8),
                    Text(dhakaClock(t.receivedAt), style: AppText.mu10),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(t.amountPoisha),
              const SizedBox(height: 4),
              SyncStatusLabel(t.syncStatus),
            ],
          ),
        ],
      ),
    );
  }
}
