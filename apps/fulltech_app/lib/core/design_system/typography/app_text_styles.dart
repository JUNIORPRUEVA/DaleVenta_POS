import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'app_typography.dart';

abstract final class FullPOSCloudTextStyles {
  static const screenTitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static const sectionTitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );

  static const subtitle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.35,
    letterSpacing: 0,
    color: AppColors.textSecondary,
  );

  static const tableHeader = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: 0,
    color: AppColors.textSecondary,
  );

  static const money = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0,
    color: AppColors.textPrimary,
  );
}
