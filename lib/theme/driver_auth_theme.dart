import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Светлая тема и токены для экранов входа водителя (макеты iOS-style).
abstract final class DriverAuthColors {
  static const Color background = Color(0xFFFFFFFF);
  static const Color primary = Color(0xFFFF6B44);
  static const Color primaryText = Color(0xFF000000);
  static const Color secondaryText = Color(0xFF8E8E93);
  static const Color border = Color(0xFFE5E5EA);
  static const Color backButtonBorder = Color(0xFFE5E5EA);
  static const Color error = Color(0xFFE53935);
  static const Color buttonDisabledFill = Color(0xFFFFCCBC);
}

abstract final class DriverAuthTheme {
  static ThemeData material() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: DriverAuthColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: DriverAuthColors.primary,
        brightness: Brightness.light,
        primary: DriverAuthColors.primary,
        onPrimary: Colors.white,
        surface: DriverAuthColors.background,
        onSurface: DriverAuthColors.primaryText,
        error: DriverAuthColors.error,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: DriverAuthColors.background,
        foregroundColor: DriverAuthColors.primaryText,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: DriverAuthColors.primaryText,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: DriverAuthColors.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black26,
        height: 72,
        indicatorColor: DriverAuthColors.primary.withValues(alpha: 0.15),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DriverAuthColors.primary, size: 24);
          }
          return IconThemeData(color: DriverAuthColors.secondaryText, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DriverAuthColors.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: DriverAuthColors.secondaryText,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DriverAuthColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  static ThemeData darkMaterial() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF1C1C1E),
      colorScheme: ColorScheme.fromSeed(
        seedColor: DriverAuthColors.primary,
        brightness: Brightness.dark,
        primary: DriverAuthColors.primary,
        onPrimary: Colors.white,
        surface: const Color(0xFF2C2C2E),
        onSurface: Colors.white,
        error: DriverAuthColors.error,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1C1C1E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF2C2C2E),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF2C2C2E),
        surfaceTintColor: Colors.transparent,
        indicatorColor: DriverAuthColors.primary.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DriverAuthColors.primary, size: 24);
          }
          return IconThemeData(color: Colors.grey.shade500, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DriverAuthColors.primary,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DriverAuthColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}
