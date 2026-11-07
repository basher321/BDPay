import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/validators.dart';
import '../../data/account_providers.dart';
import '../../domain/account_enums.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/app_button.dart';
import 'widgets/auth_layout.dart';

/// Spec 16: username + password. One screen with two modes: login and new account.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  bool _showForgot = false;
  bool _showPassword = false;
  AuthResult? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Set before the first await, so a second fast tap sends nothing.
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(authRepositoryProvider);
    final username = normalizeUsername(_username.text);
    final result =
        _signup ? await repo.signUp(username, _password.text) : await repo.signIn(username, _password.text);
    // On done the next screen replaces this one; staying busy blocks a late second tap.
    if (!mounted || result == AuthResult.done) return;
    setState(() {
      _busy = false;
      _error = result;
    });
  }

  void _toggleMode() => setState(() {
        _signup = !_signup;
        _error = null;
        _showForgot = false;
      });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final error = switch (_error) {
      AuthResult.invalidUsername => l.errInvalidUsername,
      AuthResult.weakPassword => l.errWeakPassword,
      AuthResult.wrongPassword => l.errWrongPassword,
      AuthResult.usernameTaken => l.errUsernameTaken,
      AuthResult.notConfirmed => l.errNotConfirmed,
      AuthResult.offline => l.internetNo,
      AuthResult.tooSoon => l.errTooSoon,
      _ => null,
    };
    return AuthLayout(children: [
      Text(_signup ? l.signupTitle : l.loginTitle, key: const Key('loginTitle'), style: AppText.title14),
      const SizedBox(height: 12),
      Text(l.usernameLabel, style: AppText.sm13),
      const SizedBox(height: 6),
      TextField(
        key: const Key('usernameField'),
        controller: _username,
        keyboardType: TextInputType.visiblePassword,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 20,
        style: AppText.body13,
        decoration: InputDecoration(counterText: '', hintText: _signup ? l.usernameRule : null),
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: 10),
      Text(l.passwordLabel, style: AppText.sm13),
      const SizedBox(height: 6),
      TextField(
        key: const Key('passwordField'),
        controller: _password,
        obscureText: !_showPassword,
        autocorrect: false,
        enableSuggestions: false,
        style: AppText.body13,
        decoration: InputDecoration(
          suffixIcon: IconButton(
            key: const Key('passwordToggle'),
            tooltip: _showPassword ? l.hidePassword : l.showPassword,
            icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 20, color: AppColors.t3),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
        onChanged: (_) => setState(() => _error = null),
        onSubmitted: (_) => _submit(),
      ),
      AuthError(error),
      AppButton.primary(
        key: const Key('loginButton'),
        label: _signup ? l.signupButton : l.loginButton,
        onPressed: _busy ? null : _submit,
      ),
      const SizedBox(height: 4),
      AuthLink(key: const Key('toggleMode'), label: _signup ? l.toLogin : l.toSignup, onTap: _toggleMode),
      if (!_signup)
        AuthLink(
          key: const Key('forgotPassword'),
          label: l.forgotPassword,
          onTap: () => setState(() => _showForgot = true),
        ),
      if (!_signup && _showForgot)
        Text(l.forgotPasswordHelp, key: const Key('forgotHelp'), textAlign: TextAlign.center, style: AppText.sm),
    ]);
  }
}
