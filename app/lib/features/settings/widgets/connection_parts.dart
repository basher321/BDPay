import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../domain/models/store_connection.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import 'settings_section.dart';

/// Spec 17 shared parts of the connection screens.

/// The platform's shown name ("অন্য প্ল্যাটফর্ম" for other).
String platformName(StorePlatform p, AppLocalizations l) => p == StorePlatform.other ? l.platformOther : p.displayName;

/// The reference chip style: a dot and a label; active = green, disabled / uninstalled = red.
class ConnectionStatusChip extends StatelessWidget {
  const ConnectionStatusChip(this.status, {super.key});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (label, c) = switch (status) {
      ConnectionStatus.active => (l.connStatusActive, AppColors.ok),
      ConnectionStatus.disabled => (l.connStatusDisabled, AppColors.er),
      ConnectionStatus.uninstalled => (l.connStatusUninstalled, AppColors.er),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        border: Border.all(color: c.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: AppText.chip.copyWith(color: c)),
        ],
      ),
    );
  }
}

/// A secret shown once (rule 2): label, the value as plain selectable text, and a copy button.
class SecretBox extends StatelessWidget {
  const SecretBox({super.key, required this.label, required this.value, required this.copyKey});

  final String label;
  final String value;
  final Key copyKey;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(label),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.rawSmsBg,
              border: Border.all(color: AppColors.bd),
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: SelectableText(value, style: AppText.body12),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.small(
              key: copyKey,
              label: l.copyButton,
              outlined: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) showToast(context, l.copiedToast);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The setup guide for one platform: the API address and four common steps plus one platform line.
class ConnectionGuide extends ConsumerWidget {
  const ConnectionGuide({super.key, required this.platform});

  final StorePlatform platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    final name = platformName(platform, l);
    final String platformLine = platform.isBrowserFramework
        ? l.guideBrowserPlatform(name)
        : platform.isSiteBuilder
            ? l.guideBuilderPlatform(name)
            : l.guideServerPlatform(name);
    final List<String> steps = [l.guideApiStep1, l.guideApiStep2, l.guideApiStep3, l.guideApiStep4, platformLine];
    return Column(
      key: const Key('connectionGuide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.shopifyGuideTitle, style: AppText.title13),
        const SizedBox(height: 8),
        if (config.isComplete) ...[
          FieldLabel(l.apiAddressLabel),
          SelectableText('${config.functionsUrl}/merchant-api/checkouts', style: AppText.body12),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 22, child: Text('${i + 1}.', style: AppText.sm.copyWith(color: AppColors.em))),
                Expanded(child: Text(steps[i], style: AppText.sm)),
              ],
            ),
          ),
      ],
    );
  }
}

/// Opens a bottom sheet in the wallet sheet style.
Future<T?> showSettingsSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bigCard)),
    ),
    builder: builder,
  );
}
