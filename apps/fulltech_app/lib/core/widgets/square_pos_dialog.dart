import 'package:flutter/material.dart';

/// Local appearance for POS forms; leaves unrelated dialogs unchanged.
class SquarePosDialog extends StatelessWidget {
  static const double cornerRadius = 1;
  static const corners = BorderRadius.all(Radius.circular(cornerRadius));
  const SquarePosDialog({super.key, required this.child});
  final Widget child;
  static bool active(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SquarePosScope>() != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const shape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: corners),
    );
    final controls = ButtonStyle(
      textStyle: WidgetStatePropertyAll(theme.textTheme.labelLarge),
      visualDensity: VisualDensity.standard,
      shape: shape,
      minimumSize: WidgetStatePropertyAll(Size(0, 44)),
      fixedSize: WidgetStatePropertyAll(Size.fromHeight(44)),
      maximumSize: WidgetStatePropertyAll(Size(double.infinity, 44)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    const border = OutlineInputBorder(borderRadius: corners);
    return _SquarePosScope(
      child: Theme(
        data: theme.copyWith(
          visualDensity: VisualDensity.standard,
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            isDense: true,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            constraints: const BoxConstraints(minHeight: 44),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: border,
            enabledBorder: border.copyWith(
              borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
            ),
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: theme.colorScheme.primary),
            ),
            disabledBorder: border,
            errorBorder: border.copyWith(
              borderSide: BorderSide(color: theme.colorScheme.error),
            ),
            focusedErrorBorder: border.copyWith(
              borderSide: BorderSide(color: theme.colorScheme.error),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: controls.merge(theme.filledButtonTheme.style),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: controls.merge(theme.elevatedButtonTheme.style),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: controls.merge(theme.outlinedButtonTheme.style),
          ),
          textButtonTheme: TextButtonThemeData(
            style: controls.merge(theme.textButtonTheme.style),
          ),
          segmentedButtonTheme: SegmentedButtonThemeData(
            style: controls.copyWith(visualDensity: VisualDensity.standard),
          ),
          iconButtonTheme: const IconButtonThemeData(
            style: ButtonStyle(shape: shape),
          ),
          checkboxTheme: theme.checkboxTheme.copyWith(
            shape: const RoundedRectangleBorder(borderRadius: corners),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _SquarePosScope extends InheritedWidget {
  const _SquarePosScope({required super.child});
  @override
  bool updateShouldNotify(_SquarePosScope oldWidget) => false;
}
