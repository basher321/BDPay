import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shell/app_tab.dart';
import '../home_summary.dart';

/// Section 4: three counts; a tap filters the লেনদেন tab and switches to it.
class CountCards extends ConsumerWidget {
  const CountCards({super.key, required this.summary});

  final HomeSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    void open(Set<VerifyStatus> filter) {
      ref.read(transactionFilterProvider.notifier).set(filter);
      ref.read(selectedTabProvider.notifier).select(AppTab.transactions);
    }

    return Row(
      children: [
        _CountCard(
          key: const Key('countVerified'),
          label: l.countVerified,
          value: summary.verified,
          color: AppColors.ok,
          onTap: () => open({VerifyStatus.verified}),
        ),
        const SizedBox(width: 8),
        _CountCard(
          key: const Key('countPending'),
          label: l.countPending,
          value: summary.pending,
          color: AppColors.wa,
          onTap: () => open({VerifyStatus.pending}),
        ),
        const SizedBox(width: 8),
        _CountCard(
          key: const Key('countBad'),
          label: l.countMismatchRejected,
          value: summary.mismatchOrRejected,
          color: AppColors.er,
          onTap: () => open({VerifyStatus.mismatch, VerifyStatus.rejected}),
        ),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({super.key, required this.label, required this.value, required this.color, required this.onTap});

  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    return Expanded(
      child: Material(
        color: AppColors.cd,
        shape: RoundedRectangleBorder(borderRadius: radius, side: const BorderSide(color: AppColors.bd)),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: AppText.sm.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text('●', style: AppText.sm.copyWith(color: color)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('$value', style: AppText.stat20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
