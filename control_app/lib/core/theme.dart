import 'package:flutter/material.dart';

/// ألوان من نفس هوية تطبيق خيال (بنفسجي/أرجواني + أصفر ليموني).
class Pal {
  Pal._();
  static const bg = Color(0xFF0D0817);
  static const surface = Color(0xFF1A0F26);
  static const surface2 = Color(0xFF241433);
  static const purple = Color(0xFFB34DE6);
  static const magenta = Color(0xFFAD00BA);
  static const lime = Color(0xFFE7FF14);
  static const ok = Color(0xFF3DDC84);
  static const warn = Color(0xFFFFB74D);
  static const bad = Color(0xFFFF4D4D);

  static const headerGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF3B0A52), Color(0xFF6A1B8F), Color(0xFFAD00BA)],
  );

  static ShapeBorder cardShape([Color? c]) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: (c ?? purple).withOpacity(0.35)),
      );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Pal.purple,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Pal.purple,
    secondary: Pal.lime,
    surface: Pal.surface,
  );
  final radius = BorderRadius.circular(14);
  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Pal.surface,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Pal.surface2,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: Pal.purple.withOpacity(0.25))),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: const BorderSide(color: Pal.purple, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Pal.magenta,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Pal.purple,
        side: BorderSide(color: Pal.purple.withOpacity(0.6)),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Pal.lime,
      foregroundColor: Colors.black,
    ),
  );
}
