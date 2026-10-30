import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/colors.dart';

OverlayEntry? _current;
Timer? _timer;

/// Shows a short message like the reference #toast, then hides it after 1.8 s.
void showToast(BuildContext context, String message) {
  _timer?.cancel();
  _current?.remove();
  final overlay = Overlay.of(context, rootOverlay: true);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      bottom: 80,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: AppColors.toastBg, borderRadius: BorderRadius.circular(20)),
              child: Text(message, style: AppText.toast),
            ),
          ),
        ),
      ),
    ),
  );
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(const Duration(milliseconds: 1800), () {
    entry.remove();
    if (identical(_current, entry)) _current = null;
  });
}
