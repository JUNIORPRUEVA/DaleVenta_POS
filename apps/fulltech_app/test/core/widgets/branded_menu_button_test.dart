import '../../support/platform_goldens.dart';

import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_dock_button.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/branded_menu_button.dart';
import 'package:daleventa_pos/core/widgets/fulltech_page_header.dart';
import 'package:daleventa_pos/core/widgets/preview/branded_menu_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final size in [
    const Size(1280, 720),
    const Size(390, 844),
    const Size(320, 640),
  ]) {
    testWidgets('preview de marca y menú en $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const BrandedMenuPreview(),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(BrandedMenuPreview));
        await Future.wait([
          precacheImage(
            const AssetImage('assets/image/nuevologo.png'),
            context,
          ),
          precacheImage(
            const AssetImage(AiAssistantDockButton.imageAsset),
            context,
          ),
        ]);
      });
      await tester.pumpAndSettle();
      expect(find.text('Facturación'), findsNothing);
      expect(find.text('FullPOS'), findsNothing);
      expect(find.text('Menú principal'), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byTooltip('Abrir menú principal'), findsOneWidget);
      expect(
        tester.getSize(find.byType(AiAssistantDockButton)),
        const Size(64, 64),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          platformGolden('goldens/branded_menu_${size.width.toInt()}.png'),
        ),
      );
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
        isFalse,
      );
    });
  }

  testWidgets('el acceso de marca se activa con teclado', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(child: BrandedMenuButton(onPressed: () => opened++)),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('la cabecera real sustituye el título y conserva sus acciones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            drawer: const Drawer(child: Text('Contenido del menú')),
            appBar: FullTechPageHeader(
              title: 'Facturación',
              brandMenu: true,
              preferDrawerLeading: true,
              actions: [
                IconButton(onPressed: () {}, icon: const Icon(Icons.sync)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Facturación'), findsNothing);
    expect(find.byType(BrandedMenuButton), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    await tester.tap(find.byType(BrandedMenuButton));
    await tester.pumpAndSettle();
    expect(
      tester.state<ScaffoldState>(find.byType(Scaffold)).isDrawerOpen,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
