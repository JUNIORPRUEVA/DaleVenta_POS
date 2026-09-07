import 'package:daleventa_pos/core/app_access/app_access_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web/PWA shows mobile store links and Windows installer', () {
    final channels = AppAccessLinks.visibleChannels(isWeb: true);

    expect(channels.map((channel) => channel.kind), [
      AppAccessKind.android,
      AppAccessKind.ios,
      AppAccessKind.windows,
    ]);
    expect(channels.map((channel) => channel.actionLabel), [
      'Descargar para Android',
      'Descargar para iPhone',
      'Descargar Windows',
    ]);
  });

  test('native app shows only Android and iPhone download options', () {
    final channels = AppAccessLinks.visibleChannels(isWeb: false);

    expect(channels.map((channel) => channel.kind), [
      AppAccessKind.android,
      AppAccessKind.ios,
    ]);
  });
}
