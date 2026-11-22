import 'package:flutter/material.dart';
import '../utils/native_phone_layout.dart';
import '../theme/app_colors.dart';

class MobilePresentationTheme extends StatelessWidget {
  const MobilePresentationTheme({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!usesNativePhoneLayout(context)) return child;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        popupMenuTheme: theme.popupMenuTheme.copyWith(
          shape: const RoundedRectangleBorder(),
        ),
        listTileTheme: theme.listTileTheme.copyWith(
          dense: true,
          minTileHeight: 48,
          minVerticalPadding: 4,
          horizontalTitleGap: 10,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        cardTheme: theme.cardTheme.copyWith(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        dividerTheme: theme.dividerTheme.copyWith(
          color: AppColors.border,
          thickness: 0.5,
          space: 1,
        ),
      ),
      child: child,
    );
  }
}
