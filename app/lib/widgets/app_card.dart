import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/colors.dart';

/// The reference .card: normal (cd, radius 14) or big (radius 18, more padding).
/// [surface] uses the darker sf background like .card.s.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.big = false,
    this.surface = false,
    this.color,
    this.borderColor,
    this.padding,
    this.onTap,
  });

  final Widget child;
  final bool big;
  final bool surface;
  final Color? color;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(big ? AppRadius.bigCard : AppRadius.card);
    final card = Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(big ? 16 : 14),
      decoration: BoxDecoration(
        color: color ?? (surface ? AppColors.sf : AppColors.cd),
        border: Border.all(color: borderColor ?? AppColors.bd),
        borderRadius: radius,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: radius, onTap: onTap, child: card),
    );
  }
}
