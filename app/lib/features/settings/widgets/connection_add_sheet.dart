import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/validators.dart';
import '../../../data/account_providers.dart';
import '../../../domain/models/store_connection.dart';
import '../../../domain/repositories/connections_repository.dart';
import '../../../domain/repositories/repository_errors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import 'connection_parts.dart';
import 'settings_section.dart';

/// Spec 17 add flow: platform picker -> site name + address -> the API key and webhook secret (once) + guide.
Future<void> showConnectionAddSheet(BuildContext context) =>
    showSettingsSheet<void>(context, (_) => const ConnectionAddSheet());

class ConnectionAddSheet extends ConsumerStatefulWidget {
  const ConnectionAddSheet({super.key});

  @override
  ConsumerState<ConnectionAddSheet> createState() => _ConnectionAddSheetState();
}

class _ConnectionAddSheetState extends ConsumerState<ConnectionAddSheet> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _url = TextEditingController();
  StorePlatform? _platform;
  NewConnectionKeys? _keys;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _pick(StorePlatform p) {
    if (p == StorePlatform.shopify) {
      // Shopify keeps its own OAuth flow (spec 13) in the Shopify section.
      Navigator.of(context).pop();
      showToast(context, AppLocalizations.of(context).shopifyUseSection);
      return;
    }
    setState(() => _platform = p);
  }

  Future<void> _create() async {
    final platform = _platform;
    if (_busy || platform == null) return;
    final l = AppLocalizations.of(context);
    if (!isValidSiteName(_name.text)) {
      setState(() => _error = l.errSiteName);
      return;
    }
    if (normalizeHttpsUrl(_url.text) == null) {
      setState(() => _error = l.errSiteUrl);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final keys = await ref.read(connectionsRepositoryProvider).create(platform, _name.text.trim(), _url.text);
      if (mounted) setState(() => _keys = keys);
    } on OfflineError {
      if (mounted) setState(() => _error = l.internetNo);
    } on ConnectionInputError catch (e) {
      if (mounted) {
        setState(() => _error = switch (e.kind) {
              CreateConnectionError.invalidName => l.errSiteName,
              CreateConnectionError.invalidUrl => l.errSiteUrl,
              CreateConnectionError.duplicate => l.errSiteDuplicate,
            });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = _keys;
    final platform = _platform;
    final Widget body = keys != null
        ? _keysView(keys)
        : platform != null
            ? _formView(platform)
            : _pickerView();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
          child: body,
        ),
      ),
    );
  }

  Widget _pickerView() {
    final l = AppLocalizations.of(context);
    final q = _search.text.trim().toLowerCase();
    final shown = StorePlatform.values
        .where((p) => q.isEmpty || platformName(p, l).toLowerCase().contains(q) || p.name.contains(q))
        .toList();
    return Column(
      key: const Key('platformPicker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.choosePlatformTitle, style: AppText.title16),
        const SizedBox(height: 12),
        TextField(
          key: const Key('platformSearch'),
          controller: _search,
          autocorrect: false,
          style: AppText.body13,
          decoration: InputDecoration(hintText: l.platformSearchHint),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        if (shown.isEmpty) Text(l.platformNoMatch, key: const Key('platformNoMatch'), style: AppText.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in shown)
              InkWell(
                key: Key('platform-${p.name}'),
                borderRadius: BorderRadius.circular(AppRadius.smallButton),
                onTap: () => _pick(p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.cd,
                    border: Border.all(color: AppColors.bd),
                    borderRadius: BorderRadius.circular(AppRadius.smallButton),
                  ),
                  child: Text(platformName(p, l), style: AppText.body13),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _formView(StorePlatform platform) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const Key('connectionForm'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(platformName(platform, l), key: const Key('formPlatform'), style: AppText.title16),
        const SizedBox(height: 14),
        FieldLabel(l.siteNameLabel),
        TextField(
          key: const Key('siteNameField'),
          controller: _name,
          enabled: !_busy,
          maxLength: 60,
          style: AppText.body13,
          decoration: const InputDecoration(counterText: ''),
          onChanged: (_) => setState(() => _error = null),
        ),
        const SizedBox(height: 10),
        FieldLabel(l.siteUrlLabel),
        TextField(
          key: const Key('siteUrlField'),
          controller: _url,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: AppText.body13,
          decoration: InputDecoration(hintText: l.siteUrlHint),
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, key: const Key('connectionError'), style: AppText.sm.copyWith(color: AppColors.er)),
          ),
        const SizedBox(height: 14),
        AppButton.primary(
          key: const Key('createConnectionButton'),
          label: l.connectSiteButton,
          onPressed: _busy ? null : _create,
        ),
      ],
    );
  }

  Widget _keysView(NewConnectionKeys keys) {
    final l = AppLocalizations.of(context);
    return Column(
      key: const Key('connectionKeys'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('✓ ${l.siteConnectedTitle}', style: AppText.title16.copyWith(color: AppColors.ok)),
        const SizedBox(height: 4),
        Text(keys.connection.siteName, style: AppText.sm),
        const SizedBox(height: 12),
        Text(l.keyShownOnce, key: const Key('keyShownOnce'), style: AppText.sm.copyWith(color: AppColors.wa)),
        const SizedBox(height: 10),
        SecretBox(label: l.apiKeyLabel, value: keys.apiKey, copyKey: const Key('copyApiKey')),
        SecretBox(label: l.webhookSecretLabel, value: keys.webhookSecret, copyKey: const Key('copyWebhookSecret')),
        ConnectionGuide(platform: keys.connection.platform),
        const SizedBox(height: 10),
        AppButton.primary(
          key: const Key('connectionDoneButton'),
          label: l.doneButton,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
