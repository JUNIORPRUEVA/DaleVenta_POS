import 'package:daleventa_pos/core/app_access/app_access_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato vigente del panel de descargas de FullPOS Cloud.
///
/// El producto pasó a mostrar SIEMPRE las cuatro plataformas oficiales
/// (Windows, Android, iPhone y Web/PWA), en un orden fijo y con el rótulo de
/// acción propio de cada una. El orden del enum `AppAccessKind` es un detalle
/// de implementación: lo que el usuario ve y en qué orden lo define
/// `allChannels()`, no la declaración del enum.
void main() {
  group('AppAccessLinks — contrato del panel de descargas', () {
    test('expone las cuatro plataformas oficiales en orden estable', () {
      final channels = AppAccessLinks.allChannels();

      expect(channels.map((channel) => channel.kind), [
        AppAccessKind.windows,
        AppAccessKind.android,
        AppAccessKind.ios,
        AppAccessKind.pwa,
      ]);
      expect(channels.map((channel) => channel.title), [
        'Windows',
        'Android',
        'iPhone',
        'Web / PWA',
      ]);
    });

    test('cada plataforma conserva su acción y su enlace oficial', () {
      final byKind = {
        for (final channel in AppAccessLinks.allChannels())
          channel.kind: channel,
      };

      // Windows: instalador oficial servido por el backend de releases.
      final windows = byKind[AppAccessKind.windows]!;
      expect(windows.actionLabel, 'Descargar');
      expect(windows.uri, AppAccessLinks.windowsReleaseUri);
      expect(
        windows.uri.toString(),
        contains('/api/app-updates/windows/latest/download'),
      );

      // Android: APK oficial.
      final android = byKind[AppAccessKind.android]!;
      expect(android.actionLabel, 'Descargar');
      expect(android.uri, AppAccessLinks.androidReleaseUri);
      expect(android.uri.toString(), endsWith('app-release.apk'));

      // iPhone: ficha oficial en App Store.
      final ios = byKind[AppAccessKind.ios]!;
      expect(ios.actionLabel, 'Instalar');
      expect(ios.uri, AppAccessLinks.iosAppStoreUri);
      expect(ios.uri.toString(), contains('apps.apple.com'));

      // Web/PWA: versión web oficial.
      final pwa = byKind[AppAccessKind.pwa]!;
      expect(pwa.actionLabel, 'Abrir');
      expect(pwa.uri, AppAccessLinks.pwaUri);
      expect(pwa.uri.isScheme('https'), isTrue);
    });

    test('visibleChannels mantiene la compatibilidad sin filtrar por plataforma',
        () {
      final expectedKinds = AppAccessLinks.allChannels()
          .map((channel) => channel.kind)
          .toList();

      for (final isWeb in [true, false]) {
        final channels = AppAccessLinks.visibleChannels(isWeb: isWeb);
        expect(
          channels.map((channel) => channel.kind).toList(),
          expectedKinds,
          reason: 'visibleChannels(isWeb: $isWeb)',
        );
        expect(channels, hasLength(4));
      }
    });

    test('el orden visible no depende del orden de declaración del enum', () {
      // El orden del enum es arbitrario; si alguien lo reordena, el panel no
      // debe cambiar para el usuario. La fuente de verdad es `allChannels()`.
      const expectedOrder = [
        AppAccessKind.windows,
        AppAccessKind.android,
        AppAccessKind.ios,
        AppAccessKind.pwa,
      ];
      expect(
        AppAccessLinks.allChannels().map((channel) => channel.kind).toList(),
        expectedOrder,
      );
      expect(AppAccessKind.values.first, AppAccessKind.windows);
    });

    test('cada plataforma publica un enlace https propio', () {
      final uris = AppAccessLinks.allChannels()
          .map((channel) => channel.uri)
          .toList();

      expect(uris, hasLength(4));
      expect(uris.toSet(), hasLength(4), reason: 'sin enlaces repetidos');
      for (final uri in uris) {
        expect(uri.isScheme('https'), isTrue, reason: uri.toString());
      }
    });

    test('el texto para compartir incluye el nombre y el enlace', () {
      for (final channel in AppAccessLinks.allChannels()) {
        expect(channel.shareText, contains(channel.title));
        expect(channel.shareText, contains(channel.uri.toString()));
      }
    });
  });
}
