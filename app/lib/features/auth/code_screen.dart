import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/validators.dart';
import '../../data/account_providers.dart';
import '../../domain/account_enums.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_button.dart';
import 'widgets/auth_layout.dart';
import 'widgets/resend_countdown.dart';

/// Login step 2: the 6-digit code sent to [email].
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref.read(authRepositoryProvider).verifyCode(widget.email, _code.text);
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = false;
      _error = switch (result) {
        AuthResult.wrongCode => l.errWrongCode,
        AuthResult.offline => l.internetNo,
        _ => null,
      };
    });
  }

  Future<bool> _resend() async {
    final result = await ref.read(authRepositoryProvider).sendCode(widget.email);
    if (!mounted) return false;
    final l = AppLocalizations.of(context);
    setState(() {
      _error = switch (result) {
        AuthResult.offline => l.internetNo,
        AuthResult.tooSoon => l.errTooSoon,
        _ => null,
      };
    });
    return result == AuthResult.done;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final complete = isCompleteCode(_code.text);
    return AuthLayout(children: [
      Text(l.codeSentTo(widget.email), style: AppText.title14),
      const SizedBox(height: 10),
      TextField(
        key: const Key('codeField'),
        controller: _code,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        style: AppText.title16.copyWith(letterSpacing: 6),
        inputFormatters: [_DigitsOnly()],
        decoration: const InputDecoration(counterText: ''),
        onChanged: (_) => setState(() => _error = null),
      ),
      AuthError(_error),
      AppButton.primary(
        key: const Key('verifyButton'),
        label: l.verifyCode,
        onPressed: complete && !_busy ? _verify : null,
      ),
      const SizedBox(height: 4),
      ResendCountdown(onResend: _resend),
      AuthLink(
        key: const Key('changeEmail'),
        label: l.changeEmail,
        onTap: () => ref.read(authRepositoryProvider).signOut(),
      ),
    ]);
  }
}

/// Keeps digits only; Bangla digits become English.
class _DigitsOnly extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = toEnglishDigits(newValue.text).replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == newValue.text) return newValue;
    return TextEditingValue(text: digits, selection: TextSelection.collapsed(offset: digits.length));
  }
}
