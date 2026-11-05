import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_providers.dart';
import '../data/providers.dart';
import '../data/sync_coordinator.dart';
import '../domain/account_enums.dart';
import '../domain/models/app_settings.dart';
import '../features/auth/business_name_screen.dart';
import '../features/auth/device_limit_screen.dart';
import '../data/device/device_registration.dart';
import '../features/auth/login_screen.dart';
import '../features/dev_lab/dev_lab_screen.dart';
import '../features/home/home_screen.dart';
import '../features/queue/queue_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/transactions/transactions_screen.dart';
import '../l10n/app_localizations.dart';
import 'app_bottom_nav.dart';
import 'app_header.dart';
import 'app_tab.dart';
import '../widgets/toast.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  late final SyncCoordinator _coordinator;

  @override
  void initState() {
    super.initState();
    // Started once for the app's life; it sends waiting items when the internet comes back.
    _coordinator = ref.read(syncCoordinatorProvider)
      ..onAutoSent = (sent) {
        if (mounted) showToast(context, AppLocalizations.of(context).autoSent(sent));
      }
      ..start();
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Turning developer mode off while on পরীক্ষা returns to হোম.
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (_, next) {
      final dev = next.value?.developerMode ?? false;
      if (!dev && ref.read(selectedTabProvider) == AppTab.devLab) {
        ref.read(selectedTabProvider.notifier).select(AppTab.home);
      }
    });
    // Login, business name or the main tabs, depending on AuthState (spec 05).
    final auth = ref.watch(authStateProvider).value;
    switch (auth?.status) {
      case null:
        return const Scaffold();
      case AuthStatus.signedOut:
        return const LoginScreen();
      case AuthStatus.needsBusinessName:
        return const BusinessNameScreen();
      case AuthStatus.signedIn:
        break;
    }
    // Spec 13a: three phones already registered -> a full screen.
    if (ref.watch(registrationStateProvider).value?.status == RegistrationStatus.deviceLimit) {
      return const DeviceLimitScreen();
    }
    final dev = ref.watch(settingsProvider).value?.developerMode ?? false;
    final tabs = visibleTabs(dev);
    final tab = ref.watch(selectedTabProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const AppHeader(),
            Expanded(
              child: switch (tab) {
                AppTab.home => const HomeScreen(),
                AppTab.transactions => const TransactionsScreen(),
                AppTab.queue => const QueueScreen(),
                AppTab.devLab => const DevLabScreen(),
                AppTab.settings => const SettingsScreen(),
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        tabs: tabs,
        selected: tab,
        onSelect: (t) => ref.read(selectedTabProvider.notifier).select(t),
      ),
    );
  }
}
