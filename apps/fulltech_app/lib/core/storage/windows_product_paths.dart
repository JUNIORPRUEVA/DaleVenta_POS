import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum WindowsProductFolder { app, databases, backups, mediaCache, logs, config }

class WindowsProductPaths {
  WindowsProductPaths._();

  static const productName = 'DaleVentas POS';
  static const overrideRootEnv = 'DALEVENTAS_POS_ROOT';

  static bool get isOfficialWindowsStorageEnabled {
    if (kIsWeb || !Platform.isWindows) return false;
    if (_overrideRoot().isNotEmpty) return true;
    return kReleaseMode;
  }

  static Directory? productRoot() {
    if (kIsWeb || !Platform.isWindows) return null;

    final override = _overrideRoot();
    if (override.isNotEmpty) return Directory(override);
    if (!kReleaseMode) return null;

    final programFiles = (Platform.environment['ProgramFiles'] ?? '').trim();
    final base = programFiles.isEmpty ? r'C:\Program Files' : programFiles;
    return Directory(p.join(base, productName));
  }

  static Directory? folder(WindowsProductFolder folder) {
    final root = productRoot();
    if (root == null) return null;
    return Directory(p.join(root.path, _folderName(folder)));
  }

  static String pathForRoot(String root, WindowsProductFolder folder) {
    return p.join(root, _folderName(folder));
  }

  static String _overrideRoot() {
    return (Platform.environment[overrideRootEnv] ?? '').trim();
  }

  static String _folderName(WindowsProductFolder folder) {
    return switch (folder) {
      WindowsProductFolder.app => 'app',
      WindowsProductFolder.databases => 'databases',
      WindowsProductFolder.backups => 'backups',
      WindowsProductFolder.mediaCache => 'media_cache',
      WindowsProductFolder.logs => 'logs',
      WindowsProductFolder.config => 'config',
    };
  }
}
