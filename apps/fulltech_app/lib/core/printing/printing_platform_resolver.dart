import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PrintingPlatform { windows, android, ios, web, other }

class PrintingPlatformCapabilities {
  const PrintingPlatformCapabilities({
    required this.platform,
    required this.supportsWindowsDrivers,
    required this.supportsNetworkEscPos,
    required this.supportsBluetoothEscPos,
    required this.supportsUsbEscPos,
    required this.supportsSystemPrint,
  });

  final PrintingPlatform platform;
  final bool supportsWindowsDrivers;
  final bool supportsNetworkEscPos;
  final bool supportsBluetoothEscPos;
  final bool supportsUsbEscPos;
  final bool supportsSystemPrint;

  bool get isMobile =>
      platform == PrintingPlatform.android || platform == PrintingPlatform.ios;
}

class PrintingPlatformResolver {
  const PrintingPlatformResolver();

  PrintingPlatform get platform {
    if (kIsWeb) return PrintingPlatform.web;
    if (Platform.isWindows) return PrintingPlatform.windows;
    if (Platform.isAndroid) return PrintingPlatform.android;
    if (Platform.isIOS) return PrintingPlatform.ios;
    return PrintingPlatform.other;
  }

  PrintingPlatformCapabilities get capabilities {
    final current = platform;
    return PrintingPlatformCapabilities(
      platform: current,
      supportsWindowsDrivers: current == PrintingPlatform.windows,
      supportsNetworkEscPos:
          current == PrintingPlatform.android ||
          current == PrintingPlatform.ios,
      supportsBluetoothEscPos: current == PrintingPlatform.android,
      supportsUsbEscPos: false,
      supportsSystemPrint:
          current == PrintingPlatform.android ||
          current == PrintingPlatform.ios ||
          current == PrintingPlatform.web ||
          current == PrintingPlatform.windows,
    );
  }
}

final printingPlatformResolverProvider = Provider<PrintingPlatformResolver>(
  (_) => const PrintingPlatformResolver(),
);
