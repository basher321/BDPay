import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/money_text.dart';

/// Section 3: today's verified total, with the reference's emerald-to-surface gradient.
class TodayTotalCard extends StatelessWidget {
  const TodayTotalCard({super.key, required this.totalPoisha});

  final int totalPoisha;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      key: const Key('todayTotalCard'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppColors.em.withValues(alpha: 0.08), AppColors.sf], stops: const [0, 0.9]),
        border: Border.all(color: AppColors.bd),
        borderRadius: BorderRadius.circular(AppRadius.bigCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.todayTotalLabel, style: AppText.sm13.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          MoneyText(totalPoisha, style: AppText.amount32),
          const SizedBox(height: 4),
          Text(l.todayTotalCaption, style: AppText.mu10.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}
