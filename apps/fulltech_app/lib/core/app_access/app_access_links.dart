import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppAccessKind { android, pwa, windows }

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
    'https://fullposcloud.fulltechrd.com/downloads/FullPOS-Cloud-Setup-1.0.2-5.exe',
  );

  static final Uri androidReleaseUri = Uri.parse(
    'https://fullposcloud.fulltechrd.com/downloads/fullpos-cloud-android-v1.0.2.apk',
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

    return [_androidChannel, _pwaChannel, _windowsChannel];
  }

  static final AppAccessChannel _androidChannel = AppAccessChannel(
    kind: AppAccessKind.android,
    icon: Icons.android_rounded,
    title: 'App Android',
    status: 'APK para móviles y tablets',
    description:
        'Descarga la app Android para consultar ventas, clientes, inventario y operaciones autorizadas con las mismas credenciales.',
    actionLabel: 'Descargar APK',
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
