import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/colors.dart';
import '../l10n/app_localizations.dart';

/// Spec 13: shown alone when SUPABASE_URL or SUPABASE_ANON_KEY was not given with --dart-define.
class NotConfiguredApp extends StatelessWidget {
  const NotConfiguredApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('bn'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const NotConfiguredScreen(),
    );
  }
}

class NotConfiguredScreen extends StatelessWidget {
  const NotConfiguredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l.appNotConfigured,
            key: const Key('notConfigured'),
            textAlign: TextAlign.center,
            style: AppText.title16.copyWith(color: AppColors.wa),
          ),
        ),
      ),
    );
  }
}
