import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../domain/models/device_health.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';

/// Spec 06, rule 7: phones that stop background apps. The app cannot check this itself,
/// so the row is a problem until the merchant ticks "করেছি".
class AutoStartRow extends ConsumerWidget {
  const AutoStartRow({super.key, required this.health});

  final DeviceHealth health;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final repo = ref.read(deviceHealthRepositoryProvider);
    final ok = health.autoStartConfirmed;
    final c = ok ? AppColors.ok : AppColors.wa;
    return Padding(
      key: const Key('autoStartRow'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Text(ok ? '✓' : '!', key: const Key('autoStartMark'), style: AppText.badge.copyWith(color: c)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.autoStartTitle, style: AppText.body12.copyWith(fontWeight: FontWeight.w600)),
                Text(l.autoStartHint, style: AppText.sm),
                Text(l.autoStartForceStop, style: AppText.sm.copyWith(color: AppColors.wa)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    AppButton.small(
                      key: const Key('openAppSettings'),
                      label: l.openSettings,
                      outlined: true,
                      onPressed: repo.openAppSettings,
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      key: const Key('autoStartDone'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => repo.setAutoStartConfirmed(!ok),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: Checkbox(
                              value: ok,
                              onChanged: (v) => repo.setAutoStartConfirmed(v ?? false),
                              activeColor: AppColors.em,
                              checkColor: AppColors.onEm,
                              side: const BorderSide(color: AppColors.t3),
                            ),
                          ),
                          Text(l.autoStartDone, style: AppText.body12),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
