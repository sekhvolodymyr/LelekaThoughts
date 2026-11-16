import 'package:flutter/material.dart';

class LelekaPalette {
  final String id, name;
  final Color canvas,
      background,
      sidebar,
      text,
      muted,
      primary,
      onPrimary,
      accent,
      border;
  final List<Color> gradient;
  const LelekaPalette(
    this.id,
    this.name,
    this.canvas,
    this.background,
    this.sidebar,
    this.text,
    this.muted,
    this.primary,
    this.onPrimary,
    this.accent,
    this.border,
    this.gradient,
  );
  bool get dark => id == 'dark' || id == 'ocean' || id == 'forest';
  ThemeData get theme {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          surface: background,
          onSurface: text,
          onSurfaceVariant: muted,
          outline: border,
          secondaryContainer: accent,
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Inter',
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: background,
        indicatorColor: accent,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: text,
        contentTextStyle: TextStyle(color: background),
      ),
    );
  }

  static const all = <LelekaPalette>[
    LelekaPalette(
      'light',
      'Світла',
      Color(0xfffaf9f6),
      Colors.white,
      Color(0xfff1efeb),
      Color(0xff292824),
      Color(0xff77736d),
      Color(0xffad5943),
      Colors.white,
      Color(0xfff0e1da),
      Color(0xffe7e3dd),
      [Colors.white, Colors.white],
    ),
    LelekaPalette(
      'dark',
      'Темна',
      Color(0xff1b1c1d),
      Color(0xff242527),
      Color(0xff222325),
      Color(0xffefeeeb),
      Color(0xffaaa7a1),
      Color(0xffd98c72),
      Color(0xff171717),
      Color(0xff44312b),
      Color(0xff38393b),
      [Color(0xff242527), Color(0xff242527)],
    ),
    LelekaPalette(
      'sunset',
      'Захід сонця',
      Color(0xfff9e5dc),
      Color(0xfffff7f2),
      Color(0xfff6dfd5),
      Color(0xff432d2b),
      Color(0xff75594e),
      Color(0xff99472f),
      Colors.white,
      Color(0xfff3d1c3),
      Color(0xffe5c8bd),
      [Color(0xfffff8f0), Color(0xfffff0f2)],
    ),
    LelekaPalette(
      'lavender',
      'Лаванда',
      Color(0xffe9e4f7),
      Color(0xfffaf7ff),
      Color(0xffe6def3),
      Color(0xff352c48),
      Color(0xff6d5c7d),
      Color(0xff6943a3),
      Colors.white,
      Color(0xffe3d5f2),
      Color(0xffdacee8),
      [Color(0xfff7f7ff), Color(0xfffff4fb)],
    ),
    LelekaPalette(
      'ocean',
      'Океан',
      Color(0xff102b3c),
      Color(0xff183548),
      Color(0xff153247),
      Color(0xffedf7fb),
      Color(0xffb0cbd7),
      Color(0xff93e0dd),
      Color(0xff102c3f),
      Color(0xff285568),
      Color(0xff36556a),
      [Color(0xff162c45), Color(0xff183d43)],
    ),
    LelekaPalette(
      'forest',
      'Ліс',
      Color(0xff20362e),
      Color(0xff2a4034),
      Color(0xff273d32),
      Color(0xfff0f5e9),
      Color(0xffc0ceb7),
      Color(0xffbbd79b),
      Color(0xff21382d),
      Color(0xff425d43),
      Color(0xff50604d),
      [Color(0xff223b33), Color(0xff2f4436)],
    ),
    LelekaPalette(
      'vyshyvanka',
      'Вишиванка',
      Color(0xfff5efe3),
      Color(0xfffffaf2),
      Color(0xfff3ecdf),
      Color(0xff302b29),
      Color(0xff756355),
      Color(0xffa52a35),
      Colors.white,
      Color(0xfff4dedb),
      Color(0xffdecfbd),
      [Color(0xfff5efe3), Color(0xfff5efe3)],
    ),
  ];
  static LelekaPalette fromId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.first);
}
