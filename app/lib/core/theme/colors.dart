import 'package:flutter/painting.dart';

/// Every color used by the app. This is the only file allowed to call Color(.
/// Tokens come from spec 01 (based on the :root block of the reference file).
abstract final class AppColors {
  static const em = Color(0xFF00D09C);
  static const bg = Color(0xFF080D1A);
  static const sf = Color(0xFF10192D);
  static const cd = Color(0xFF17233D);
  static const bd = Color(0xFF233558);
  static const t1 = Color(0xFFF8FAFC);
  static const t2 = Color(0xFFB4C0D3);
  static const t3 = Color(0xFF8A9AB3);
  static const ok = Color(0xFF10B981);
  static const wa = Color(0xFFF59E0B);
  static const er = Color(0xFFEF4444);
  static const info = Color(0xFF38BDF8);

  // Fixed colors from the reference that are not named tokens.
  static const onEm = Color(0xFF080D1A);
  static const rawSmsBg = Color(0xFF090E17);
  static const toastBg = Color(0xFFE2E8F0);
  static const toastText = Color(0xFF0F172A);
  static const switchOffTrack = Color(0xFF1E293B);
  static const switchOffKnob = Color(0xFF94A3B8);
  static const scrim = Color(0x99000000);

  // Operator brand colors and their readable text colors on dark.
  static const bkash = Color(0xFFE2136E);
  static const nagad = Color(0xFFF7941D);
  static const rocket = Color(0xFF8C3494);
  static const upay = Color(0xFF004884);
  static const bkashText = Color(0xFFF0559A);
  static const nagadText = Color(0xFFF9A940);
  static const rocketText = Color(0xFFB565C0);
  static const upayText = Color(0xFF5B9BE6);
}
