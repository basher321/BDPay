import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../data/account_providers.dart';
import '../../../l10n/app_localizations.dart';

/// Rule 12: the privacy sentence and the app version, small and centered.
/// Spec 15: links to the privacy policy and the terms on the site (SITE_URL); hidden when SITE_URL is not set.
class PrivacyFooter extends ConsumerWidget {
  const PrivacyFooter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);
    final privacy = config.sitePage('privacy.html');
    final terms = config.sitePage('terms.html');
    Widget link(String label, Uri url, Key key) => TextButton(
          key: key,
          onPressed: () => ref.read(linkOpenerProvider)(url),
          child: Text(label, style: AppText.mu10.copyWith(color: AppColors.em)),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          Text(l.privacyNote, textAlign: TextAlign.center, style: AppText.mu10),
          if (privacy != null && terms != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                link(l.privacyPolicyLink, privacy, const Key('privacyLink')),
                const SizedBox(width: 8),
                link(l.termsLink, terms, const Key('termsLink')),
              ],
            )
          else
            const SizedBox(height: 4),
          Text(l.appVersionLine(appVersion), key: const Key('appVersion'), style: AppText.mu10),
        ],
      ),
    );
  }
}
