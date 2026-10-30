import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/colors.dart';
import '../../../../data/providers.dart';
import '../../../../domain/models/sms_transaction.dart';
import '../../../../domain/review.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../widgets/app_button.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/toast.dart';
import '../detail_format.dart';
import 'review_confirm_dialog.dart';

/// Amber "রিভিউ দরকার" card for a mismatch payment: order, both amounts, difference and
/// approve / reject. Buttons are disabled while a review runs; a decision cannot be undone.
class ReviewCard extends ConsumerStatefulWidget {
  const ReviewCard({super.key, required this.transaction});

  final SmsTransaction transaction;

  @override
  ConsumerState<ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<ReviewCard> {
  bool _running = false;

  Future<void> _decide(ReviewDecision decision) async {
    final t = widget.transaction;
    final claim = t.claim!;
    final l = AppLocalizations.of(context);
    final note = await showReviewConfirmDialog(
      context,
      decision: decision,
      expectedPoisha: claim.expectedAmountPoisha,
      smsPoisha: t.amountPoisha,
    );
    if (note == null || !mounted) return;
    setState(() => _running = true);
    final result = await ref.read(transactionRepositoryProvider).review(t.id, decision, note.isEmpty ? null : note);
    if (!mounted) return;
    showToast(context, switch (result) {
      ReviewResult.done => decision == ReviewDecision.approve ? l.approvedToast : l.rejectedToast,
      ReviewResult.offline => l.reviewOffline,
      ReviewResult.notAllowed => l.reviewNotAllowed,
    });
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = widget.transaction;
    final claim = t.claim;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.sm)),
            Text(value, style: AppText.body13),
          ]),
        );
    return AppCard(
      key: const Key('reviewCard'),
      color: AppColors.wa.withValues(alpha: 0.12),
      borderColor: AppColors.wa.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.reviewNeeded, style: AppText.title13.copyWith(color: AppColors.wa)),
          const SizedBox(height: 6),
          if (claim == null)
            Text(l.reviewNoOrder, style: AppText.sm)
          else ...[
            Text(l.reviewOrder(claim.orderRef), style: AppText.body13),
            const SizedBox(height: 4),
            row(l.reviewExpected, formatPoisha(claim.expectedAmountPoisha)),
            row(l.reviewSmsAmount, formatPoisha(t.amountPoisha)),
            row(l.reviewDifference, amountDifference(claim.expectedAmountPoisha, t.amountPoisha, l)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: AppButton.primary(
                    key: const Key('approveButton'),
                    label: l.approve,
                    onPressed: _running ? null : () => _decide(ReviewDecision.approve),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton.outline(
                    key: const Key('rejectButton'),
                    label: l.reject,
                    textColor: AppColors.er,
                    onPressed: _running ? null : () => _decide(ReviewDecision.reject),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
