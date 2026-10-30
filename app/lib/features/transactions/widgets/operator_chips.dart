import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';
import '../transactions_providers.dart';

/// "সব অপারেটর" + one chip per operator, in one sideways-scrolling row (reference .fc).
class OperatorChips extends ConsumerWidget {
  const OperatorChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final selected = ref.watch(operatorFilterProvider);
    final notifier = ref.read(operatorFilterProvider.notifier);
    return SingleChildScrollView(
      key: const Key('operatorChips'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            key: const Key('opChip-all'),
            label: l.allOperators,
            selected: selected == null,
            onTap: () => notifier.toggle(null),
          ),
          for (final op in MfsOperator.values) ...[
            const SizedBox(width: 8),
            _Chip(
              key: Key('opChip-${op.name}'),
              label: op.label(l),
              selected: selected == op,
              color: op.textColor,
              brand: op.brandColor,
              onTap: () => notifier.toggle(op),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.selected, required this.onTap, this.color, this.brand});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Operator text and brand colours; null for the "all" chip, which uses emerald.
  final Color? color;
  final Color? brand;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final Color border;
    if (!selected) {
      bg = AppColors.sf;
      fg = AppColors.t2;
      border = AppColors.bd;
    } else if (brand != null) {
      bg = brand!.withValues(alpha: 0.2);
      fg = color!;
      border = brand!;
    } else {
      bg = AppColors.em.withValues(alpha: 0.2);
      fg = AppColors.em;
      border = AppColors.bd;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppText.sm.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : null),
        ),
      ),
    );
  }
}
