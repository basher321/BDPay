import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';

/// Section 7: one tile per operator with its count; disabled operators are faded.
class OperatorStrip extends StatelessWidget {
  const OperatorStrip({super.key, required this.counts, required this.enabled});

  final Map<MfsOperator, int> counts;
  final Set<MfsOperator> enabled;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.operatorsTitle, style: AppText.h3),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final op in MfsOperator.values) ...[
              if (op != MfsOperator.values.first) const SizedBox(width: 8),
              Expanded(
                child: Opacity(
                  key: Key('op-${op.name}'),
                  opacity: enabled.contains(op) ? 1 : 0.5,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.cd,
                      border: Border.all(
                        color: enabled.contains(op) ? op.brandColor.withValues(alpha: 0.4) : AppColors.bd,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Text(
                          op.label(l),
                          style: AppText.badge.copyWith(color: enabled.contains(op) ? op.textColor : AppColors.t3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          enabled.contains(op) ? l.operatorCount(counts[op] ?? 0) : l.operatorOff,
                          style: AppText.sm.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
