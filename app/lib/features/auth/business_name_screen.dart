import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/validators.dart';
import '../../data/account_providers.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_button.dart';
import 'widgets/auth_layout.dart';

/// First sign-in only: the merchant names the business (2 to 60 characters).
class BusinessNameScreen extends ConsumerStatefulWidget {
  const BusinessNameScreen({super.key});

  @override
  ConsumerState<BusinessNameScreen> createState() => _BusinessNameScreenState();
}

class _BusinessNameScreenState extends ConsumerState<BusinessNameScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(authRepositoryProvider).createMerchant(_name.text.trim());
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final valid = isValidBusinessName(_name.text);
    return AuthLayout(children: [
      Text(l.businessNamePrompt, style: AppText.title14),
      const SizedBox(height: 10),
      TextField(
        key: const Key('businessNameField'),
        controller: _name,
        maxLength: 60,
        style: AppText.body13,
        decoration: const InputDecoration(counterText: ''),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      AppButton.primary(
        key: const Key('startButton'),
        label: l.startButton,
        onPressed: valid && !_busy ? _start : null,
      ),
    ]);
  }
}
