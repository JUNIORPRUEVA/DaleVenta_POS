import 'package:daleventa_pos/features/account/apps_downloads_panel.dart';
import 'package:flutter/material.dart';
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
}
