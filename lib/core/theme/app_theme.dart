import 'package:flutter/material.dart';

class AppTheme {
  static const Color keepYellow = Color(0xFFFBBC04);
  static const Color keepDarkSurface = Color(0xFF202124);
  static const Color keepDarkBackground = Color(0xFF17181B);
  static const Color keepLightBackground = Color(0xFFFFFFFF);
  static const Color keepLightSearchSurface = Color(0xFFF1F3F4);
  static const Color keepDarkSearchSurface = Color(0xFF2D2E33);

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: keepYellow,
      brightness: Brightness.light,
      surface: keepLightBackground,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: keepLightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: keepLightBackground,
        foregroundColor: Color(0xFF202124),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFFFFFFFF),
        foregroundColor: const Color(0xFF202124),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomAppBarTheme: const BottomAppBarThemeData(
        color: Color(0xFFF1F3F4),
        elevation: 2,
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: keepYellow,
      brightness: Brightness.dark,
      surface: keepDarkSurface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: keepDarkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: keepDarkBackground,
        foregroundColor: Color(0xFFE8EAED),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF303134),
        foregroundColor: const Color(0xFFE8EAED),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomAppBarTheme: const BottomAppBarThemeData(
        color: Color(0xFF28292C),
        elevation: 2,
      ),
    );
  }
}
