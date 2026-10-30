import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../data/account_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_button.dart';
import 'widgets/auth_layout.dart';

/// Spec 13a: the merchant already has 3 active phones. Retry, or log out (this phone was never registered, so
/// there is nothing to deactivate).
class DeviceLimitScreen extends ConsumerWidget {
  const DeviceLimitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return AuthLayout(
      children: [
        Text(
          l.deviceLimitTitle,
          key: const Key('deviceLimitTitle'),
          textAlign: TextAlign.center,
          style: AppText.title16.copyWith(color: AppColors.er),
        ),
        const SizedBox(height: 8),
        Text(l.deviceLimitHint, textAlign: TextAlign.center, style: AppText.sm13),
        const SizedBox(height: 20),
        AppButton.primary(
          key: const Key('deviceLimitRetry'),
          label: l.deviceLimitRetry,
          onPressed: () => ref.read(deviceRegistrationProvider)?.register(),
        ),
        const SizedBox(height: 10),
        AppButton.outline(
          key: const Key('deviceLimitLogout'),
          label: l.logout,
          textColor: AppColors.er,
          onPressed: () async {
            // Stops catching SMS until the next sign-in (plan 13a D171).
            await ref.read(pipelineRepositoryProvider).clearDeviceConfig();
            await ref.read(authRepositoryProvider).signOut();
          },
        ),
      ],
    );
  }
}
