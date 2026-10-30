import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/account_providers.dart';
import '../../../domain/account_enums.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/repositories/repository_errors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import '../settings_rules.dart';
import 'confirm_dialog.dart';
import 'settings_section.dart';
import 'wallet_row.dart';
import 'wallet_sheet.dart';

/// Rule 6: the merchant's wallets, the add button, and the last-active-wallet confirm.
class WalletsSection extends ConsumerWidget {
  const WalletsSection({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, List<Wallet> wallets, Wallet w, bool on) async {
    final l = AppLocalizations.of(context);
    if (!on && isLastActiveWallet(wallets, w.id) && !await showConfirmDialog(context, l.lastWalletConfirm)) return;
    final AddWalletResult result;
    try {
      result = await ref.read(walletRepositoryProvider).setActive(w.id, on);
    } on OfflineError {
      if (context.mounted) showToast(context, l.internetNo);
      return;
    }
    if (result == AddWalletResult.simTaken && context.mounted) showToast(context, l.errSimTaken);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final wallets = ref.watch(walletsProvider).value ?? const <Wallet>[];
    return SettingsSection(
      key: const Key('walletsSection'),
      title: l.walletsTitle,
      children: [
        for (final w in wallets)
          WalletRow(
            wallet: w,
            onTap: () => showWalletSheet(context, edit: w),
            onToggle: (on) => _toggle(context, ref, wallets, w, on),
          ),
        const SizedBox(height: 8),
        AppButton.outline(
          key: const Key('addWalletButton'),
          label: l.addWalletButton,
          onPressed: () => showWalletSheet(context),
        ),
      ],
    );
  }
}
