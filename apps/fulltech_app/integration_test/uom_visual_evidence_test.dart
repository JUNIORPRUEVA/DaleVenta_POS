import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = const String.fromEnvironment('UOM_UAT_EMAIL').isNotEmpty
      ? const String.fromEnvironment('UOM_UAT_EMAIL')
      : (Platform.environment['UOM_UAT_EMAIL'] ?? '');
  final password = const String.fromEnvironment('UOM_UAT_PASSWORD').isNotEmpty
      ? const String.fromEnvironment('UOM_UAT_PASSWORD')
      : (Platform.environment['UOM_UAT_PASSWORD'] ?? '');
  final outDir = const String.fromEnvironment(
    'UOM_UAT_SCREENSHOT_DIR',
    defaultValue: '../../docs/uom-visual-evidence',
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = Directory(outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await tester.pump(const Duration(milliseconds: 300));
    final renderView = binding.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = renderView.layer! as OffsetLayer;
    final image = await layer.toImage(renderView.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  }

  Future<void> go(WidgetTester tester, String route) async {
    final context = appRootNavigatorKey.currentContext;
    expect(context, isNotNull, reason: 'App navigator context is available');
    GoRouter.of(context!).go(route);
    await settle(tester);
  }

  Future<void> login(WidgetTester tester) async {
    await settle(tester);
    if (find.text('Iniciar sesion').evaluate().isEmpty) {
      await go(tester, Routes.login);
    }
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email corporativo').first,
      email,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contrasena').first,
      password,
    );
    await tester.tap(find.text('Iniciar sesion').first);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
  }

  Future<void> tapIfVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) return;
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await settle(tester);
  }

  testWidgets('captures real UoM visual evidence on Windows', (tester) async {
    expect(email, isNotEmpty, reason: 'Pass UOM_UAT_EMAIL via --dart-define');
    expect(
      password,
      isNotEmpty,
      reason: 'Pass UOM_UAT_PASSWORD via --dart-define',
    );

    await TokenStorage().clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    app.main();
    await login(tester);

    await go(tester, Routes.catalogo);
    await shot(tester, '02-product-list-uom');

    await tapIfVisible(tester, find.text('Nuevo producto'));
    if (find.text('Nuevo producto').evaluate().isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del producto').first,
        'Tela Azul Creacion Visual',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Precio').first,
        '120',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Costo').first,
        '70',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Stock disponible').first,
        '20.5',
      );
      final unitDropdown = find.byType(DropdownButtonFormField<String>);
      if (unitDropdown.evaluate().isNotEmpty) {
        await tester.tap(unitDropdown.first);
        await settle(tester);
        await tester.tap(find.text('Yarda (yd)').last);
        await settle(tester);
      }
      await shot(tester, '01-product-editor-yard');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
    }

    await go(tester, Routes.catalogo);
    await tapIfVisible(tester, find.textContaining('Tela Azul Visual UAT'));
    await shot(tester, '03-product-edit-yard-or-detail');

    await go(tester, Routes.catalogoStock);
    if (find
        .widgetWithText(TextField, 'Buscar producto')
        .evaluate()
        .isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar producto').first,
        'Tela',
      );
      await settle(tester);
    }
    await shot(tester, '04-stock-adjustment-list');
    await tapIfVisible(tester, find.textContaining('Tela Azul Visual UAT'));
    await shot(tester, '05-stock-adjustment-yard');

    await go(tester, Routes.registrarVenta);
    await shot(tester, '06-pos-product-grid');
    await tapIfVisible(tester, find.textContaining('Tela Azul Visual UAT'));
    if (find.widgetWithText(TextField, 'Cantidad').evaluate().isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Cantidad').last,
        '5.5',
      );
      await shot(tester, '07-pos-quantity-editor-yard');
      await tapIfVisible(tester, find.text('Agregar'));
    }
    await tapIfVisible(tester, find.textContaining('Carne Visual UAT'));
    if (find.widgetWithText(TextField, 'Cantidad').evaluate().isNotEmpty) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Cantidad').last,
        '2.375',
      );
      await shot(tester, '08-pos-quantity-editor-pound');
      await tapIfVisible(tester, find.text('Agregar'));
    }
    await shot(tester, '09-pos-cart-decimals');

    await go(tester, Routes.cotizacionesHistorial);
    await shot(tester, '10-quotation-history-uom');

    await go(tester, Routes.comprasLista);
    await tapIfVisible(tester, find.textContaining('OC-000001'));
    await shot(tester, '11-purchase-uom');

    await go(tester, Routes.ventasLista);
    await shot(tester, '12-sales-history-uom');

    await go(tester, Routes.ventas);
    await shot(tester, '13-report-uom');

    await go(tester, Routes.configuracionEmpresa);
    await shot(tester, '14-feature-enabled');
  });
}
