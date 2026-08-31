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

  final mode = const String.fromEnvironment('UOM_UAT_MODE', defaultValue: 'on');
  final onEmail = const String.fromEnvironment('UOM_UAT_EMAIL').isNotEmpty
      ? const String.fromEnvironment('UOM_UAT_EMAIL')
      : (Platform.environment['UOM_UAT_EMAIL'] ?? '');
  final offEmail = const String.fromEnvironment('UOM_UAT_OFF_EMAIL').isNotEmpty
      ? const String.fromEnvironment('UOM_UAT_OFF_EMAIL')
      : (Platform.environment['UOM_UAT_OFF_EMAIL'] ??
            'uat.legacy@daleventa.local');
  final password = const String.fromEnvironment('UOM_UAT_PASSWORD').isNotEmpty
      ? const String.fromEnvironment('UOM_UAT_PASSWORD')
      : (Platform.environment['UOM_UAT_PASSWORD'] ?? '');
  final outDir = const String.fromEnvironment(
    'UOM_UAT_SCREENSHOT_DIR',
    defaultValue: '../../docs/uom-visual-evidence/phase48-final',
  );

  Future<void> settle(WidgetTester tester, {int ticks = 8}) async {
    for (var i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = Directory(outDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await tester.pump(const Duration(milliseconds: 600));
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

  Future<void> login(WidgetTester tester, String email) async {
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
    await settle(tester, ticks: 14);
  }

  Future<void> tapFirst(WidgetTester tester, Finder finder) async {
    expect(finder.evaluate(), isNotEmpty, reason: 'Expected tappable target');
    await tester.ensureVisible(finder.first);
    await tester.tap(finder.first);
    await settle(tester, ticks: 10);
  }

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder, {
    int ticks = 24,
  }) async {
    for (var i = 0; i < ticks; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.pump(const Duration(milliseconds: 250));
    }
    await shot(tester, 'debug-missing-target');
    expect(finder.evaluate(), isNotEmpty, reason: 'Expected visible target');
  }

  Future<void> dragUntilVisible(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 8; i++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.ensureVisible(finder.first);
        await settle(tester, ticks: 2);
        return;
      }
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isEmpty) break;
      await tester.drag(scrollable.last, const Offset(0, -650));
      await settle(tester, ticks: 3);
    }
    await shot(tester, 'debug-scroll-target');
    expect(finder.evaluate(), isNotEmpty, reason: 'Expected scrolled target');
  }

  Future<void> openPdfAndCapture(
    WidgetTester tester,
    Finder trigger,
    String name,
  ) async {
    await waitFor(tester, trigger);
    await tapFirst(tester, trigger);
    await settle(tester, ticks: 20);
    await shot(tester, name);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
  }

  testWidgets('captures Phase 4.8 final visual evidence', (tester) async {
    expect(password, isNotEmpty, reason: 'Pass UOM_UAT_PASSWORD');
    final email = mode == 'off' ? offEmail : onEmail;
    expect(email, isNotEmpty, reason: 'Pass UAT email for selected mode');

    await TokenStorage().clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    app.main();
    await login(tester, email);

    if (mode == 'off') {
      await go(tester, Routes.catalogo);
      await tapFirst(tester, find.text('Nuevo producto'));
      await shot(tester, '04-feature-off-product');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);

      await go(tester, Routes.catalogoStock);
      await shot(tester, '05-feature-off-inventory');

      await go(tester, Routes.registrarVenta);
      await shot(tester, '06-feature-off-pos');
      return;
    }

    await go(tester, Routes.ventasLista);
    await waitFor(tester, find.text('Facturacion'));
    await openPdfAndCapture(tester, find.byTooltip('PDF'), '01-invoice-pdf');

    await go(tester, Routes.cotizacionesHistorial);
    await waitFor(tester, find.textContaining('Cliente Visual UAT'));
    await openPdfAndCapture(
      tester,
      find.byIcon(Icons.picture_as_pdf_outlined),
      '02-quotation-pdf',
    );

    await go(tester, Routes.comprasLista);
    await tapFirst(tester, find.textContaining('OC-000001'));
    await openPdfAndCapture(tester, find.text('PDF'), '03-purchase-pdf');

    await go(tester, Routes.configuracionEmpresa);
    await shot(tester, '07-feature-on-off-comparison');

    await go(tester, Routes.ventas);
    await dragUntilVisible(tester, find.text('Productos más vendidos'));
    await shot(tester, '08-report-buckets');

    await go(tester, Routes.comprasLista);
    await tapFirst(tester, find.textContaining('OC-000001'));
    await shot(tester, '09-purchase-received-pending');
  });
}
