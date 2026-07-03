import 'package:flutter/material.dart';

class AppColors {
  static const background  = Color(0xFF0D1117);
  static const surface     = Color(0xFF161B22);
  static const surfaceAlt  = Color(0xFF1C2128);
  static const border      = Color(0xFF30363D);
  static const primary     = Color(0xFF14C8A6);
  static const accent      = Color(0xFF22DDB8);
  static const text        = Color(0xFFE6EDF3);
  static const textMuted   = Color(0xFF8B949E);
  static const textDim     = Color(0xFF6E7681);
  static const danger      = Color(0xFFEF5466);
  static const warning     = Color(0xFFF4B740);
  static const success     = Color(0xFF3FB950);
  static const info        = Color(0xFF58A6FF);
  // back-compat aliases
  static const green = success;
  static const amber = warning;
  static const red   = danger;
}

class AppDurations {
  static const fast  = Duration(milliseconds: 150);
  static const base  = Duration(milliseconds: 280);
  static const slow  = Duration(milliseconds: 420);
  static const xslow = Duration(milliseconds: 650);
}

class AppCurves {
  static const spring = Curves.easeOutBack;
  static const smooth = Curves.easeInOutCubic;
  static const sharp  = Curves.easeOut;
  static const elastic = Curves.elasticOut;
}

class AppSpacing {
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 24.0;
  static const xxl = 32.0;
}

class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        surface: AppColors.surface,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      dividerColor: AppColors.border,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      textTheme: const TextTheme(
        displaySmall:  TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 30, letterSpacing: -1.0),
        headlineSmall: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, letterSpacing: -0.5, fontSize: 24),
        titleLarge:    TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, letterSpacing: -0.3, fontSize: 18),
        titleMedium:   TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15),
        titleSmall:    TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
        bodyLarge:     TextStyle(color: AppColors.text, fontSize: 16, height: 1.5),
        bodyMedium:    TextStyle(color: AppColors.text, fontSize: 14, height: 1.4),
        bodySmall:     TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4),
        labelSmall:    TextStyle(color: AppColors.textDim, fontSize: 11, letterSpacing: 0.4, fontWeight: FontWeight.w600),
      ),
    );
  }

  static BoxDecoration cardDecoration({double radius = AppRadius.lg, Color? borderColor}) =>
      BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? AppColors.border),
      );

  static BoxDecoration glowCardDecoration({double radius = AppRadius.lg, Color? glowColor}) =>
      BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: (glowColor ?? AppColors.primary).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: (glowColor ?? AppColors.primary).withValues(alpha: 0.14),
            blurRadius: 24,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration elevatedCardDecoration({double radius = AppRadius.lg}) =>
      BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      );

  static Color severityColor(String status) {
    switch (status) {
      case 'approved': return AppColors.success;
      case 'denied':   return AppColors.danger;
      default:         return AppColors.warning;
    }
  }
}
