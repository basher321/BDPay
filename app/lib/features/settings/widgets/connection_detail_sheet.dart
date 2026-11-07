import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time.dart';
import '../../../data/account_providers.dart';
import '../../../data/providers.dart';
import '../../../domain/models/store_connection.dart';
import '../../../domain/repositories/connections_repository.dart';
import '../../../domain/repositories/repository_errors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import 'confirm_dialog.dart';
import 'connection_parts.dart';
import 'settings_section.dart';

/// Spec 17 connection detail: site, key start, webhook address, new key, turn off, and the guide.
Future<void> showConnectionDetailSheet(BuildContext context, String connectionId) =>
    showSettingsSheet<void>(context, (_) => ConnectionDetailSheet(connectionId: connectionId));

class ConnectionDetailSheet extends ConsumerStatefulWidget {
  const ConnectionDetailSheet({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<ConnectionDetailSheet> createState() => _ConnectionDetailSheetState();
}

class _ConnectionDetailSheetState extends ConsumerState<ConnectionDetailSheet> {
  TextEditingController? _webhook;
  bool _busy = false;
  String? _error;
  String? _newKey;

  @override
  void dispose() {
    _webhook?.dispose();
    super.dispose();
  }

  /// Runs one write; offline / rejected values show under the webhook field or as a toast.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on OfflineError {
      if (mounted) showToast(context, l.internetNo);
    } on ConnectionInputError {
      if (mounted) setState(() => _error = l.errSiteUrl);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list = ref.watch(connectionsProvider).value ?? const <StoreConnection>[];
    final c = list.where((x) => x.id == widget.connectionId).firstOrNull;
    if (c == null) return const SizedBox(height: 120);
    final webhook = _webhook ??= TextEditingController(text: c.webhookUrl ?? '');
    final repo = ref.read(connectionsRepositoryProvider);
    final active = c.status == ConnectionStatus.active;
    final now = ref.watch(clockProvider);
    final newKey = _newKey;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          child: Column(
            key: const Key('connectionDetail'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(c.siteName, style: AppText.title16)),
                  ConnectionStatusChip(c.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(platformName(c.platform, l), style: AppText.sm),
              if (c.siteUrl != null) Text(c.siteUrl!, style: AppText.sm),
              Text(l.connConnectedAgo(timeAgo(c.connectedAt, now, l)), style: AppText.mu12),
              const SizedBox(height: 12),
              if (c.apiKeyPrefix != null) ...[
                FieldLabel(l.keyPrefixLabel),
                Text('${c.apiKeyPrefix}…', key: const Key('keyPrefix'), style: AppText.body13),
                const SizedBox(height: 12),
              ],
              if (newKey != null) ...[
                Text(l.newKeyTitle, style: AppText.title13),
                const SizedBox(height: 4),
                Text(l.keyShownOnce, style: AppText.sm.copyWith(color: AppColors.wa)),
                const SizedBox(height: 8),
                SecretBox(label: l.apiKeyLabel, value: newKey, copyKey: const Key('copyNewKey')),
              ],
              if (active) ...[
                FieldLabel(l.webhookUrlLabel),
                TextField(
                  key: const Key('webhookField'),
                  controller: webhook,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: AppText.body13,
                  decoration: InputDecoration(hintText: l.webhookUrlHint),
                  onChanged: (_) => setState(() => _error = null),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_error!, key: const Key('webhookError'), style: AppText.sm.copyWith(color: AppColors.er)),
                  ),
                const SizedBox(height: 8),
                AppButton.outline(
                  key: const Key('saveWebhookButton'),
                  label: l.saveWebhookButton,
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await repo.updateWebhook(c.id, webhook.text);
                            if (mounted) showToast(this.context, l.webhookSaved);
                          }),
                ),
                const SizedBox(height: 8),
                AppButton.outline(
                  key: const Key('rotateKeyButton'),
                  label: l.rotateKeyButton,
                  onPressed: _busy
                      ? null
                      : () async {
                          if (!await showConfirmDialog(context, l.rotateKeyConfirm)) return;
                          await _run(() async {
                            final key = await repo.rotateKey(c.id);
                            if (mounted) setState(() => _newKey = key);
                          });
                        },
                ),
                const SizedBox(height: 8),
                AppButton.outline(
                  key: const Key('disableConnButton'),
                  label: l.disableConnButton,
                  textColor: AppColors.er,
                  onPressed: _busy
                      ? null
                      : () async {
                          if (!await showConfirmDialog(context, l.disableConnConfirm)) return;
                          await _run(() => repo.disable(c.id));
                        },
                ),
                const SizedBox(height: 16),
              ],
              ConnectionGuide(platform: c.platform),
            ],
          ),
        ),
      ),
    );
  }
}
