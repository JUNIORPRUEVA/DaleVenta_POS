import 'package:daleventa_pos/features/account/apps_downloads_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPanel(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppsDownloadsPanel())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('muestra las cuatro plataformas oficiales', (tester) async {
    await pumpPanel(tester, const Size(1280, 800));

    expect(find.text('Aplicaciones y descargas'), findsOneWidget);
    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('Android'), findsOneWidget);
    expect(find.text('iPhone'), findsOneWidget);
    expect(find.text('Web / PWA'), findsOneWidget);
    expect(find.text('Descargar'), findsNWidgets(2));
    expect(find.text('Instalar'), findsNWidgets(2));
    expect(find.text('Abrir'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda en pantalla móvil', (tester) async {
    await pumpPanel(tester, const Size(390, 780));

    expect(find.text('Windows'), findsOneWidget);
    expect(find.text('Web / PWA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la columna se ajusta al contenido sin ocupar toda la altura', (
    tester,
  ) async {
    await pumpPanel(tester, const Size(1920, 1080));
    final surface = tester.getRect(
      find.byKey(const ValueKey('apps-downloads-surface')),
    );
    expect(surface.width, 560);
    expect(surface.height, lessThan(700));
    expect(surface.top, 12);
    expect(surface.right, 1908);
    expect(find.textContaining('mismo correo y contraseña'), findsOneWidget);
  });

  testWidgets(
    'la columna permite desplazarse y cerrarse en una pantalla baja',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showGeneralDialog<void>(
                  context: context,
                  pageBuilder: (_, __, ___) => const AppsDownloadsPanel(),
                ),
                child: const Text('Abrir apps'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir apps'));
      await tester.pumpAndSettle();
      final surface = tester.getRect(
        find.byKey(const ValueKey('apps-downloads-surface')),
      );
      expect(surface.bottom, lessThanOrEqualTo(468));
      await tester.ensureVisible(
        find.textContaining('mismo correo y contraseña'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Cerrar'));
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.byType(AppsDownloadsPanel), findsNothing);
    },
  );

  testWidgets('copiar Android entrega la ficha oficial de Google Play', (
    tester,
  ) async {
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpPanel(tester, const Size(1280, 800));
    final android = find.ancestor(
      of: find.text('Android'),
      matching: find.byType(AppsDownloadCard),
    );
    final copy = find.descendant(
      of: android,
      matching: find.byTooltip('Copiar enlace'),
    );
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(
      copied,
      'https://play.google.com/store/apps/details?id=com.daleventa.pos',
    );
    expect(find.text('Google Play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
