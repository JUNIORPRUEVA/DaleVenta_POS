import 'package:flutter/material.dart';
import '../utils/native_phone_layout.dart';

String? mobileActionAsset(IconData? icon) {
  if ({
    Icons.search,
    Icons.search_rounded,
    Icons.search_outlined,
    Icons.search_sharp,
  }.contains(icon)) {
    return 'assets/image/mobile_navigation/search.png';
  }
  if ({
    Icons.filter_alt,
    Icons.filter_alt_outlined,
    Icons.filter_alt_rounded,
    Icons.filter_alt_sharp,
    Icons.filter_list,
    Icons.filter_list_rounded,
    Icons.filter_list_outlined,
    Icons.filter_list_sharp,
  }.contains(icon)) {
    return 'assets/image/mobile_navigation/filter.png';
  }
  if ({
    Icons.refresh,
    Icons.refresh_rounded,
    Icons.refresh_outlined,
    Icons.refresh_sharp,
  }.contains(icon)) {
    return 'assets/image/mobile_navigation/refresh.png';
  }
  if ({
    Icons.arrow_back,
    Icons.arrow_back_rounded,
    Icons.arrow_back_outlined,
    Icons.arrow_back_sharp,
    Icons.arrow_back_ios,
    Icons.arrow_back_ios_new,
    Icons.arrow_back_ios_new_rounded,
    Icons.arrow_back_ios_rounded,
  }.contains(icon)) {
    return 'assets/image/mobile_navigation/back.png';
  }
  return null;
}

/// Preserves the original Icon and its styling outside native phone layouts.
class MobileActionIcon extends StatelessWidget {
  const MobileActionIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.applyTextScaling,
    this.blendMode,
    this.fontWeight,
  });
  final IconData? icon;
  final double? size, fill, weight, grade, opticalSize;
  final Color? color;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final bool? applyTextScaling;
  final BlendMode? blendMode;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final asset = usesNativePhoneLayout(context)
        ? mobileActionAsset(icon)
        : null;
    if (asset == null) {
      return Icon(
        icon,
        size: size,
        color: color,
        fill: fill,
        weight: weight,
        grade: grade,
        opticalSize: opticalSize,
        shadows: shadows,
        semanticLabel: semanticLabel,
        textDirection: textDirection,
        applyTextScaling: applyTextScaling,
        blendMode: blendMode,
        fontWeight: fontWeight,
      );
    }
    final theme = IconTheme.of(context);
    final dimension = size ?? theme.size ?? 24;
    return Center(
      widthFactor: 1,
      heightFactor: 1,
      child: SizedBox.square(
        dimension: (applyTextScaling ?? theme.applyTextScaling ?? false)
            ? MediaQuery.textScalerOf(context).scale(dimension)
            : dimension,
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          color: color ?? theme.color,
          colorBlendMode: blendMode ?? BlendMode.srcIn,
          semanticLabel: semanticLabel,
          excludeFromSemantics: semanticLabel == null,
        ),
      ),
    );
  }
}

/// Conditional IconButtons (search/close, etc.) keep their original callbacks.
Widget mobileAppBarAction(Widget widget) {
  if (widget is BackButton) {
    return Builder(
      builder: (context) => IconButton(
        tooltip: 'Regresar',
        color: widget.color,
        onPressed: widget.onPressed ?? () => Navigator.maybePop(context),
        icon: const MobileActionIcon(Icons.arrow_back_rounded),
      ),
    );
  }
  if (widget is! IconButton || widget.icon is! Icon) return widget;
  final icon = widget.icon as Icon;
  if (mobileActionAsset(icon.icon) == null) return widget;
  return IconButton(
    key: widget.key,
    icon: MobileActionIcon(
      icon.icon,
      size: icon.size,
      color: icon.color,
      semanticLabel: icon.semanticLabel,
    ),
    onPressed: widget.onPressed,
    tooltip: widget.tooltip,
    onLongPress: widget.onLongPress,
    iconSize: widget.iconSize,
    color: widget.color,
    disabledColor: widget.disabledColor,
    padding: widget.padding,
    alignment: widget.alignment,
    constraints: widget.constraints,
    style: widget.style,
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    enableFeedback: widget.enableFeedback,
    isSelected: widget.isSelected,
    selectedIcon: widget.selectedIcon,
    mouseCursor: widget.mouseCursor,
    visualDensity: widget.visualDensity,
  );
}
