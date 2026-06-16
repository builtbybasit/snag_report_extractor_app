import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:snag_report_extractor_app/src/theme_mode_provider.dart';
import 'package:snag_report_extractor_app/src/localization/string_hardcoded.dart';
import 'package:snag_report_extractor_app/src/routing/app_routing.dart';

/// Brand / accent colors shared by the theme and the custom UI chrome.
class AppColors {
  // Light theme — vivid blue used across the app bar gradient and primary
  // actions (matches the design mockup).
  static const blue = Color(0xFF2563EB);
  static const blueDark = Color(0xFF1D4FD7);

  // Dark theme — gold accent on near-black surfaces.
  static const gold = Color(0xFFEDC57E);
  static const goldHover = Color(0xFFD9B06B);
  static const goldLight = Color(0xFFF5D08A);

  static const bg = Color(0xFF050505);
  static const surface = Color(0xFF0A0A0A);
  static const surfaceElevated = Color(0xFF111111);
  static const border = Color(0xFF232323);

  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA0A0A0);
  static const textMuted = Color(0xFF6E6E6E);
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      routerConfig: goRouter,
      debugShowCheckedModeBanner: false,
      restorationScopeId: 'app',
      onGenerateTitle: (BuildContext context) => "Snag Report Extractor".hardcoded,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: GoogleFonts.inter().fontFamily,
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.blue,
              brightness: Brightness.light,
            ).copyWith(
              primary: AppColors.blue,
              primaryContainer: const Color(0xFFE7EDFD),
              surface: Colors.white,
              onSurface: const Color(0xFF1A1D23),
              error: Colors.red.shade600,
              onError: Colors.white,
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: GoogleFonts.inter().fontFamily,
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: AppColors.gold,
              brightness: Brightness.dark,
            ).copyWith(
              primary: AppColors.gold,
              onPrimary: Colors.black,
              primaryContainer: AppColors.surfaceElevated,
              onPrimaryContainer: AppColors.goldLight,
              surface: AppColors.surface,
              surfaceContainerHighest: AppColors.surfaceElevated,
              onSurface: AppColors.text,
              onSurfaceVariant: AppColors.textSecondary,
              outline: AppColors.border,
              error: Colors.red.shade400,
              onError: Colors.black,
            ),
        dividerColor: AppColors.border,
        cardColor: AppColors.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.text,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: Colors.black,
          ),
        ),
      ),
      themeMode: themeMode,
    );
  }
}
