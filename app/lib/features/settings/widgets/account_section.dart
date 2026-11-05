import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../core/validators.dart';
import '../../../data/account_providers.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';
import '../../../widgets/toast.dart';
import '../settings_rules.dart';
import 'confirm_dialog.dart';
import 'settings_section.dart';

/// Rule 11: business name, username and logout (blocked while any SMS is not on the server).
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final waiting = logoutBlockedCount(ref.read(transactionsProvider).value ?? const []);
    if (waiting > 0) {
      showToast(context, l.logoutBlocked(waiting));
      return;
    }
    if (!await showConfirmDialog(context, l.logoutConfirm)) return;
    // Spec 13a: a registered phone is deactivated on the server first; no internet -> blocked.
    final pipeline = ref.read(pipelineRepositoryProvider);
    final state = ref.read(pipelineStateProvider).value;
    if (state != null && state.active) {
      if (!await pipeline.deactivateDevice()) {
        if (context.mounted) showToast(context, l.logoutNeedsInternet);
        return;
      }
    }
    // Always: clears deviceId and stops catching SMS until the next sign-in (plan 13a D171).
    await pipeline.clearDeviceConfig();
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final auth = ref.watch(authStateProvider).value;
    Widget row(String label, String value, Key key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.sm13)),
            Flexible(
              child: Text(value, key: key, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.title13),
            ),
          ]),
        );
    return SettingsSection(
      key: const Key('accountSection'),
      title: l.accountTitle,
      children: [
        row(l.businessNameLabel, auth?.merchant?.businessName ?? '—', const Key('accountBusinessName')),
        row(l.usernameLabel, auth?.email == null ? '—' : usernameOf(auth!.email!), const Key('accountUsername')),
        const SizedBox(height: 10),
        AppButton.outline(
          key: const Key('logoutButton'),
          label: l.logout,
          textColor: AppColors.er,
          onPressed: () => _logout(context, ref),
        ),
      ],
    );
  }
}
