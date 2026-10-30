import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../widgets/toast.dart';

/// Label on the left, value on the right; optional ⧉ copies the value.
class DetailRow extends StatelessWidget {
  const DetailRow({super.key, required this.label, required this.value, this.copyValue, this.copyKey});

  final String label;
  final String value;

  /// The text to copy; null hides the ⧉ button.
  final String? copyValue;
  final Key? copyKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: AppText.mu12),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppText.body13,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (copyValue != null) ...[
            const SizedBox(width: 6),
            GestureDetector(
              key: copyKey,
              onTap: () async {
                final l = AppLocalizations.of(context);
                await Clipboard.setData(ClipboardData(text: copyValue!));
                if (context.mounted) showToast(context, l.copied);
              },
              child: Text('⧉', style: AppText.body13.copyWith(color: AppColors.em)),
            ),
          ],
        ],
      ),
    );
  }
}
