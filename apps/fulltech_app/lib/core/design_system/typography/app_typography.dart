import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';

abstract final class AppTypography {
  static const String fontFamily = 'Manrope';

  static TextTheme textTheme([TextTheme? base]) {
    final seeded = GoogleFonts.manropeTextTheme(
      base ?? ThemeData.light().textTheme,
    );

    return seeded.copyWith(
      displayLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 34,
        fontWeight: FontWeight.w600,
        height: 1.15,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
      headlineLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
      titleLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
      titleMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
      titleSmall: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
      bodyLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.45,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
      bodyMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
        letterSpacing: 0,
        color: AppColors.textPrimary,
      ),
      bodySmall: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.35,
        letterSpacing: 0,
        color: AppColors.textSecondary,
      ),
      labelLarge: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.1,
      ),
      labelMedium: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.1,
      ),
      labelSmall: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.1,
      ),
    );
  }
}
