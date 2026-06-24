import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFF14181F);
  static const Color surface = Color(0xFF1B212B);
  static const Color surfaceAlt = Color(0xFF232A36);
  static const Color border = Color(0xFF2E3744);
  static const Color primary = Color(0xFF14C8A6);
  static const Color text = Color(0xFFFFFFFF);
  static const Color textDim = Color(0xFF8C95A6);
  static const Color green = Color(0xFF14C8A6);
  static const Color amber = Color(0xFFF4B740);
  static const Color red = Color(0xFFEF5466);
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.textDim,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? AppColors.primary : AppColors.textDim);
        }),
      ),
      dividerColor: AppColors.border,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          fontSize: 24,
        ),
        titleLarge: TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          fontSize: 18,
        ),
        titleMedium: TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
        bodyMedium: TextStyle(color: AppColors.text, fontSize: 14, height: 1.4),
        bodySmall: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
        labelSmall: TextStyle(
          color: AppColors.textDim,
          fontSize: 11,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Subtle border + soft shadow used for elevated surfaces that aren't a
  /// plain themed [Card] (e.g. composite headers, gauges).
  static BoxDecoration elevatedCardDecoration({double radius = AppRadius.lg}) {
    return BoxDecoration(
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
  }

  static Color severityColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.green;
      case 'denied':
        return AppColors.red;
      default:
        return AppColors.amber;
    }
  }
}
