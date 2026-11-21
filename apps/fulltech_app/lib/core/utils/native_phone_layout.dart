import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Native phones only. Narrow desktop/web windows and desktop tablet layouts
/// retain their existing presentation.
bool usesNativePhoneLayout(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      size.shortestSide < 600 &&
      size.width < 900;
}
