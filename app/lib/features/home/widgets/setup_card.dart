import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/app_tab.dart';
import '../../../widgets/app_card.dart';
import '../setup_status.dart';

/// Amber "সেটআপ বাকি" card at the top of হোম. Hidden when wallets and Shopify are both done.
/// Adds its own bottom gap when shown.
class SetupCard extends ConsumerWidget {
  const SetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider);
    final store = ref.watch(shopifyStoreProvider);
    if (!wallets.hasValue || !store.hasValue) return const SizedBox.shrink();
    final status = setupStatus(wallets.value!, store.value);
    if (!status.show) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    void openSettings() => ref.read(selectedTabProvider.notifier).select(AppTab.settings);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        key: const Key('setupCard'),
        color: AppColors.wa.withValues(alpha: 0.08),
        borderColor: AppColors.wa.withValues(alpha: 0.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.setupTitle, style: AppText.title13.copyWith(color: AppColors.wa)),
            const SizedBox(height: 6),
            _SetupRow(
              rowKey: 'setupWallet',
              done: status.hasActiveWallet,
              title: l.addWalletTitle,
              onTap: openSettings,
            ),
            _SetupRow(
              rowKey: 'setupShopify',
              done: status.hasStore,
              title: l.connectShopify,
              onTap: openSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({required this.rowKey, required this.done, required this.title, required this.onTap});

  final String rowKey;
  final bool done;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = done ? AppColors.ok : AppColors.wa;
    return GestureDetector(
      key: Key('${rowKey}Row'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Text(done ? '✓' : '!', key: Key('${rowKey}Mark'), style: AppText.badge.copyWith(color: c)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: AppText.body12.copyWith(fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.t3),
          ],
        ),
      ),
    );
  }
}
