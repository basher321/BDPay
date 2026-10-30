import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'home_summary.dart';
import 'widgets/alerts_card.dart';
import 'widgets/count_cards.dart';
import 'widgets/disconnected_banner.dart';
import 'widgets/update_card.dart';
import 'widgets/dev_lab_button.dart';
import 'widgets/device_card.dart';
import 'widgets/health_card.dart';
import 'widgets/latest_transactions.dart';
import 'widgets/operator_strip.dart';
import 'widgets/send_pending_button.dart';
import 'widgets/setup_card.dart';
import 'widgets/today_total_card.dart';

/// The হোম tab: sections 1-8 of spec 02, in order, in one scrolling list.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(transactionsProvider).value ?? const [];
    final health = ref.watch(deviceHealthProvider).value;
    final settings = ref.watch(settingsProvider).value;
    if (health == null || settings == null) return const SizedBox.shrink();
    final summary = summarize(all, ref.watch(clockProvider));

    Widget gap(Widget child) => Padding(padding: const EdgeInsets.only(bottom: 14), child: child);
    return ListView(
      key: const Key('homeList'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        // Spec 13a rule 2: shown only when the server revoked this phone.
        const DisconnectedBanner(),
        // Spec 15: a newer app version is out; adds its own gap when shown.
        const UpdateCard(),
        // Spec 05: hidden when wallets and Shopify are both set up; adds its own gap when shown.
        const SetupCard(),
        // Spec 13: hidden when there are no open alerts; adds its own gap when shown.
        const AlertsCard(),
        gap(DeviceCard(health: health, deviceName: settings.deviceName)),
        gap(HealthCard(health: health)),
        gap(TodayTotalCard(totalPoisha: summary.todayVerifiedPoisha)),
        gap(CountCards(summary: summary)),
        // Hidden when 0; adds its own gap when shown.
        SendPendingButton(count: summary.sendable),
        if (settings.developerMode) gap(const DevLabButton()),
        gap(OperatorStrip(counts: summary.perOperator, enabled: settings.enabledOperators)),
        LatestTransactions(all: all),
      ],
    );
  }
}
