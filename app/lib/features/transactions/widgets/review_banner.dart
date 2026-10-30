import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_card.dart';

/// Amber card shown while any payment is mismatch; a tap filters to mismatch only.
class ReviewBanner extends ConsumerWidget {
  const ReviewBanner({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      key: const Key('reviewBanner'),
      color: AppColors.wa.withValues(alpha: 0.12),
      borderColor: AppColors.wa.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      onTap: () => ref.read(transactionFilterProvider.notifier).set({VerifyStatus.mismatch}),
      child: Text(
        AppLocalizations.of(context).reviewBanner(count),
        style: AppText.body12.copyWith(color: AppColors.wa, fontWeight: FontWeight.w700),
      ),
    );
  }
}
