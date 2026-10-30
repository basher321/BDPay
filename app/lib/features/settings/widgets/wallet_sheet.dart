import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../domain/account_enums.dart';
import '../../../domain/enums.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/repositories/repository_errors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/operator_badge.dart';
import 'settings_section.dart';

/// Opens the add sheet ([edit] null) or the edit sheet for [edit].
Future<void> showWalletSheet(BuildContext context, {Wallet? edit}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bigCard)),
    ),
    builder: (_) => WalletSheet(edit: edit),
  );
}

/// Rule 7: operator, number, account type, SIM, label. In edit mode operator and number are read-only.
class WalletSheet extends ConsumerStatefulWidget {
  const WalletSheet({super.key, this.edit});

  final Wallet? edit;

  @override
  ConsumerState<WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends ConsumerState<WalletSheet> {
  late final _number = TextEditingController(text: widget.edit?.walletNumber ?? '');
  late final _label = TextEditingController(text: widget.edit?.label ?? '');
  late MfsOperator _operator = widget.edit?.operator ?? MfsOperator.bkash;
  late AccountType _accountType = widget.edit?.accountType ?? AccountType.merchant;
  late SimSlot _sim = widget.edit?.simSlot ?? SimSlot.sim1;
  bool _busy = false;
  AddWalletResult? _error;

  /// Spec 13: the save could not reach the server; nothing was saved.
  bool _offline = false;

  @override
  void dispose() {
    _number.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final edit = widget.edit;
    final w = Wallet(
      id: edit?.id ?? '',
      operator: edit?.operator ?? _operator,
      walletNumber: edit?.walletNumber ?? _number.text,
      accountType: _accountType,
      label: _label.text,
      simSlot: _sim,
      isActive: edit?.isActive ?? true,
    );
    final repo = ref.read(walletRepositoryProvider);
    final AddWalletResult result;
    try {
      result = edit == null ? await repo.add(w) : await repo.update(w);
    } on OfflineError {
      // The typed values stay in the form (rule 3).
      if (mounted) {
        setState(() {
          _busy = false;
          _offline = true;
          _error = null;
        });
      }
      return;
    }
    if (!mounted) return;
    if (result == AddWalletResult.done) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _offline = false;
      _error = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final edit = widget.edit;
    final error = _offline ? l.internetNo : switch (_error) {
      AddWalletResult.invalidNumber => l.errWalletNumber,
      AddWalletResult.duplicate => l.errWalletDuplicate,
      AddWalletResult.simTaken => l.errSimTaken,
      _ => null,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Column(
          key: const Key('walletSheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(edit == null ? l.addWalletTitle : l.walletsTitle, style: AppText.title16),
            const SizedBox(height: 14),
            if (edit != null)
              Row(children: [
                OperatorBadge(edit.operator),
                const SizedBox(width: 10),
                Text(edit.walletNumber, key: const Key('walletNumberReadOnly'), style: AppText.title14),
              ])
            else ...[
              FieldLabel(l.operatorsTitle),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final op in MfsOperator.values)
                    _Choice(
                      key: Key('opChip-${op.name}'),
                      label: op.label(l),
                      selected: op == _operator,
                      color: op.brandColor,
                      textColor: op.textColor,
                      onTap: () => setState(() => _operator = op),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              FieldLabel(l.walletNumberLabel),
              TextField(
                key: const Key('walletNumberField'),
                controller: _number,
                keyboardType: TextInputType.phone,
                style: AppText.body13,
                onChanged: (_) => setState(() => _error = null),
              ),
            ],
            const SizedBox(height: 14),
            FieldLabel(l.accountTypeLabel),
            Wrap(spacing: 8, children: [
              for (final t in AccountType.values)
                _Choice(
                  key: Key('accountChip-${t.name}'),
                  label: t.label(l),
                  selected: t == _accountType,
                  onTap: () => setState(() => _accountType = t),
                ),
            ]),
            const SizedBox(height: 6),
            Text(l.accountTypeNote, style: AppText.sm),
            const SizedBox(height: 14),
            FieldLabel(l.simLabel),
            Wrap(spacing: 8, children: [
              for (final s in SimSlot.values)
                _Choice(
                  key: Key('simChip-${s.name}'),
                  label: s.label(l),
                  selected: s == _sim,
                  onTap: () => setState(() {
                    _sim = s;
                    _error = null;
                  }),
                ),
            ]),
            const SizedBox(height: 14),
            FieldLabel(l.walletLabelLabel),
            TextField(
              key: const Key('walletLabelField'),
              controller: _label,
              maxLength: 30,
              style: AppText.body13,
              decoration: const InputDecoration(counterText: ''),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error, key: const Key('walletError'), style: AppText.sm.copyWith(color: AppColors.er)),
              ),
            const SizedBox(height: 14),
            AppButton.primary(key: const Key('saveWalletButton'), label: l.save, onPressed: _busy ? null : _save),
          ],
        ),
      ),
    );
  }
}

/// A selectable chip; selected uses [color] (emerald by default), like the reference chips.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.em,
    this.textColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppColors.cd,
          border: Border.all(color: selected ? color : AppColors.bd),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppText.chip.copyWith(color: selected ? (textColor ?? color) : AppColors.t2),
        ),
      ),
    );
  }
}
