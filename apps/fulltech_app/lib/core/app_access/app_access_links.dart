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

  static List<AppAccessChannel> visibleChannels() {
    final platform = defaultTargetPlatform;
    final mobilePlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;

    if (!kIsWeb && platform == TargetPlatform.windows) {
      return [_androidChannel, _pwaChannel];
    }

    if (!kIsWeb && mobilePlatform) {
      return [_pwaChannel];
    }

    if (kIsWeb && mobilePlatform) {
      return [_pwaChannel];
    }

    return [_androidChannel, _iosChannel, _pwaChannel, _windowsChannel];
  }

  static final AppAccessChannel _androidChannel = AppAccessChannel(
    kind: AppAccessKind.android,
    icon: Icons.android_rounded,
    title: 'App Android',
    status: 'APK para móviles y tablets',
    description:
        'Descarga la app Android para consultar ventas, clientes, inventario y operaciones autorizadas con las mismas credenciales.',
    actionLabel: 'Descargar para Android',
    actionIcon: Icons.download_rounded,
    uri: androidReleaseUri,
  );

  static final AppAccessChannel _pwaChannel = AppAccessChannel(
    kind: AppAccessKind.pwa,
    icon: Icons.language_rounded,
    title: 'App web / PWA',
    status: 'Abrir o instalar desde navegador',
    description:
        'Usa FullPOS Cloud desde el navegador o instala la PWA para trabajar con la misma base de datos en cualquier dispositivo autorizado.',
    actionLabel: 'Abrir PWA',
    actionIcon: Icons.open_in_new_rounded,
    uri: pwaUri,
  );

  static final AppAccessChannel _iosChannel = AppAccessChannel(
    kind: AppAccessKind.ios,
    icon: Icons.phone_iphone_rounded,
    title: 'iPhone',
    status: 'App Store',
    description:
        'Descarga FullPOS Cloud desde la App Store oficial para iPhone.',
    actionLabel: 'Descargar para iPhone',
    actionIcon: Icons.open_in_new_rounded,
    uri: iosAppStoreUri,
  );

  static final AppAccessChannel _windowsChannel = AppAccessChannel(
    kind: AppAccessKind.windows,
    icon: Icons.desktop_windows_rounded,
    title: 'Windows POS',
    status: 'Instalador de escritorio',
    description:
        'Descarga el instalador de Windows para caja, facturación, impresión y trabajo diario del punto de venta.',
    actionLabel: 'Descargar Windows',
    actionIcon: Icons.download_rounded,
    uri: windowsReleaseUri,
  );
}
