import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_switch.dart';

/// One settings card (the reference "card s big") with a bold title.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      big: true,
      surface: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.title14),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// A title (and optional hint) on the left, an AppSwitch on the right, like the reference.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.switchKey,
    required this.title,
    this.hint,
    this.titleColor,
    this.activeColor,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String? hint;
  final Color? titleColor;
  final Color? activeColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.title13.copyWith(color: titleColor)),
                if (hint != null) Text(hint!, style: AppText.sm),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AppSwitch(key: switchKey, value: value, activeColor: activeColor, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A small grey label above a field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(text, style: AppText.label));
  }
}
