import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import 'app_icons.dart';
import 'app_icon_sizes.dart';

class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
    this.semanticLabel,
  });

  final AppIconData icon;
  final double? size;
  final Color? color;
  final double? strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final effectiveColor = color ?? iconTheme.color ?? Colors.black;
    final effectiveSize = size ?? iconTheme.size ?? AppIconSizes.normal;

    final child = HugeIcon(
      icon: icon,
      size: effectiveSize,
      color: effectiveColor,
      strokeWidth: strokeWidth,
    );

    if (semanticLabel == null || semanticLabel!.trim().isEmpty) {
      return child;
    }

    return Semantics(label: semanticLabel, child: child);
  }
}
