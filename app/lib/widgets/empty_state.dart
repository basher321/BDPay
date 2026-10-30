import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The reference .empty block: a big icon, a bold title and a hint.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.hint});

  final String icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: AppText.emptyIcon),
          const SizedBox(height: 6),
          Text(title, style: AppText.title14, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(hint, style: AppText.sm, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
