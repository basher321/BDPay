import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../domain/enums.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';

/// Section 5: sends every queued and failed item. Disabled while it runs, so a fast
/// double tap sends only once. Stays mounted (and invisible) when there is nothing to send,
/// so the result toast still shows after the last item is sent.
class SendPendingButton extends ConsumerStatefulWidget {
  const SendPendingButton({super.key, required this.count});

  final int count;

  @override
  ConsumerState<SendPendingButton> createState() => _SendPendingButtonState();
}

class _SendPendingButtonState extends ConsumerState<SendPendingButton> {
  bool _running = false;

  Future<void> _send() async {
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
    if (widget.count == 0 && !_running) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppButton.outline(
        key: const Key('sendPending'),
        label: AppLocalizations.of(context).sendPendingNow(widget.count),
        onPressed: _running ? null : _send,
      ),
    );
  }
}
