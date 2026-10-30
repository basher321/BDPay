import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/time.dart';
import '../../../core/validators.dart';
import '../../../data/account_providers.dart';
import '../../../data/providers.dart';
import '../../../domain/account_enums.dart';
import '../../../domain/models/shopify_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import 'settings_section.dart';
import 'shopify_disconnect_sheet.dart';
import 'shopify_setup_guide.dart';

/// Spec 05 rule 5 + spec 13 rules 4 and 5: connect a Shopify store; reconnect when Shopify's grant expired;
/// test the connection; how to disconnect; the setup guide.
class ShopifySection extends ConsumerWidget {
  const ShopifySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final store = ref.watch(shopifyStoreProvider).value;
    return SettingsSection(
      key: const Key('shopifySection'),
      title: l.shopifyTitle,
      children: [store == null ? const _ConnectForm() : _Connected(store: store)],
    );
  }
}

/// Rule 4: after the browser opens, "যুক্ত হচ্ছে…" until the store shows as connected (the section then switches
/// to the connected view) or 60 s pass ("এখনো যুক্ত হয়নি — আবার চেষ্টা করুন").
mixin _ConnectFlow<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  static const waitFor = Duration(seconds: 60);

  bool busy = false;
  bool waiting = false;
  String? error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> connect(String input) async {
    if (busy || waiting) return;
    final l = AppLocalizations.of(context);
    final domain = normalizeShopDomain(input);
    if (!isValidShopDomain(domain)) {
      setState(() => error = l.errShopDomain);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final result = await ref.read(storeRepositoryProvider).connectShopify(domain);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = switch (result) {
        ConnectResult.invalidDomain => l.errShopDomain,
        ConnectResult.offline => l.internetNo,
        ConnectResult.shopTaken => l.errShopTaken,
        ConnectResult.done => null,
      };
      if (result == ConnectResult.done) _startWaiting();
    });
  }

  void _startWaiting() {
    waiting = true;
    _timer?.cancel();
    _timer = Timer(waitFor, () {
      if (!mounted) return;
      setState(() {
        waiting = false;
        error = AppLocalizations.of(context).shopifyNotYet;
      });
    });
  }

  /// The button label: "যুক্ত হচ্ছে…" while connecting or waiting.
  String buttonLabel(String idle) => busy || waiting ? AppLocalizations.of(context).shopifyConnecting : idle;

  Widget errorText(Key key) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(error!, key: key, style: AppText.sm.copyWith(color: AppColors.er)),
        );
}

class _ConnectForm extends ConsumerStatefulWidget {
  const _ConnectForm();

  @override
  ConsumerState<_ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends ConsumerState<_ConnectForm> with _ConnectFlow {
  final _domain = TextEditingController();

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.shopifyPrompt, style: AppText.sm),
        const SizedBox(height: 8),
        TextField(
          key: const Key('shopField'),
          controller: _domain,
          enabled: !busy && !waiting,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: AppText.body13,
          decoration: InputDecoration(hintText: l.shopifyHint),
        ),
        errorText(const Key('shopError')),
        const SizedBox(height: 10),
        AppButton.primary(
          key: const Key('connectShopifyButton'),
          label: buttonLabel(l.connectShopify),
          onPressed: busy || waiting ? null : () => connect(_domain.text),
        ),
      ],
    );
  }
}

class _Connected extends ConsumerStatefulWidget {
  const _Connected({required this.store});

  final ShopifyStore store;

  @override
  ConsumerState<_Connected> createState() => _ConnectedState();
}

class _ConnectedState extends ConsumerState<_Connected> with _ConnectFlow {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final store = widget.store;
    final now = ref.watch(clockProvider);
    final connectedAt = store.connectedAt;
    final reconnect = store.needsReconnect;
    final mark = reconnect ? AppColors.wa : AppColors.ok;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: mark.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Text(reconnect ? '!' : '✓', style: AppText.title14.copyWith(color: mark)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    store.shopDomain,
                    key: const Key('shopDomain'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title13,
                  ),
                  if (reconnect)
                    Text(
                      l.shopifyReconnectNeeded,
                      key: const Key('shopifyReconnectLine'),
                      style: AppText.sm.copyWith(color: AppColors.wa),
                    )
                  else if (connectedAt != null)
                    Text(l.shopifyConnectedAgo(timeAgo(connectedAt, now, l)), style: AppText.sm),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (reconnect) ...[
          AppButton.primary(
            key: const Key('reconnectShopifyButton'),
            label: buttonLabel(l.shopifyReconnect),
            onPressed: busy || waiting ? null : () => connect(store.shopDomain),
          ),
          errorText(const Key('shopError')),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            if (!reconnect) ...[
              Expanded(
                child: AppButton.small(
                  key: const Key('testShopifyButton'),
                  label: l.shopifyTest,
                  outlined: true,
                  onPressed: () async {
                    final ok = await ref.read(storeRepositoryProvider).testConnection();
                    if (context.mounted) showToast(context, ok ? l.shopifyTestOk : l.shopifyTestFail);
                  },
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: AppButton.small(
                key: const Key('disconnectShopifyButton'),
                label: l.shopifyDisconnect,
                outlined: true,
                textColor: AppColors.er,
                onPressed: () => showShopifyDisconnectSheet(context),
              ),
            ),
          ],
        ),
        if (!reconnect) ...[
          const SizedBox(height: 10),
          const ShopifySetupGuide(),
        ],
      ],
    );
  }
}
