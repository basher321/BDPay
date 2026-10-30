import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';

/// Spec 13a rule 2: the server revoked this phone. "লগ আউট" skips device-deactivate (the server already revoked
/// it). New SMS are still caught and kept as queued. Hidden otherwise; adds its own gap when shown.
class DisconnectedBanner extends ConsumerWidget {
  const DisconnectedBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revoked = ref.watch(pipelineStateProvider).value?.revoked ?? false;
    if (!revoked) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        key: const Key('disconnectedBanner'),
        color: AppColors.er.withValues(alpha: 0.10),
        borderColor: AppColors.er.withValues(alpha: 0.7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.deviceDisconnected, style: AppText.title13.copyWith(color: AppColors.er)),
            const SizedBox(height: 10),
            AppButton.small(
              key: const Key('disconnectedLogout'),
              label: l.logout,
              outlined: true,
              textColor: AppColors.er,
              onPressed: () async {
                await ref.read(pipelineRepositoryProvider).clearDeviceConfig();
                await ref.read(authRepositoryProvider).signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
