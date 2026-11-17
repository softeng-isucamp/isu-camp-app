import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared defaults for new controls; screen-specific artwork stays local.
abstract final class AppTheme {
  static const green = Color(0xFF0F5A28);
  static const gold = Color(0xFFECC700);
  static const controlSize = 48.0;
  static const radius = 14.0;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(seedColor: green).copyWith(
      primary: green,
      secondary: gold,
      onSecondary: const Color(0xFF0B351E),
      surface: Colors.white,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    );
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
      shape: WidgetStatePropertyAll(buttonShape),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: GoogleFonts.montserratTextTheme(),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}
