import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_button.dart';

/// Spec 13 rule 5: "বিচ্ছিন্ন করুন" explains how to uninstall in Shopify instead of disconnecting.
Future<void> showShopifyDisconnectSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    barrierColor: AppColors.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.bigCard)),
    ),
    builder: (context) {
      final l = AppLocalizations.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
        child: Column(
          key: const Key('shopifyDisconnectSheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.shopifyDisconnect, style: AppText.title16),
            const SizedBox(height: 10),
            Text(l.shopifyDisconnectHow, key: const Key('shopifyDisconnectHow'), style: AppText.body13),
            const SizedBox(height: 16),
            AppButton.primary(
              key: const Key('shopifyDisconnectOk'),
              label: l.okButton,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    },
  );
}
