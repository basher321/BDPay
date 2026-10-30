import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/validators.dart';
import '../../../data/account_providers.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import 'settings_section.dart';

/// Rule 8: device name (saved with the big button), read-only device ID, and autoSend (saved at once).
class DeviceSection extends ConsumerStatefulWidget {
  const DeviceSection({super.key});

  @override
  ConsumerState<DeviceSection> createState() => _DeviceSectionState();
}

class _DeviceSectionState extends ConsumerState<DeviceSection> {
  final _name = TextEditingController();
  bool _filled = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repo = ref.read(settingsRepositoryProvider);
    final s = ref.read(settingsProvider).value;
    if (s == null) return;
    await repo.update(s.copyWith(deviceName: _name.text.trim()));
    if (mounted) showToast(context, AppLocalizations.of(context).settingsSaved);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value;
    // Spec 13a: the server's device id (a UUID, shortened to 8 characters); the mock id without a server.
    final registered = ref.watch(registrationStateProvider).value?.deviceId;
    final deviceId = registered == null ? '—' : (registered.length > 12 ? registered.substring(0, 8) : registered);
    if (settings == null) return const SizedBox.shrink();
    if (!_filled) {
      _name.text = settings.deviceName;
      _filled = true;
    }
    return SettingsSection(
      key: const Key('deviceSection'),
      title: l.deviceSectionTitle,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldLabel(l.deviceNameLabel),
                  TextField(
                    key: const Key('deviceNameField'),
                    controller: _name,
                    maxLength: 30,
                    style: AppText.body13,
                    decoration: const InputDecoration(counterText: ''),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FieldLabel(l.deviceIdLabel),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cd,
                      border: Border.all(color: AppColors.bd),
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                    child: Text(deviceId, key: const Key('deviceIdText'), style: AppText.body13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SettingsSwitchRow(
          switchKey: const Key('autoSendSwitch'),
          title: l.autoSendTitle,
          hint: l.autoSendHint,
          value: settings.autoSend,
          onChanged: (v) => ref.read(settingsRepositoryProvider).update(settings.copyWith(autoSend: v)),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: AppButton.primary(
            key: const Key('saveSettingsButton'),
            label: l.saveSettings,
            onPressed: isValidDeviceName(_name.text) ? _save : null,
          ),
        ),
      ],
    );
  }
}
