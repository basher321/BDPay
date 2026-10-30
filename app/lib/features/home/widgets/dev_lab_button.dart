import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/app_tab.dart';
import '../../../widgets/app_button.dart';

/// Section 6: shown only in developer mode; opens the পরীক্ষা tab.
class DevLabButton extends ConsumerWidget {
  const DevLabButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppButton.outline(
      key: const Key('devLabButton'),
      label: AppLocalizations.of(context).devLabButton,
      onPressed: () => ref.read(selectedTabProvider.notifier).select(AppTab.devLab),
    );
  }
}
