import 'package:flutter/material.dart';

import '../auth/app_role.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';
import 'role_branding.dart';

class AppTheme {
  static const Color primaryColor = AppColors.primary;
  static const Color secondaryColor = AppColors.secondary;
  static const Color accentColor = AppColors.accent;
  static const Color successColor = AppColors.success;
  static const Color warningColor = AppColors.warning;
  static const Color errorColor = AppColors.error;
  static const Color backgroundColor = AppColors.background;
  static const Color surfaceColor = AppColors.surface;
  static const Color textDarkColor = AppColors.textPrimary;
  static const Color textLightColor = AppColors.textSecondary;

  static ThemeData get light => lightForRole(AppRole.unknown);

  static ThemeData lightForRole(AppRole role) {
    final branding = resolveRoleBranding(role);
    final scheme = ColorScheme.fromSeed(
      seedColor: branding.primary,
      brightness: Brightness.light,
      primary: branding.primary,
      secondary: branding.secondary,
      tertiary: branding.tertiary,
      surface: surfaceColor,
    );

    final elevatedSurface = Color.alphaBlend(
      branding.primary.withValues(alpha: 0.030),
      Colors.white,
    );
    final surfaceHigh = Color.alphaBlend(
      branding.secondary.withValues(alpha: 0.055),
      Colors.white,
    );
    final outlineSoft = Color.alphaBlend(
      branding.tertiary.withValues(alpha: 0.12),
      const Color(0xFFD6E2EC),
    );

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      useMaterial3: true,
      fontFamily: 'Inter',

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: Color(0xFFD3E0E7))),
        centerTitle: false,
        titleTextStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 19,
          color: Color(0xFF111827),
          letterSpacing: 0,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1957E6)),
        actionsIconTheme: const IconThemeData(color: Color(0xFF1957E6)),
      ),

      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.2,
        ),
        titleMedium: AppTextStyles.title,
        bodyLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
          height: 1.35,
        ),
        bodyMedium: AppTextStyles.subtitle,
        bodySmall: AppTextStyles.body,
        labelSmall: AppTextStyles.small,
      ),

      cardTheme: CardThemeData(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 0,
        color: elevatedSurface.withValues(alpha: 0.94),
        surfaceTintColor: Colors.transparent,
        shadowColor: branding.tertiary.withValues(alpha: 0.10),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.92),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outlineSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: outlineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: branding.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: errorColor),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: errorColor, width: 2),
        ),
        labelStyle: const TextStyle(
          color: textLightColor,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: branding.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: branding.primary,
          side: BorderSide(color: branding.primary.withValues(alpha: 0.78)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: branding.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.90),
        selectedItemColor: branding.primary,
        unselectedItemColor: textLightColor,
        elevation: 10,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 12,
        ),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: surfaceColor.withValues(alpha: 0.96),
        elevation: 8,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: branding.primary,
        foregroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      dividerTheme: DividerThemeData(
        color: outlineSoft,
        thickness: 1,
        space: 16,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor.withValues(alpha: 0.98),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: branding.primary,
        disabledColor: AppColors.border,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: branding.primary,
        textColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: branding.tertiary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
