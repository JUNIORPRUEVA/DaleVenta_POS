import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> logFullPosRuntimeDiagnostics() async {
  final packageInfo = await PackageInfo.fromPlatform();
  debugPrint('FULLPOS RUNTIME');
  debugPrint('mode=${_buildMode()}');
  debugPrint('version=${packageInfo.version}+${packageInfo.buildNumber}');
  debugPrint('executable=${Platform.resolvedExecutable}');
  debugPrint('startedAt=${DateTime.now().toIso8601String()}');
}

String _buildMode() {
  if (kDebugMode) return 'DEBUG';
  if (kProfileMode) return 'PROFILE';
  if (kReleaseMode) return 'RELEASE';
  return 'UNKNOWN';
}
