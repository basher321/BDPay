import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../widgets/app_card.dart';
import 'auth_logo.dart';

/// Shared layout of the login screens: logo on top, then one big card, centered.
class AuthLayout extends StatelessWidget {
  const AuthLayout({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AuthLogo(),
                const SizedBox(height: 24),
                AppCard(
                  big: true,
                  surface: true,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A red error line under a field; empty space keeps the layout still when there is no error.
class AuthError extends StatelessWidget {
  const AuthError(this.text, {super.key});

  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = text;
    if (t == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Text(t, key: const Key('authError'), style: AppText.sm.copyWith(color: AppColors.er)),
    );
  }
}

/// A small emerald text link.
class AuthLink extends StatelessWidget {
  const AuthLink({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.title13.copyWith(color: onTap == null ? AppColors.t3 : AppColors.em),
        ),
      ),
    );
  }
}
