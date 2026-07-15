import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../data/whatsapp_instance_repository.dart';
import '../whatsapp_instance_model.dart';

final whatsappNavigationVisibilityProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authStateProvider).user;
  if (user == null) return false;
  if (user.appRole == AppRole.admin) return true;

  try {
    final status = await ref
        .watch(whatsappInstanceRepositoryProvider)
        .getInstanceStatus();
    return needsWhatsappSetup(status);
  } catch (_) {
    // If the app cannot verify the status, keep the entry visible so the user
    // can fix the configuration manually.
    return true;
  }
});

bool needsWhatsappSetup(WhatsappInstanceStatusResponse status) {
  if (!status.exists) return true;
  if (!status.isConnected) return true;
  final instanceName = (status.instanceName ?? '').trim();
  return instanceName.isEmpty;
}
