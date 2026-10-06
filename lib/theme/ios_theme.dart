import 'package:flutter/material.dart';

/// FAHD iOS-style design tokens. Single source of truth for color,
/// radius, type and motion — no random colors or radii in widgets.
abstract final class FaColors {
  static const bg = Color(0xFF000000);
  static const group = Color(0xFF1C1C1E);
  static const group2 = Color(0xFF2C2C2E);
  static const sep = Color(0xFF38383A);
  static const blue = Color(0xFF0A84FF);
  static const green = Color(0xFF30D158);
  static const red = Color(0xFFFF453A);
  static const orange = Color(0xFFFF9F0A);
  static const ink = Color(0xFFFFFFFF);
  static const ink2 = Color(0xFF98989D);
  static const ink3 = Color(0xFF636366);
}

abstract final class FaRadii {
  static const card = 14.0;
  static const row = 12.0;
  static const pill = 999.0;
}

abstract final class FaMotion {
  /// Micro-interactions: 150–300ms ease-out.
  static const micro = Duration(milliseconds: 200);
  static const tab = Duration(milliseconds: 250);
  static const toast = Duration(milliseconds: 220);
  static const staggerStep = Duration(milliseconds: 60);
  static const pressScale = 0.96;
  static const curve = Curves.easeOut;
  static const spring = Curves.easeOutBack;
}

ThemeData buildFaTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: FaColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: FaColors.blue,
      secondary: FaColors.orange,
      surface: FaColors.group,
      error: FaColors.red,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: FaColors.group2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FaRadii.row)),
    ),
  );
}
