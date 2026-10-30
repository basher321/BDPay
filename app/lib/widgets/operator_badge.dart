import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/enums.dart';
import '../l10n/app_localizations.dart';

/// The reference .pb badge: operator name on a tinted brand background.
class OperatorBadge extends StatelessWidget {
  const OperatorBadge(this.operator, {super.key});

  final MfsOperator operator;

  @override
  Widget build(BuildContext context) {
    final brand = operator.brandColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.15),
        border: Border.all(color: brand.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        operator.label(AppLocalizations.of(context)),
        style: AppText.badge.copyWith(color: operator.textColor),
      ),
    );
  }
}
