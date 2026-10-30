import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/colors.dart';

enum AppButtonKind { primary, outline, small }

/// The reference .btn: primary (emerald), outline (.btn.o) or small (.btn.xs).
/// A null [onPressed] shows the disabled look.
class AppButton extends StatelessWidget {
  const AppButton.primary({super.key, required this.label, this.onPressed, this.textColor})
      : kind = AppButtonKind.primary,
        outlined = false;

  const AppButton.outline({super.key, required this.label, this.onPressed, this.textColor})
      : kind = AppButtonKind.outline,
        outlined = true;

  /// Small button; [outlined] picks the outline look instead of emerald.
  const AppButton.small({super.key, required this.label, this.onPressed, this.textColor, this.outlined = false})
      : kind = AppButtonKind.small;

  final String label;
  final VoidCallback? onPressed;
  final Color? textColor;
  final AppButtonKind kind;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final small = kind == AppButtonKind.small;
    final Color bg;
    final Color fg;
    if (!enabled) {
      bg = AppColors.cd;
      fg = AppColors.t3;
    } else if (outlined) {
      bg = AppColors.cd;
      fg = textColor ?? AppColors.t1;
    } else {
      bg = AppColors.em;
      fg = textColor ?? AppColors.onEm;
    }
    final radius = BorderRadius.circular(small ? AppRadius.smallButton : AppRadius.button);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: outlined ? const BorderSide(color: AppColors.bd) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onPressed,
        child: Container(
          height: small ? 30 : null,
          padding: small
              ? const EdgeInsets.symmetric(horizontal: 10)
              : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (small ? AppText.buttonSmall : AppText.button).copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}
