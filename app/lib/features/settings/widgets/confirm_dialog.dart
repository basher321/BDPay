import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';

/// A yes / no question with "না" / "হ্যাঁ". Returns true only on "হ্যাঁ".
Future<bool> showConfirmDialog(BuildContext context, String text) async {
  final yes = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return Dialog(
        backgroundColor: AppColors.sf,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, key: const Key('confirmText'), style: AppText.title14),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    key: const Key('confirmNo'),
                    onTap: () => Navigator.of(context).pop(false),
                    child: Text(l.no, style: AppText.title14),
                  ),
                  const SizedBox(width: 24),
                  GestureDetector(
                    key: const Key('confirmYes'),
                    onTap: () => Navigator.of(context).pop(true),
                    child: Text(l.yes, style: AppText.title14.copyWith(color: AppColors.er)),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return yes ?? false;
}
