import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Stand-in for a tab whose screen comes in a later spec.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(title, style: AppText.h3));
  }
}
