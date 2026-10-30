import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/models/sms_transaction.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/sync_status_label.dart';

/// "সার্ভারের উত্তর": sync state, HTTP code and the server message.
class ServerReplyCard extends StatelessWidget {
  const ServerReplyCard({super.key, required this.transaction});

  final SmsTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = transaction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.serverReplyTitle, style: AppText.title13),
        const SizedBox(height: 6),
        AppCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(l.serverReplyState, style: AppText.sm)),
                SyncStatusLabel(t.syncStatus),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: Text(l.serverReplyCode, style: AppText.sm)),
                Text(t.serverCode?.toString() ?? l.noValue, style: AppText.title13),
              ]),
              const SizedBox(height: 6),
              Text(t.serverMessage ?? l.serverReplyNone, style: AppText.body12.copyWith(fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}
