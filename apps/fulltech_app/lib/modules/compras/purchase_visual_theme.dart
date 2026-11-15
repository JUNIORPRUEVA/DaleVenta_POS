import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/provided_action_icon.dart';

/// Shared presentation for every purchase page and its modal routes.
/// Does not change the purchase state, permissions or repository operations.
ThemeData purchaseVisualTheme(BuildContext context) {
  final theme = Theme.of(context);
  const shape = RoundedRectangleBorder();
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: AppColors.border),
  );
  ButtonStyle square(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        shape: const WidgetStatePropertyAll(shape),
        minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      );
  return theme.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    filledButtonTheme: FilledButtonThemeData(
      style: square(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: square(theme.outlinedButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: square(theme.elevatedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: square(theme.textButtonTheme.style),
    ),
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(shape)),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: AppColors.border)),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      shape: shape,
      backgroundColor: AppColors.surface,
      titleTextStyle: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    ),
    bottomSheetTheme: theme.bottomSheetTheme.copyWith(
      shape: shape,
      backgroundColor: AppColors.surface,
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(shape: shape),
    chipTheme: theme.chipTheme.copyWith(
      shape: shape,
      labelStyle: theme.textTheme.labelMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      shape: shape,
      titleTextStyle: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
        color: AppColors.textSecondary,
      ),
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
  );
}

class PurchaseIcon extends StatelessWidget {
  const PurchaseIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final action = switch (icon) {
      Icons.refresh_rounded => ProvidedAction.reload,
      Icons.filter_alt_outlined ||
      Icons.filter_alt_off_outlined => ProvidedAction.filter,
      Icons.search || Icons.search_rounded => ProvidedAction.search,
      Icons.add ||
      Icons.add_rounded ||
      Icons.add_shopping_cart_outlined => ProvidedAction.add,
      Icons.close || Icons.close_rounded => ProvidedAction.close,
      Icons.edit_outlined => ProvidedAction.edit,
      Icons.delete_outline ||
      Icons.delete_outline_rounded => ProvidedAction.delete,
      Icons.receipt_long_outlined => ProvidedAction.order,
      Icons.picture_as_pdf_outlined => ProvidedAction.pdf,
      Icons.send_outlined => ProvidedAction.send,
      Icons.storefront_outlined ||
      Icons.add_business_outlined => ProvidedAction.supplier,
      _ => null,
    };
    return action == null
        ? Icon(icon, size: size, color: color)
        : Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ProvidedActionIcon(action, size: size ?? 20, color: color),
          );
  }
}

Future<T?> showPurchaseDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showDialog<T>(
  context: context,
  builder: (dialogContext) => Theme(
    data: purchaseVisualTheme(dialogContext),
    child: Builder(builder: builder),
  ),
);

Future<T?> showPurchaseSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  Color? backgroundColor,
}) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: showDragHandle,
  isScrollControlled: isScrollControlled,
  useSafeArea: useSafeArea,
  backgroundColor: backgroundColor,
  shape: const RoundedRectangleBorder(),
  builder: (sheetContext) => Theme(
    data: purchaseVisualTheme(sheetContext),
    child: Builder(builder: builder),
  ),
);
