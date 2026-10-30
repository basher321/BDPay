import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/colors.dart';
import '../data/providers.dart';
import '../features/home/home_summary.dart';
import '../l10n/app_localizations.dart';

class AppHeader extends ConsumerWidget {
  const AppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final health = ref.watch(deviceHealthProvider).value;
    // Spec 13a rule 3: the pill follows the last server contact.
    final online = health == null || serverReachable(health, ref.watch(clockProvider));
    final pillColor = online ? AppColors.ok : AppColors.er;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.em, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shield, size: 18, color: AppColors.onEm),
          ),
          const SizedBox(width: 10),
          Expanded(
            // The app is called just "BDPay" (owner decision, 2026-10-30).
            child: Text(l.headerBrand, style: AppText.logoBrand, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Container(
            key: const Key('onlinePill'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.sf,
              border: Border.all(color: AppColors.bd),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: pillColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(online ? l.online : l.offline, style: AppText.pill.copyWith(color: pillColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
