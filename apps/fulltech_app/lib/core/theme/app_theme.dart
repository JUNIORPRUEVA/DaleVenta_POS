import 'package:flutter/material.dart';

import '../auth/app_role.dart';
import '../design_system/icons/app_icon_sizes.dart';
import '../design_system/typography/app_typography.dart';
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
    final textTheme = AppTypography.textTheme();
    final buttonTextStyle = textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
    );

    return ThemeData(
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      useMaterial3: true,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: const IconThemeData(
        color: Color(0xFF334155),
        size: AppIconSizes.normal,
      ),
      primaryIconTheme: IconThemeData(
        color: branding.primary,
        size: AppIconSizes.navigation,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: const Border(bottom: BorderSide(color: Color(0xFFD3E0E7))),
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF111827),
        ),
        toolbarTextStyle: textTheme.bodyMedium,
        iconTheme: IconThemeData(
          color: branding.primary,
          size: AppIconSizes.navigation,
        ),
        actionsIconTheme: IconThemeData(
          color: branding.primary,
          size: AppIconSizes.navigation,
        ),
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
          fontFamily: AppTypography.fontFamily,
          color: textLightColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          color: Color(0xFF94A3B8),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIconColor: const Color(0xFF64748B),
        suffixIconColor: const Color(0xFF64748B),
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
          textStyle: buttonTextStyle,
          minimumSize: const Size(40, 40),
          iconSize: AppIconSizes.button,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: branding.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          minimumSize: const Size(40, 40),
          iconSize: AppIconSizes.button,
          textStyle: buttonTextStyle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
          textStyle: buttonTextStyle,
          minimumSize: const Size(40, 40),
          iconSize: AppIconSizes.button,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: branding.primary,
          textStyle: buttonTextStyle,
          minimumSize: const Size(40, 40),
          iconSize: AppIconSizes.button,
        ),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyMedium,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: outlineSoft),
          ),
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(Colors.white),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.90),
        selectedItemColor: branding.primary,
        unselectedItemColor: textLightColor,
        elevation: 10,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: surfaceColor.withValues(alpha: 0.96),
        elevation: 8,
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.94),
        selectedIconTheme: IconThemeData(
          color: branding.primary,
          size: AppIconSizes.navigation,
        ),
        unselectedIconTheme: const IconThemeData(
          color: Color(0xFF64748B),
          size: AppIconSizes.navigation,
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: branding.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),

      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: Colors.white.withValues(alpha: 0.96),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? branding.primary : const Color(0xFF64748B),
            size: AppIconSizes.navigation,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelLarge?.copyWith(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
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
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: textTheme.bodyMedium,
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
        titleTextStyle: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: branding.tertiary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        headingRowColor: WidgetStateProperty.all(AppColors.surfaceMuted),
        dividerThickness: 1,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: textTheme.labelSmall?.copyWith(color: Colors.white),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
        ),
        waitDuration: const Duration(milliseconds: 450),
      ),
    );
  }
}
