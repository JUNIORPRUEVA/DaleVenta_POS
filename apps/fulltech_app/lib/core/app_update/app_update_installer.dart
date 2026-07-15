import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_installer_contract.dart';
import 'app_update_installer_stub.dart'
    if (dart.library.io) 'app_update_installer_io.dart'
    as installer_impl;

final appUpdateInstallerProvider = Provider<AppUpdateInstaller>((ref) {
  return installer_impl.createAppUpdateInstaller();
});
