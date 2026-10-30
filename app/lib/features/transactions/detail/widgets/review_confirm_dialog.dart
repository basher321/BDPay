import 'package:flutter/material.dart';

import '../../../../core/money.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/colors.dart';
import '../../../../domain/review.dart';
import '../../../../l10n/app_localizations.dart';

/// Confirms an approve / reject. Returns the note ('' when empty) on "হ্যাঁ, নিশ্চিত", null on "না".
Future<String?> showReviewConfirmDialog(
  BuildContext context, {
  required ReviewDecision decision,
  required int expectedPoisha,
  required int smsPoisha,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (_) => _ReviewConfirmDialog(decision: decision, expectedPoisha: expectedPoisha, smsPoisha: smsPoisha),
  );
}

class _ReviewConfirmDialog extends StatefulWidget {
  const _ReviewConfirmDialog({required this.decision, required this.expectedPoisha, required this.smsPoisha});

  final ReviewDecision decision;
  final int expectedPoisha;
  final int smsPoisha;

  @override
  State<_ReviewConfirmDialog> createState() => _ReviewConfirmDialogState();
}

class _ReviewConfirmDialogState extends State<_ReviewConfirmDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final approve = widget.decision == ReviewDecision.approve;
    Widget amountRow(String label, int poisha) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.sm13)),
            Text(formatPoisha(poisha), style: AppText.title13),
          ]),
        );
    return Dialog(
      backgroundColor: AppColors.sf,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(approve ? l.approve : l.reject, style: AppText.title16),
            const SizedBox(height: 12),
            amountRow(l.reviewExpected, widget.expectedPoisha),
            amountRow(l.reviewSmsAmount, widget.smsPoisha),
            const SizedBox(height: 12),
            TextField(
              key: const Key('noteField'),
              controller: _note,
              maxLength: 200,
              style: AppText.body13,
              decoration: InputDecoration(hintText: l.note),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  key: const Key('confirmNo'),
                  onTap: () => Navigator.of(context).pop(),
                  child: Text(l.no, style: AppText.title14),
                ),
                const SizedBox(width: 20),
                GestureDetector(
                  key: const Key('confirmYes'),
                  onTap: () => Navigator.of(context).pop(_note.text.trim()),
                  child: Text(
                    l.yesConfirm,
                    style: AppText.title14.copyWith(color: approve ? AppColors.em : AppColors.er),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
