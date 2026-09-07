import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppAccessKind { android, ios, pwa, windows }

class AppAccessChannel {
  const AppAccessChannel({
    required this.kind,
    required this.icon,
    required this.title,
    required this.status,
    required this.description,
    required this.actionLabel,
    required this.actionIcon,
    required this.uri,
  });

  final AppAccessKind kind;
  final IconData icon;
  final String title;
  final String status;
  final String description;
  final String actionLabel;
  final IconData actionIcon;
  final Uri uri;
}

class AppAccessLinks {
  static final Uri pwaUri = Uri.parse('https://fullposcloud.fulltechrd.com/');

  static final Uri windowsReleaseUri = Uri.parse(
    'https://github.com/JUNIORPRUEVA/DaleVenta_POS/releases/download/v1.0.4/FullPOS-Cloud-Setup-1.0.3-7.exe',
  );

  static final Uri androidReleaseUri = Uri.parse(
    'https://github.com/JUNIORPRUEVA/fullpos_cluouds/releases/latest/download/app-release.apk',
  );

  static final Uri iosAppStoreUri = Uri.parse(
    'https://apps.apple.com/do/app/fullpos-cloud/id6801349002',
  );

  static List<AppAccessChannel> visibleChannels({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final runningOnWeb = isWeb ?? kIsWeb;

    if (runningOnWeb) {
      return [_androidChannel, _iosChannel, _windowsChannel];
    }

    return [_androidChannel, _iosChannel];
  }

  static final AppAccessChannel _androidChannel = AppAccessChannel(
    kind: AppAccessKind.android,
    icon: Icons.android_rounded,
    title: 'Android',
    status: 'APK oficial',
    description:
        'Descarga la app Android e inicia sesión con las mismas credenciales de FullPOS Cloud.',
    actionLabel: 'Descargar para Android',
    actionIcon: Icons.download_rounded,
    uri: androidReleaseUri,
  );

  static final AppAccessChannel _iosChannel = AppAccessChannel(
    kind: AppAccessKind.ios,
    icon: Icons.phone_iphone_rounded,
    title: 'iPhone',
    status: 'App Store oficial',
    description:
        'Abre la ficha oficial de FullPOS Cloud en App Store para descargarla en tu iPhone.',
    actionLabel: 'Descargar para iPhone',
    actionIcon: Icons.open_in_new_rounded,
    uri: iosAppStoreUri,
  );

  static final AppAccessChannel _windowsChannel = AppAccessChannel(
    kind: AppAccessKind.windows,
    icon: Icons.desktop_windows_rounded,
    title: 'Windows',
    status: 'Instalador oficial',
    description:
        'Descarga el instalador de Windows para usar FullPOS Cloud en el punto de venta.',
    actionLabel: 'Descargar Windows',
    actionIcon: Icons.download_rounded,
    uri: windowsReleaseUri,
  );
}
