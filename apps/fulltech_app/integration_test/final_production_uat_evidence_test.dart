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

  final email = const String.fromEnvironment('FINAL_UAT_EMAIL').isNotEmpty
      ? const String.fromEnvironment('FINAL_UAT_EMAIL')
      : (Platform.environment['FINAL_UAT_EMAIL'] ??
            'uat.admin@daleventa.local');
  final password = const String.fromEnvironment('FINAL_UAT_PASSWORD').isNotEmpty
      ? const String.fromEnvironment('FINAL_UAT_PASSWORD')
      : (Platform.environment['FINAL_UAT_PASSWORD'] ?? '');
  final outDir = const String.fromEnvironment(
    'FINAL_UAT_SCREENSHOT_DIR',
    defaultValue: '../../docs/final-production-uat',
  );

  Future<void> settle(WidgetTester tester, {int ticks = 10}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = Directory(outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await tester.pump(const Duration(milliseconds: 500));
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
    await settle(tester, ticks: 14);
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
    await settle(tester, ticks: 18);
  }

  Future<void> tapIfPresent(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) return;
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await settle(tester, ticks: 10);
  }

  Future<void> dragUntilVisible(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 8; i++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.ensureVisible(finder.first);
        await settle(tester, ticks: 2);
        return;
      }
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) return;
      await tester.drag(scrollable.last, const Offset(0, -620));
      await settle(tester, ticks: 4);
    }
  }

  Future<void> dragDown(WidgetTester tester, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) return;
      await tester.drag(scrollable.last, const Offset(0, -620));
      await settle(tester, ticks: 4);
    }
  }

  Future<void> closeTopPanel(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      final closeButton = find.byTooltip('Cerrar');
      if (closeButton.evaluate().isEmpty) return;
      await tester.tap(closeButton.last);
      await settle(tester, ticks: 4);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester, ticks: 8);
    expect(
      find.byTooltip('Cerrar'),
      findsNothing,
      reason: 'The active panel must be closed before more screenshots',
    );
  }

  Future<void> dismissTransientErrors(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      if (find.text('Algo salio mal').evaluate().isEmpty &&
          find.text('Algo salió mal').evaluate().isEmpty) {
        return;
      }
      final closeIcon = find.byIcon(Icons.close);
      if (closeIcon.evaluate().isNotEmpty) {
        await tester.tap(closeIcon.last);
      } else {
        final size = tester.view.physicalSize;
        await tester.tapAt(Offset(size.width - 36, size.height - 106));
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester, ticks: 4);
    }
  }

  Future<void> setViewport(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await settle(tester, ticks: 4);
  }

  Future<void> boot(WidgetTester tester, Size size) async {
    await setViewport(tester, size);
    await TokenStorage().clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    app.main();
    await login(tester);
  }

  testWidgets(
    'captures final inventory and warehouse visual UAT evidence',
    (tester) async {
      expect(password, isNotEmpty, reason: 'Pass FINAL_UAT_PASSWORD');

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await boot(tester, const Size(1366, 768));

      await go(tester, Routes.catalogo);
      await tapIfPresent(tester, find.byTooltip('Abrir menú'));
      await shot(tester, 'windows-inventory-menu');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);

      await go(tester, Routes.catalogo);
      await shot(tester, 'windows-products');
      await tapIfPresent(tester, find.text('Nuevo producto'));
      await shot(tester, 'windows-product-create-uom');
      await closeTopPanel(tester);

      await tapIfPresent(tester, find.byTooltip('Editar'));
      await shot(tester, 'windows-product-edit-uom');
      await shot(tester, 'windows-product-stock-breakdown');
      await closeTopPanel(tester);

      await go(tester, Routes.catalogoStock);
      await shot(tester, 'windows-stock-adjustment');
      await shot(tester, 'windows-stock-adjustment-uom');

      await go(tester, Routes.catalogoConteo);
      await shot(tester, 'windows-inventory-count');

      await go(tester, Routes.configuracionAlmacenes);
      await shot(tester, 'windows-warehouses');
      await dragUntilVisible(tester, find.text('Transferencias'));
      await shot(tester, 'windows-transfer');
      await go(tester, Routes.configuracionAlmacenes);
      await dragUntilVisible(tester, find.text('Terminales'));
      await shot(tester, 'windows-terminals');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'captures final kardex pos and mobile visual UAT evidence',
    (tester) async {
      expect(password, isNotEmpty, reason: 'Pass FINAL_UAT_PASSWORD');

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await boot(tester, const Size(1366, 768));

      await go(tester, Routes.registrarVenta);
      await shot(tester, 'windows-pos-simple-mode');
      await shot(tester, 'windows-pos-simple');

      await setViewport(tester, const Size(390, 844));
      await go(tester, Routes.catalogo);
      await shot(tester, 'mobile-products');
      await tapIfPresent(tester, find.byTooltip('Nuevo producto'));
      if (find.text('Unidad de medida').evaluate().isNotEmpty) {
        await shot(tester, 'mobile-product-uom');
        await closeTopPanel(tester);
      }

      await tapIfPresent(tester, find.byTooltip('Abrir menú'));
      await shot(tester, 'mobile-inventory');
      await closeTopPanel(tester);

      await go(tester, Routes.configuracionAlmacenes);
      await shot(tester, 'mobile-warehouses');
      await dragDown(tester, times: 3);
      await shot(tester, 'mobile-transfer');

      await go(tester, Routes.catalogoKardex);
      await dismissTransientErrors(tester);
      await shot(tester, 'mobile-kardex');

      await setViewport(tester, const Size(1366, 768));
      await go(tester, Routes.catalogoKardex);
      await dismissTransientErrors(tester);
      await shot(tester, 'windows-kardex-movements');
      await tapIfPresent(tester, find.text('Stock por almacén'));
      await dismissTransientErrors(tester);
      await shot(tester, 'windows-kardex-stock');
      await shot(tester, 'windows-kardex-warehouse-stock');
      await tapIfPresent(tester, find.text('Conciliación'));
      await dismissTransientErrors(tester);
      await shot(tester, 'windows-kardex-reconciliation');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
