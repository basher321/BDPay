import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_card.dart';

/// ⓘ card explaining that SMS are kept safely; the 2nd sentence depends on autoSend.
class QueueInfoCard extends StatelessWidget {
  const QueueInfoCard({super.key, required this.autoSend});

  final bool autoSend;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = [l.queueInfoSafe, autoSend ? l.queueInfoAuto : l.queueInfoManual, l.queueInfoNoDuplicate].join(' ');
    return AppCard(
      key: const Key('queueInfo'),
      surface: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ⓘ', style: AppText.title14.copyWith(color: AppColors.em)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, key: const Key('queueInfoText'), style: AppText.sm.copyWith(height: 16 / 11))),
        ],
      ),
    );
  }
}
