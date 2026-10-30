import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/validators.dart';
import '../../data/account_providers.dart';
import '../../domain/account_enums.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_button.dart';
import 'widgets/auth_layout.dart';

/// Login step 1: the merchant's email.
class EmailScreen extends ConsumerStatefulWidget {
  const EmailScreen({super.key});

  @override
  ConsumerState<EmailScreen> createState() => _EmailScreenState();
}

class _EmailScreenState extends ConsumerState<EmailScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  AuthResult? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // Set before the first await, so a second fast tap sends nothing.
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref.read(authRepositoryProvider).sendCode(normalizeEmail(_email.text));
    // On done the code screen replaces this one; staying busy blocks a late second tap.
    if (!mounted || result == AuthResult.done) return;
    setState(() {
      _busy = false;
      _error = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final error = switch (_error) {
      AuthResult.invalidEmail => l.errInvalidEmail,
      AuthResult.offline => l.internetNo,
      AuthResult.tooSoon => l.errTooSoon,
      _ => null,
    };
    return AuthLayout(children: [
      Text(l.loginEmailPrompt, style: AppText.title14),
      const SizedBox(height: 10),
      TextField(
        key: const Key('emailField'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        style: AppText.body13,
        onSubmitted: (_) => _send(),
      ),
      AuthError(error),
      AppButton.primary(key: const Key('sendCodeButton'), label: l.sendCode, onPressed: _busy ? null : _send),
    ]);
  }
}
