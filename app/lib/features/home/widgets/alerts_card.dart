import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../widgets/app_card.dart';

/// Spec 13 rule 6: one red-bordered card per open alert (title and hint from the server), newest first.
/// Hidden when there are none. Tapping does nothing in v1. Adds its own bottom gap when shown.
class AlertsCard extends ConsumerWidget {
  const AlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = [...ref.watch(alertsProvider).value ?? const []]..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('alertsCard'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in alerts)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: AppCard(
              key: Key('alert-${a.id}'),
              color: AppColors.er.withValues(alpha: 0.08),
              borderColor: AppColors.er.withValues(alpha: 0.6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title, style: AppText.title13.copyWith(color: AppColors.er)),
                  const SizedBox(height: 4),
                  Text(a.hint, style: AppText.sm),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
