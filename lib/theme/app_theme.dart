import 'package:flutter/material.dart';

class AppTheme {
  static Color _hex(String value, Color fallback) {
    final normalized = value.trim().replaceFirst('#', '');
    if (normalized.length != 6) return fallback;
    final parsed = int.tryParse('FF$normalized', radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  static ThemeData build({
    required bool pink,
    String fontFamily = 'HarmonyOS Sans SC',
    Map<String, dynamic>? pluginTheme,
  }) {
    final primary = pluginTheme?['primary'] is String
        ? _hex(pluginTheme!['primary'].toString(), pink ? const Color(0xFFF5A9C0) : const Color(0xFF5AAFE3))
        : (pink ? const Color(0xFFF5A9C0) : const Color(0xFF5AAFE3));
    final secondary = pluginTheme?['secondary'] is String
        ? _hex(pluginTheme!['secondary'].toString(), pink ? const Color(0xFFF8C9D7) : const Color(0xFF83C6ED))
        : (pink ? const Color(0xFFF8C9D7) : const Color(0xFF83C6ED));
    final background = pluginTheme?['background'] is String
        ? _hex(pluginTheme!['background'].toString(), pink ? const Color(0xFFFFF5FA) : const Color(0xFFF3FAFF))
        : (pink ? const Color(0xFFFFF5FA) : const Color(0xFFF3FAFF));
    final surface = pluginTheme?['surface'] is String
        ? _hex(pluginTheme!['surface'].toString(), pink ? const Color(0xFFFFFBFD) : const Color(0xFFF7FBFF))
        : (pink ? const Color(0xFFFFFBFD) : const Color(0xFFF7FBFF));
    final border = pluginTheme?['border'] is String
        ? _hex(pluginTheme!['border'].toString(), pink ? const Color(0xFFF4C1D3) : const Color(0xFFB9DFF5))
        : (pink ? const Color(0xFFF4C1D3) : const Color(0xFFB9DFF5));
    final text = pluginTheme?['foreground'] is String
        ? _hex(pluginTheme!['foreground'].toString(), pink ? const Color(0xFF5A4050) : const Color(0xFF25445A))
        : (pink ? const Color(0xFF5A4050) : const Color(0xFF25445A));

    final baseTextTheme = ThemeData.light().textTheme.apply(
      bodyColor: text,
      displayColor: text,
      fontFamily: fontFamily,
      fontFamilyFallback: const ['HarmonyOS Sans SC', 'Microsoft YaHei'],
    );
    final textTheme = baseTextTheme.copyWith(
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w400),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w400,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(fontWeight: FontWeight.w400),
      titleLarge: baseTextTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      titleMedium: baseTextTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      titleSmall: baseTextTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      labelSmall: baseTextTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w400,
      ),
    );

    return ThemeData(
      fontFamily: fontFamily,
      fontFamilyFallback: const ['HarmonyOS Sans SC', 'Microsoft YaHei'],
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: primary,
            brightness: Brightness.light,
          ).copyWith(
            primary: primary,
            onPrimary: Colors.white,
            secondary: secondary,
            onSecondary: text,
            surface: surface,
            onSurface: text,
            primaryContainer: pink
                ? const Color(0xFFFFE2EC)
                : const Color(0xFFDDF1FF),
            onPrimaryContainer: text,
            secondaryContainer: pink
                ? const Color(0xFFFFEEF4)
                : const Color(0xFFE8F6FF),
            onSecondaryContainer: text,
            outline: border,
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        hintStyle: TextStyle(color: text.withOpacity(.55)),
      ),
      textTheme: textTheme,
    );
  }
}
