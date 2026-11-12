import '../../support/platform_goldens.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/preview/sales_detail_panel_preview.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_detail_header.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_detail_shortcut.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_ticket_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/modules/clientes/application/clientes_controller.dart';
import 'package:daleventa_pos/modules/clientes/cliente_form_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_client_selector.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_catalog_command_bar.dart';

Future<void> pumpPanel(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        clientesControllerProvider.overrideWith(
          (ref) => SalesPreviewClientsController(ref),
        ),
        companySettingsProvider.overrideWith(
          (ref) async =>
              CompanySettings.empty().copyWith(measurementUnitsEnabled: true),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const SalesDetailPanelPreview(),
      ),
    ),
  );
  await tester.runAsync(() async {
    final context = tester.element(find.byType(SalesDetailPanelPreview));
    await Future.wait([
      for (final asset in [
        'assets/image/nuevologo.png',
        SalesDetailShortcut.calculatorAsset,
        SalesDetailShortcut.salesAsset,
        SalesTicketTab.cartIconAsset,
        SalesTicketBar.addIconAsset,
        SalesCatalogCommandBar.searchAsset,
      ])
        precacheImage(AssetImage(asset), context),
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
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'detalle mantiene ancho útil en ventanas pequeñas sin exceder el disponible',
    () {
      expect(salesDetailPanelWidth(1108), 480);
      expect(salesDetailPanelWidth(1868), 550);
      expect(salesDetailPanelWidth(844), 480);
      expect(salesDetailPanelWidth(400), 400);
    },
  );

  for (final size in [
    const Size(1920, 1080),
    const Size(1280, 800),
    const Size(960, 720),
    const Size(900, 720),
  ]) {
    testWidgets('panel real y totales conservados en $size', (tester) async {
      await pumpPanel(tester, size);
      final panel = find.byType(DesktopSalesDetailPanel);
      expect(
        tester.getSize(panel).width,
        closeTo(salesDetailPanelWidth(size.width - 56), 0.01),
      );
      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Mayoreo'), findsOneWidget);
      expect(find.text('Comprobante'), findsOneWidget);
      expect(find.byTooltip('Guardar cotización'), findsOneWidget);
      expect(find.byTooltip('Agregar nota'), findsOneWidget);
      expect(find.byTooltip('Ver PDF'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Utilidad'), findsOneWidget);
      expect(tester.getSize(find.byTooltip('Calculadora')), const Size(40, 64));
      expect(tester.getSize(find.byTooltip('Ventas')), const Size(70, 64));
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'Cobrar')).height,
        64,
      );
      expect(
        tester
            .getSize(
              find
                  .descendant(
                    of: find.widgetWithText(FilledButton, 'Cobrar'),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .height,
        64,
      );
      expect(find.text('Factura actual'), findsOneWidget);
      final clientEditable = find.descendant(
        of: find.byType(SalesClientSelector),
        matching: find.byType(EditableText),
      );
      expect(
        tester.getCenter(clientEditable).dy,
        closeTo(tester.getCenter(find.text('Cliente')).dy, 0.5),
      );
      expect(
        tester.getSize(find.byType(SalesDetailHeader)).height,
        lessThan(150),
      );
      expect(
        tester.getRect(find.text('Mayoreo')).top,
        lessThan(tester.getRect(find.text('Cliente')).top),
      );
      expect(
        tester.getRect(find.text('Mayoreo')).top,
        tester.getRect(find.text('Comprobante')).top,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Productos y descuento'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Descuento:'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final header = tester.widget<SalesDetailHeader>(
        find.byType(SalesDetailHeader),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: const ValueKey('header-golden'),
              child: SizedBox(
                width: salesDetailPanelWidth(size.width - 56),
                child: header,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('header-golden')),
        matchesGoldenFile(
          platformGolden(
            'goldens/sales_detail_header_${size.width.toInt()}.png',
          ),
        ),
      );
    });
  }

  testWidgets(
    'crear desde el selector abre el formulario real y selecciona el resultado',
    (tester) async {
      await pumpPanel(tester, const Size(1280, 800));
      await tester.tap(find.byTooltip('Crear cliente'));
      await tester.pumpAndSettle();
      expect(find.byType(ClienteFormScreen), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Cliente creado en vista previa',
      );
      await tester.tap(find.text('Guardar').last);
      await tester.pumpAndSettle();
      expect(find.byType(ClienteFormScreen), findsNothing);
      expect(find.text('Cliente creado en vista previa'), findsOneWidget);
      expect(find.byTooltip('Quitar cliente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cliente, comprobante, mayoreo y cantidades conservan sus acciones',
    (tester) async {
      await pumpPanel(tester, const Size(1280, 800));
      await tester.tap(
        find.descendant(
          of: find.byType(SalesClientSelector),
          matching: find.byType(TextField),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Distribuidora de productos y servicios del Caribe'),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Quitar cliente'), findsOneWidget);
      expect(
        find.byTooltip(
          'Distribuidora de productos y servicios del Caribe · 809 555 0100',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Tipo de factura: Factura normal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fiscal · B01'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Tipo de factura: Fiscal · B01'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mayorista').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String?>>(
              find.byType(DropdownButton<String?>),
            )
            .value,
        'mayoreo',
      );
      await tester.tap(find.byTooltip('Sumar unidad'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DesktopSalesDetailPanel>(
              find.byType(DesktopSalesDetailPanel),
            )
            .items
            .single
            .qty,
        2,
      );
      await tester.tap(find.byTooltip('Quitar cliente'));
      await tester.pumpAndSettle();
      expect(find.text('Seleccionar cliente'), findsOneWidget);
      await tester.tap(find.text('Alternar opciones'));
      await tester.pumpAndSettle();
      expect(find.text('Mayoreo'), findsNothing);
      expect(find.text('Comprobante'), findsNothing);
      await tester.tap(find.text('Venta vacía'));
      await tester.pumpAndSettle();
      expect(find.text('Agrega productos desde el catálogo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('texto ampliado y nombres largos caben en el panel estrecho', (
    tester,
  ) async {
    await pumpPanel(tester, const Size(900, 800), textScale: 1.4);
    await tester.tap(find.text('Productos y descuento'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SalesClientSelector),
        matching: find.byType(TextField),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Distribuidora de productos y servicios del Caribe'),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
