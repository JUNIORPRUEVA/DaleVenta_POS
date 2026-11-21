import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../routing/app_navigator.dart';
import '../utils/native_phone_layout.dart';
import 'mobile_action_icon.dart';

const phoneAppBarGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF1957E6), Color(0xFF2F6BFF)],
);

/// Adapts direct AppBars without changing their desktop configuration.
class MobilePageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MobilePageAppBar({super.key, required this.appBar});
  final AppBar appBar;

  @override
  Size get preferredSize => appBar.preferredSize;

  @override
  Widget build(BuildContext context) {
    if (!usesNativePhoneLayout(context)) return appBar;
    return AppBar(
      title: appBar.title,
      centerTitle: appBar.centerTitle,
      titleSpacing: appBar.titleSpacing,
      toolbarHeight: appBar.toolbarHeight,
      leadingWidth: appBar.leadingWidth,
      leading: appBar.leading == null
          ? (appBar.automaticallyImplyLeading
                ? AppNavigator.maybeBackButton(context)
                : null)
          : mobileAppBarAction(appBar.leading!),
      automaticallyImplyLeading: false,
      actions: appBar.actions?.map(mobileAppBarAction).toList(),
      bottom: appBar.bottom,
      elevation: 0,
      scrolledUnderElevation: 0,
      shape: const Border(),
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(gradient: phoneAppBarGradient),
        child: SizedBox.expand(),
      ),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white, size: 20),
      actionsIconTheme: const IconThemeData(color: Colors.white, size: 20),
      titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
      systemOverlayStyle: SystemUiOverlayStyle.light,
      primary: appBar.primary,
      excludeHeaderSemantics: appBar.excludeHeaderSemantics,
      notificationPredicate: appBar.notificationPredicate,
    );
  }
}
