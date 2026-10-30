import 'package:flutter/material.dart';

import 'colors.dart';

abstract final class AppRadius {
  static const card = 14.0;
  static const bigCard = 18.0;
  static const button = 12.0;
  static const smallButton = 8.0;
}

/// Text styles used across the app, sized like the reference.
abstract final class AppText {
  static const logoBrand = TextStyle(color: AppColors.t1, fontSize: 17, fontWeight: FontWeight.w900);
  static const logoProduct = TextStyle(color: AppColors.em, fontSize: 15, fontWeight: FontWeight.w500);
  static const headerSub = TextStyle(color: AppColors.t3, fontSize: 10);
  static const pill = TextStyle(fontSize: 10, fontWeight: FontWeight.w700);

  static const h3 = TextStyle(color: AppColors.t1, fontSize: 15, fontWeight: FontWeight.w700);
  static const title13 = TextStyle(color: AppColors.t1, fontSize: 13, fontWeight: FontWeight.w700);
  static const title14 = TextStyle(color: AppColors.t1, fontSize: 14, fontWeight: FontWeight.w700);
  static const title16 = TextStyle(color: AppColors.t1, fontSize: 16, fontWeight: FontWeight.w700);
  static const body12 = TextStyle(color: AppColors.t1, fontSize: 12);
  static const body13 = TextStyle(color: AppColors.t1, fontSize: 13, fontWeight: FontWeight.w500);
  static const sm = TextStyle(color: AppColors.t2, fontSize: 11);
  static const sm13 = TextStyle(color: AppColors.t2, fontSize: 13);
  static const mu10 = TextStyle(color: AppColors.t3, fontSize: 10);
  static const mu12 = TextStyle(color: AppColors.t3, fontSize: 12);
  static const label = TextStyle(color: AppColors.t2, fontSize: 12);

  static const amount15 = TextStyle(color: AppColors.em, fontSize: 15, fontWeight: FontWeight.w700);
  static const amount16 = TextStyle(color: AppColors.em, fontSize: 16, fontWeight: FontWeight.w700);
  static const amount28 = TextStyle(color: AppColors.em, fontSize: 28, fontWeight: FontWeight.w700);
  static const amount32 = TextStyle(color: AppColors.em, fontSize: 32, fontWeight: FontWeight.w700);
  static const stat20 = TextStyle(color: AppColors.t1, fontSize: 20, fontWeight: FontWeight.w700);

  static const chip = TextStyle(fontSize: 11, fontWeight: FontWeight.w600);
  static const badge = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);
  static const syncLabel = TextStyle(fontSize: 10, fontWeight: FontWeight.w500);
  static const navBadge = TextStyle(color: AppColors.onEm, fontSize: 10, fontWeight: FontWeight.w700);
  static const nav = TextStyle(color: AppColors.t3, fontSize: 10);
  static const navActive = TextStyle(color: AppColors.em, fontSize: 10, fontWeight: FontWeight.w700);
  static const button = TextStyle(fontSize: 12, fontWeight: FontWeight.w700);
  static const buttonSmall = TextStyle(fontSize: 11, fontWeight: FontWeight.w700);
  static const toast = TextStyle(color: AppColors.toastText, fontSize: 12);
  static const emptyIcon = TextStyle(fontSize: 40);
  static const rawSms = TextStyle(
    color: AppColors.t2,
    fontSize: 11,
    height: 16 / 11,
    fontFamily: 'monospace',
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
    borderSide: const BorderSide(color: AppColors.bd),
  );
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.em,
      onPrimary: AppColors.onEm,
      surface: AppColors.sf,
      onSurface: AppColors.t1,
      error: AppColors.er,
    ),
    textTheme: base.textTheme.apply(bodyColor: AppColors.t1, displayColor: AppColors.t1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.sf,
      hintStyle: const TextStyle(color: AppColors.t3, fontSize: 13),
      contentPadding: const EdgeInsets.all(12),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.em)),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.em),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.sf),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.sf),
  );
}
