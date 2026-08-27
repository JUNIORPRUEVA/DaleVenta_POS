import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final businessRegistrationDisabledProvider = Provider<bool>((ref) {
  return isBusinessRegistrationDisabledOnCurrentPlatform;
});

bool get isBusinessRegistrationDisabledOnCurrentPlatform {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}
