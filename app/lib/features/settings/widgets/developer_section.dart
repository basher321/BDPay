import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_section.dart';

/// Rule 10: developer mode, and (only in developer mode) the red "অফলাইন সিমুলেট" switch.
class DeveloperSection extends ConsumerWidget {
  const DeveloperSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value;
    final online = ref.watch(deviceHealthProvider).value?.internetOnline ?? true;
    if (settings == null) return const SizedBox.shrink();
    return SettingsSection(
      key: const Key('developerSection'),
      title: l.developerTitle,
      children: [
        SettingsSwitchRow(
          switchKey: const Key('devModeSwitch'),
          title: l.developerTitle,
          hint: l.developerHint,
          value: settings.developerMode,
          onChanged: (v) => ref.read(settingsRepositoryProvider).update(settings.copyWith(developerMode: v)),
        ),
        if (settings.developerMode)
          SettingsSwitchRow(
            switchKey: const Key('offlineSwitch'),
            title: l.simulateOffline,
            titleColor: AppColors.er,
            activeColor: AppColors.er,
            value: !online,
            // MOCK - only the mock DeviceHealthRepository can change the online state.
            onChanged: (offline) => ref.read(deviceHealthRepositoryProvider).setOnline(!offline),
          ),
      ],
    );
  }
}
