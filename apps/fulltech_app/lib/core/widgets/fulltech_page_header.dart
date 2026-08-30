import 'package:flutter/material.dart';

import 'custom_app_bar.dart';

class FullTechPageHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const FullTechPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onMenuPressed,
    this.actions,
    this.bottom,
    this.trailing,
    this.showDrawerButton = true,
    this.preferDrawerLeading = false,
    this.toolbarHeight,
    this.titleSpacing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onMenuPressed;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? trailing;
  final bool showDrawerButton;
  final bool preferDrawerLeading;
  final double? toolbarHeight;
  final double? titleSpacing;

  @override
  Widget build(BuildContext context) {
    return CustomAppBar(
      title: title,
      subtitle: subtitle,
      onMenuPressed: showDrawerButton ? onMenuPressed : null,
      actions: actions,
      bottom: bottom,
      trailing: trailing,
      showLogo: false,
      showDepartmentLabel: false,
      preferDrawerLeading: preferDrawerLeading,
      toolbarHeight: toolbarHeight,
      titleSpacing: titleSpacing,
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
    (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
  );
}
