import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';

/// "পাঠানো বাকি (n)", the internet line and "☁ সব পাঠান".
class QueueHeader extends ConsumerStatefulWidget {
  const QueueHeader({super.key, required this.count, required this.sendable, required this.online});

  /// All queue items (queued, sending, failed).
  final int count;

  /// Queued + failed: what send-all can send.
  final int sendable;
  final bool online;

  @override
  ConsumerState<QueueHeader> createState() => _QueueHeaderState();
}

class _QueueHeaderState extends ConsumerState<QueueHeader> {
  bool _running = false;

  // Same send-all and toasts as the হোম button (spec 02), which this spec may not change.
  Future<void> _sendAll() async {
    if (_running) return;
    setState(() => _running = true);
    final l = AppLocalizations.of(context);
    await ref.read(transactionRepositoryProvider).retryAllPending();
    // Let the list stream deliver the final states before counting.
    await Future<void>.delayed(Duration.zero);
    final list = ref.read(transactionsProvider).value ?? const [];
    final failed = list.where((t) => t.syncStatus == SyncStatus.failed).length;
    if (mounted) {
      showToast(context, failed == 0 ? l.allSent : l.someFailed(failed));
      setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final enabled = widget.sendable > 0 && widget.online && !_running;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.queueTitle(widget.count), style: AppText.title16.copyWith(fontSize: 17)),
              Text(
                widget.online ? l.internetYes : l.internetNo,
                style: AppText.sm.copyWith(color: widget.online ? AppColors.ok : AppColors.er),
              ),
            ],
          ),
        ),
        AppButton.primary(
          key: const Key('sendAll'),
          label: l.sendAll,
          onPressed: enabled ? _sendAll : null,
        ),
      ],
    );
  }
}
