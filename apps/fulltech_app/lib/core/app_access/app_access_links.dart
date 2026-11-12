import 'package:flutter/material.dart';

import '../config/product_config.dart';

enum AppAccessKind { windows, android, ios, pwa }

/// Canal oficial de descarga/uso de FullPOS Cloud en una plataforma.
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

  /// Etiqueta corta del formato de entrega (por ejemplo `Instalador oficial`).
  final String status;
  final String description;

  /// Etiqueta de la acción principal: Descargar / Instalar / Abrir.
  final String actionLabel;
  final IconData actionIcon;
  final Uri uri;

  /// Texto listo para compartir el enlace oficial de la plataforma.
  String get shareText => 'FullPOS Cloud para $title: ${uri.toString()}';
}

class AppAccessLinks {
  static final Uri pwaUri = Uri.parse('https://fullposcloud.fulltechrd.com/');

  static final Uri windowsReleaseUri = Uri.parse(
    '${ProductConfig.productionApiBaseUrl}/api/app-updates/windows/latest/download',
  );

  static final Uri androidReleaseUri = Uri.parse(
    'https://github.com/JUNIORPRUEVA/fullpos_cluouds/releases/latest/download/app-release.apk',
  );

  static final Uri iosAppStoreUri = Uri.parse(
    'https://apps.apple.com/do/app/fullpos-cloud/id6801349002',
  );

  /// Las cuatro plataformas oficiales, siempre en el mismo orden.
  static List<AppAccessChannel> allChannels() => [
    _windowsChannel,
    _androidChannel,
    _iosChannel,
    _pwaChannel,
  ];

  /// Compatibilidad: el panel de descargas muestra todas las plataformas.
  static List<AppAccessChannel> visibleChannels({
    bool? isWeb,
    TargetPlatform? platform,
  }) => allChannels();

  static final AppAccessChannel _windowsChannel = AppAccessChannel(
    kind: AppAccessKind.windows,
    icon: Icons.desktop_windows_rounded,
    title: 'Windows',
    status: 'Instalador oficial',
    description: 'Descarga e instala FullPOS Cloud en tu computadora.',
    actionLabel: 'Descargar',
    actionIcon: Icons.download_rounded,
    uri: windowsReleaseUri,
  );

  static final AppAccessChannel _androidChannel = AppAccessChannel(
    kind: AppAccessKind.android,
    icon: Icons.android_rounded,
    title: 'Android',
    status: 'APK oficial',
    description: 'Descarga la aplicación oficial para Android.',
    actionLabel: 'Descargar',
    actionIcon: Icons.download_rounded,
    uri: androidReleaseUri,
  );

  static final AppAccessChannel _iosChannel = AppAccessChannel(
    kind: AppAccessKind.ios,
    icon: Icons.phone_iphone_rounded,
    title: 'iPhone',
    status: 'App Store oficial',
    description: 'Instala FullPOS Cloud desde App Store.',
    actionLabel: 'Instalar',
    actionIcon: Icons.open_in_new_rounded,
    uri: iosAppStoreUri,
  );

  static final AppAccessChannel _pwaChannel = AppAccessChannel(
    kind: AppAccessKind.pwa,
    icon: Icons.public_rounded,
    title: 'Web / PWA',
    status: 'Versión web oficial',
    description:
        'Utiliza FullPOS Cloud desde el navegador o instala su versión web.',
    actionLabel: 'Abrir',
    actionIcon: Icons.open_in_new_rounded,
    uri: pwaUri,
  );
}
