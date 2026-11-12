import '../../support/platform_goldens.dart';

import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/preview/sales_ticket_bar_preview.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_ticket_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Finder tab(String label) => find.byWidgetPredicate(
  (widget) => widget is SalesTicketTab && widget.label == label,
);

Widget reducedMotion(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(disableAnimations: true),
  child: child!,
);

Future<void> pumpPreview(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      builder: reducedMotion,
      home: const SalesTicketBarPreview(),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(SalesTicketBarPreview));
    await Future.wait([
      precacheImage(const AssetImage(SalesTicketBar.addIconAsset), context),
      precacheImage(const AssetImage(SalesTicketTab.cartIconAsset), context),
      precacheImage(const AssetImage('assets/image/nuevologo.png'), context),
    ]);
  });
  await tester.pumpAndSettle();
}

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

  testWidgets(
    'el carrito pulsa solo con productos y respeta movimiento reducido',
    (tester) async {
      Future<void> showTicket(int count, {bool reduceMotion = false}) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduceMotion),
              child: Scaffold(
                body: SalesTicketTab(
                  label: 'Ticket',
                  itemCount: count,
                  selected: true,
                  onTap: () {},
                  onRename: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        );
      }

      final pulse = find.byKey(const ValueKey('ticket-activity-pulse'));
      double scale() => tester.widget<Transform>(pulse).transform.entry(0, 0);
      Color? color() =>
          (tester
                      .widget<Container>(
                        find.descendant(
                          of: pulse,
                          matching: find.byType(Container),
                        ),
                      )
                      .decoration!
                  as BoxDecoration)
              .color;

      await showTicket(0);
      expect(pulse, findsNothing);
      expect(
        tester.widget<ImageIcon>(find.byType(ImageIcon)).image,
        const AssetImage(SalesTicketTab.cartIconAsset),
      );
      await showTicket(3);
      final initialScale = scale();
      final initialColor = color();
      await tester.pump(const Duration(milliseconds: 700));
      expect(scale(), greaterThan(initialScale));
      expect(color(), isNot(initialColor));
      await tester.pump(const Duration(milliseconds: 700));
      final peakScale = scale();
      await tester.pump(const Duration(milliseconds: 700));
      expect(scale(), lessThan(peakScale));

      await showTicket(3, reduceMotion: true);
      await tester.pumpAndSettle();
      final staticScale = scale();
      final staticColor = color();
      await tester.pump(const Duration(seconds: 3));
      expect(scale(), staticScale);
      expect(color(), staticColor);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await showTicket(0);
      expect(pulse, findsNothing);
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1280, 720),
    const Size(960, 640),
    const Size(390, 844),
  ]) {
    testWidgets('footer sin desbordamientos en $size', (tester) async {
      await pumpPreview(tester, size);
      expect(tester.widget<SalesTicketTab>(tab('Mostrador')).selected, isTrue);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(find.bySemanticsLabel('Nuevo ticket'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
      final selectedRect = tester.getRect(tab('Mostrador'));
      final barRect = tester.getRect(find.byType(SalesTicketBar));
      final firstRect = tester.getRect(tab('Ticket 1'));
      final lastRect = tester.getRect(tab('Pedido para recoger'));
      final lineRect = tester.getRect(
        find.byKey(const ValueKey('ticket-active-line')),
      );
      expect(barRect.height, 46);
      expect(selectedRect.top, barRect.top);
      expect(selectedRect.bottom, barRect.bottom);
      expect(selectedRect.left, firstRect.right);
      expect(lastRect.left, selectedRect.right);
      expect(lineRect.left, selectedRect.left);
      expect(lineRect.right, selectedRect.right);
      expect(lineRect.top, selectedRect.top);
      expect(lineRect.height, 2);
      final material = tester.widget<Material>(
        find
            .descendant(of: tab('Mostrador'), matching: find.byType(Material))
            .first,
      );
      expect(material.borderRadius, isNull);
      expect(material.shape, isA<Border>());
      if (size.width >= 900) {
        expect(firstRect.left, barRect.left);
        expect(
          tester.getRect(find.byTooltip('Nuevo ticket')).left,
          lastRect.right,
        );
      }
      expect(selectedRect.left, greaterThanOrEqualTo(0));
      expect(
        selectedRect.right,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('Nuevo ticket')).left),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          platformGolden('goldens/sales_ticket_bar_${size.width.toInt()}.png'),
        ),
      );
    });
  }

  testWidgets('seleccionar y crear tickets actualiza la selección', (
    tester,
  ) async {
    await pumpPreview(tester, const Size(1280, 720));
    await tester.tap(
      find
          .descendant(of: tab('Ticket 1'), matching: find.byType(InkWell))
          .first,
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SalesTicketTab>(tab('Ticket 1')).selected, isTrue);
    expect(tester.widget<SalesTicketTab>(tab('Mostrador')).selected, isFalse);
    expect(find.byTooltip('Opciones de Mostrador'), findsNothing);
    expect(find.byTooltip('Opciones de Ticket 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Nuevo ticket'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SalesTicketBar>(find.byType(SalesTicketBar)).ticketCount,
      4,
    );
    expect(tester.widget<SalesTicketTab>(tab('Ticket 4')).selected, isTrue);
  });

  testWidgets('crear sigue accesible con muchos tickets y nombre largo', (
    tester,
  ) async {
    await pumpPreview(tester, const Size(960, 640));
    await tester.tap(find.text('Probar muchos tickets'));
    await tester.pumpAndSettle();
    final createRect = tester.getRect(find.byTooltip('Nuevo ticket'));
    expect(createRect.left, greaterThanOrEqualTo(0));
    expect(createRect.right, lessThanOrEqualTo(960));
    await tester.drag(
      find.descendant(
        of: find.byType(SalesTicketBar),
        matching: find.byType(SingleChildScrollView),
      ),
      const Offset(-4000, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Nuevo ticket'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SalesTicketBar>(find.byType(SalesTicketBar)).ticketCount,
      14,
    );
    final newTicketRect = tester.getRect(tab('Ticket 14'));
    expect(newTicketRect.left, greaterThanOrEqualTo(0));
    expect(newTicketRect.right, lessThanOrEqualTo(createRect.left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opciones editan o eliminan sin seleccionar el ticket por accidente',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: reducedMotion,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SalesTicketTab(
                label: 'Nombre de ticket de prueba bastante largo',
                itemCount: 12,
                selected: true,
                onTap: () => actions.add('select'),
                onRename: () => actions.add('rename'),
                onDelete: () => actions.add('delete'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byTooltip('Opciones de Nombre de ticket de prueba bastante largo'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      expect(actions, ['rename']);
      await tester.tap(
        find.byTooltip('Opciones de Nombre de ticket de prueba bastante largo'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar'));
      await tester.pumpAndSettle();
      expect(actions, ['rename', 'delete']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('la barra admite texto ampliado sin perder el botón de crear', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(960, 640),
            textScaler: TextScaler.linear(1.5),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: SalesTicketBar(
                ticketCount: 2,
                onCreateTicket: () {},
                ticketBuilder: (_, index) => SalesTicketTab(
                  label: 'Ticket con nombre largo $index',
                  itemCount: 100,
                  selected: index == 0,
                  onTap: () {},
                  onRename: () {},
                  onDelete: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Nuevo ticket'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
