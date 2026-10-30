import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/wallet.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_switch.dart';
import '../../../widgets/operator_badge.dart';

/// One wallet: badge, number, "{account type} • {sim}", label, and the isActive switch.
/// Inactive wallets are faded to 50%.
class WalletRow extends StatelessWidget {
  const WalletRow({super.key, required this.wallet, required this.onTap, required this.onToggle});

  final Wallet wallet;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final label = wallet.label;
    return Opacity(
      key: Key('walletRow-${wallet.id}'),
      opacity: wallet.isActive ? 1 : 0.5,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              OperatorBadge(wallet.operator),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(wallet.walletNumber, style: AppText.title13),
                    Text(
                      l.walletMeta(wallet.accountType.label(l), wallet.simSlot.label(l)),
                      style: AppText.sm,
                    ),
                    if (label != null)
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.mu12),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AppSwitch(key: Key('walletSwitch-${wallet.id}'), value: wallet.isActive, onChanged: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}
