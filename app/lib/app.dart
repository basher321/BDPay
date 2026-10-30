import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'shell/app_shell.dart';

class BdpayApp extends StatelessWidget {
  const BdpayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('bn'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const AppShell(),
    );
  }
}
