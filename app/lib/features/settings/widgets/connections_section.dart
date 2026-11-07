import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../domain/models/store_connection.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import 'connection_add_sheet.dart';
import 'connection_detail_sheet.dart';
import 'connection_parts.dart';
import 'settings_section.dart';

/// Spec 17: "স্টোর / ওয়েবসাইট" - the merchant's website connections on every platform and the add button.
/// Shopify stores keep their own section (spec 13) right below.
class ConnectionsSection extends ConsumerWidget {
  const ConnectionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final list = (ref.watch(connectionsProvider).value ?? const <StoreConnection>[]).where((c) => c.isApi).toList();
    return SettingsSection(
      key: const Key('connectionsSection'),
      title: l.connectionsTitle,
      children: [
        if (list.isEmpty) Text(l.connectionsEmpty, key: const Key('connectionsEmpty'), style: AppText.sm),
        for (final c in list)
          InkWell(
            key: Key('connection-${c.id}'),
            onTap: () => showConnectionDetailSheet(context, c.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.siteName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title13),
                        Text(platformName(c.platform, l), style: AppText.sm),
                      ],
                    ),
                  ),
                  ConnectionStatusChip(c.status),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: AppColors.t3),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        AppButton.outline(
          key: const Key('addStoreButton'),
          label: l.addStoreButton,
          onPressed: () => showConnectionAddSheet(context),
        ),
      ],
    );
  }
}
