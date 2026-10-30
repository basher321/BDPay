import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';
import 'settings_section.dart';

/// Rule 9: one switch per operator in its brand colour (enabledOperators, saved at once).
class OperatorsSection extends ConsumerWidget {
  const OperatorsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final settings = ref.watch(settingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    return SettingsSection(
      key: const Key('operatorsSection'),
      title: l.smsOperatorsTitle,
      children: [
        for (final op in MfsOperator.values)
          SettingsSwitchRow(
            switchKey: Key('opSwitch-${op.name}'),
            title: op.label(l),
            titleColor: op.textColor,
            activeColor: op.brandColor,
            value: settings.enabledOperators.contains(op),
            onChanged: (on) {
              final next = {...settings.enabledOperators};
              on ? next.add(op) : next.remove(op);
              ref.read(settingsRepositoryProvider).update(settings.copyWith(enabledOperators: next));
            },
          ),
      ],
    );
  }
}
