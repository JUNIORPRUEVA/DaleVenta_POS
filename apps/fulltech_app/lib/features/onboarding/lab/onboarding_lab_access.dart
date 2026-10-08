import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/product_config.dart';
import '../../../core/models/user_model.dart';

const onboardingLabAuthorizedEmail = 'prueva7@gmail.com';
const onboardingLabAuthorizedCompany = 'prueva7';

final onboardingLabEnabledProvider = Provider<bool>((ref) {
  return ProductConfig.enableOnboardingLab || kDebugMode;
});

bool canAccessOnboardingLab(UserModel? user, {required bool enabled}) {
  if (!enabled) return false;
  if (user == null) return false;
  final email = user.email.trim().toLowerCase();
  final companyName = user.companyName?.trim().toLowerCase();
  final companySlug = user.companySlug?.trim().toLowerCase();
  return email == onboardingLabAuthorizedEmail ||
      companyName == onboardingLabAuthorizedCompany ||
      companySlug == onboardingLabAuthorizedCompany;
}
