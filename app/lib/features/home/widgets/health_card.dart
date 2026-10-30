import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time.dart';
import '../../../data/providers.dart';
import '../../../domain/models/device_health.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/app_card.dart';
import '../home_summary.dart';
import 'auto_start_row.dart';

/// Section 2: the device health checklist.
class HealthCard extends ConsumerWidget {
  const HealthCard({super.key, required this.health});

  final DeviceHealth health;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final now = ref.watch(clockProvider);
    final repo = ref.read(deviceHealthRepositoryProvider);
    final problems = healthProblemCount(health);
    final lastSms = health.lastSmsAt;
    return AppCard(
      key: const Key('healthCard'),
      surface: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(l.healthTitle, style: AppText.title13)),
              Text(
                problems == 0 ? l.healthAllOk : l.healthProblems(problems),
                key: const Key('healthHeader'),
                style: AppText.badge.copyWith(color: problems == 0 ? AppColors.ok : AppColors.wa),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _HealthRow(
            ok: health.smsPermission,
            title: l.healthSmsTitle,
            hint: health.smsPermission ? l.healthSmsOk : l.healthSmsProblem,
            fixKey: const Key('fixSms'),
            onFix: repo.requestSmsPermission,
          ),
          _HealthRow(
            ok: health.batteryOptimizationOff,
            title: l.healthBatteryTitle,
            hint: health.batteryOptimizationOff ? l.healthBatteryOk : l.healthBatteryProblem,
            fixKey: const Key('fixBattery'),
            onFix: repo.requestBatteryExemption,
          ),
          _HealthRow(
            ok: health.internetOnline,
            title: l.healthInternetTitle,
            hint: health.internetOnline ? l.healthInternetOk : l.healthInternetProblem,
          ),
          _HealthRow(
            ok: health.monitoring,
            title: l.healthMonitoringTitle,
            hint: health.monitoring ? l.healthMonitoringOk : l.healthMonitoringProblem,
          ),
          // Spec 06, rule 7: only for phone makers that stop background apps.
          if (showsAutoStartRow(health.maker)) AutoStartRow(health: health),
          _HealthRow(
            ok: true,
            title: l.healthLastSmsTitle,
            hint: lastSms == null ? l.healthLastSmsNone : timeAgo(lastSms, now, l),
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.ok, required this.title, required this.hint, this.fixKey, this.onFix});

  final bool ok;
  final String title;
  final String hint;
  final Key? fixKey;
  final Future<void> Function()? onFix;

  @override
  Widget build(BuildContext context) {
    final c = ok ? AppColors.ok : AppColors.wa;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Text(ok ? '✓' : '!', style: AppText.badge.copyWith(color: c)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body12.copyWith(fontWeight: FontWeight.w600)),
                Text(hint, style: AppText.sm, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (!ok && onFix != null) ...[
            const SizedBox(width: 8),
            AppButton.small(
              key: fixKey,
              label: AppLocalizations.of(context).fix,
              outlined: true,
              onPressed: onFix,
            ),
          ],
        ],
      ),
    );
  }
}
