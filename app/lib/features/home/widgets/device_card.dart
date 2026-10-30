import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time.dart';
import '../../../data/providers.dart';
import '../home_summary.dart';
import '../../../domain/models/device_health.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/toast.dart';

/// Section 1: monitoring state, device name, monitoring switch and the server row.
class DeviceCard extends ConsumerWidget {
  const DeviceCard({super.key, required this.health, required this.deviceName});

  final DeviceHealth health;
  final String deviceName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final now = ref.watch(clockProvider);
    final on = health.monitoring;
    final online = serverReachable(health, now); // spec 13a rule 3
    final iconColor = on ? AppColors.em : AppColors.er;
    final serverColor = online ? AppColors.ok : AppColors.er;
    final contact = health.lastServerContactAt;
    return AppCard(
      key: const Key('deviceCard'),
      big: true,
      surface: true,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Text(on ? '◉' : '⊘', style: AppText.h3.copyWith(color: iconColor)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceName, style: AppText.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      on ? l.monitoringOnSubtitle : l.monitoringOffSubtitle,
                      style: AppText.sm,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppSwitch(
                key: const Key('monitoringSwitch'),
                value: on,
                onChanged: (v) => ref.read(deviceHealthRepositoryProvider).setMonitoring(v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.cd, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: serverColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (online ? l.serverConnected : l.serverDisconnected) +
                        (contact == null ? '' : l.lastContact(timeAgo(contact, now, l))),
                    style: AppText.sm.copyWith(color: AppColors.t1, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  key: const Key('pingButton'),
                  onTap: () async {
                    final ok = await ref.read(deviceHealthRepositoryProvider).pingServer();
                    if (context.mounted) showToast(context, ok ? l.pingOk : l.serverDisconnected);
                  },
                  child: Text('⟳', style: AppText.h3.copyWith(color: AppColors.em)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
