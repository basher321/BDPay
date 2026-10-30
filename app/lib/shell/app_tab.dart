import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Bottom tabs. devLab (পরীক্ষা) is shown only in developer mode.
enum AppTab {
  home(Icons.dashboard),
  transactions(Icons.history),
  queue(Icons.cloud),
  devLab(Icons.science),
  settings(Icons.settings);

  const AppTab(this.icon);

  final IconData icon;

  String label(AppLocalizations l) => switch (this) {
        home => l.tabHome,
        transactions => l.tabTransactions,
        queue => l.tabQueue,
        devLab => l.tabDevLab,
        settings => l.tabSettings,
      };
}

/// Tabs in display order for the given developer mode.
List<AppTab> visibleTabs(bool developerMode) => [
      AppTab.home,
      AppTab.transactions,
      AppTab.queue,
      if (developerMode) AppTab.devLab,
      AppTab.settings,
    ];
