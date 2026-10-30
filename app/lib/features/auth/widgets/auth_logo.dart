import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colors.dart';
import '../../../l10n/app_localizations.dart';

/// The header logo (emerald shield) and "BDPay", centered. The header draws the same shield
/// inline; it is repeated here so app_header.dart stays unchanged.
class AuthLogo extends StatelessWidget {
  const AuthLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: AppColors.em, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.shield, size: 18, color: AppColors.onEm),
        ),
        const SizedBox(width: 10),
        Text(AppLocalizations.of(context).headerBrand, style: AppText.logoBrand),
      ],
    );
  }
}
