import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/colors.dart';
import '../../../../l10n/app_localizations.dart';

/// "মূল এসএমএস": the raw SMS as plain, selectable, wrapping text. SMS text is untrusted,
/// so it is never parsed as markup.
class RawSmsBox extends StatelessWidget {
  const RawSmsBox({super.key, required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppLocalizations.of(context).rawSmsTitle, style: AppText.title13),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.rawSmsBg,
            border: Border.all(color: AppColors.bd),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(body, key: const Key('rawSms'), style: AppText.rawSms),
        ),
      ],
    );
  }
}
