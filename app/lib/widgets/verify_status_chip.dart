import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/enums.dart';
import '../l10n/app_localizations.dart';

/// The reference .chip: a dot and the status label on a tinted background.
class VerifyStatusChip extends StatelessWidget {
  const VerifyStatusChip(this.status, {super.key});

  final VerifyStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        border: Border.all(color: c.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              status.label(AppLocalizations.of(context)),
              style: AppText.chip.copyWith(color: c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
