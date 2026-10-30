import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/enums.dart';
import '../l10n/app_localizations.dart';

/// The small sync label from the reference (Synced / Queue / Failed).
class SyncStatusLabel extends StatelessWidget {
  const SyncStatusLabel(this.status, {super.key});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final c = status.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(status.label(AppLocalizations.of(context)), style: AppText.syncLabel.copyWith(color: c)),
    );
  }
}
