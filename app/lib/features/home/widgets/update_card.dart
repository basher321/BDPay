import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../domain/update/update_rules.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';

/// Spec 15: a newer app version is out (from the heartbeat). Emerald card with a download button that opens the
/// download page in the browser. Hidden otherwise; adds its own gap when shown.
class UpdateCard extends ConsumerWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pipelineStateProvider).value;
    final link = updateLink(
      latest: state?.latestAppVersion,
      downloadUrl: state?.appDownloadUrl,
      running: appVersion,
    );
    if (link == null) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        key: const Key('updateCard'),
        color: AppColors.em.withValues(alpha: 0.10),
        borderColor: AppColors.em.withValues(alpha: 0.7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.updateAvailable(state!.latestAppVersion!), style: AppText.title13.copyWith(color: AppColors.em)),
            const SizedBox(height: 10),
            AppButton.small(
              key: const Key('updateDownload'),
              label: l.updateDownload,
              onPressed: () => ref.read(linkOpenerProvider)(link),
            ),
          ],
        ),
      ),
    );
  }
}
