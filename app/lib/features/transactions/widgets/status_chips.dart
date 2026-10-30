import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';

/// "সব" + one chip per status (reference .fp). Reads and writes transactionFilterProvider;
/// several chips show selected when the filter came from the হোম card.
class StatusChips extends ConsumerWidget {
  const StatusChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    final chips = [
      (VerifyStatus.verified, l.statusVerified),
      (VerifyStatus.pending, l.statusPending),
      (VerifyStatus.mismatch, l.statusMismatch),
      (VerifyStatus.rejected, l.statusRejected),
    ];
    return SingleChildScrollView(
      key: const Key('statusChips'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _StatusChip(
            key: const Key('statusChip-all'),
            label: l.statusAll,
            selected: filter == null,
            onTap: () => notifier.set(null),
          ),
          for (final (status, label) in chips) ...[
            const SizedBox(width: 8),
            _StatusChip(
              key: Key('statusChip-${status.name}'),
              label: label,
              selected: filter?.contains(status) ?? false,
              onTap: () => notifier.set({status}),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.em.withValues(alpha: 0.2) : AppColors.sf,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppText.sm.copyWith(
            color: selected ? AppColors.em : AppColors.t2,
            fontWeight: selected ? FontWeight.w700 : null,
          ),
        ),
      ),
    );
  }
}
