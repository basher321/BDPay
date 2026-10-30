import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import 'queue_logic.dart';
import 'widgets/queue_card.dart';
import 'widgets/queue_header.dart';
import 'widgets/queue_info_card.dart';

/// The পাঠানো বাকি tab: info card, header with send-all, the queue (oldest first) or the empty state.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final items = queueItems(ref.watch(transactionsProvider).value ?? const []);
    final online = ref.watch(deviceHealthProvider).value?.internetOnline ?? true;
    final autoSend = ref.watch(settingsProvider).value?.autoSend ?? true;
    final sendable = items.where((t) => t.syncStatus.isPending).length;
    return CustomScrollView(
      key: const Key('queueList'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                QueueInfoCard(autoSend: autoSend),
                const SizedBox(height: 12),
                QueueHeader(count: items.length, sendable: sendable, online: online),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              key: const Key('queueEmpty'),
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
              child: Column(
                children: [
                  Text('☁', style: AppText.emptyIcon.copyWith(fontSize: 52, color: AppColors.em)),
                  const SizedBox(height: 6),
                  Text(l.queueEmptyTitle, style: AppText.title16),
                  const SizedBox(height: 4),
                  Text(l.queueEmptyHint, style: AppText.sm),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverList.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => QueueCard(
                key: ValueKey('queueCard-${items[i].id}'),
                transaction: items[i],
                online: online,
              ),
            ),
          ),
      ],
    );
  }
}
