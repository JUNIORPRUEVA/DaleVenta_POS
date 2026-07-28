import 'package:flutter/material.dart';

import '../design_system/typography/app_typography.dart';
import 'app_colors.dart';

class AppTextStyles {
  const AppTextStyles._();

  static const title = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const subtitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static const body = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  static const small = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12,
    color: AppColors.textSecondary,
  );
}
