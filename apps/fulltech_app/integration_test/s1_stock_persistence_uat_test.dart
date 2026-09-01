import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = const String.fromEnvironment('S1_UAT_EMAIL').isNotEmpty
      ? const String.fromEnvironment('S1_UAT_EMAIL')
      : (Platform.environment['S1_UAT_EMAIL'] ?? 'uat.admin@daleventa.local');
  final password = const String.fromEnvironment('S1_UAT_PASSWORD').isNotEmpty
      ? const String.fromEnvironment('S1_UAT_PASSWORD')
      : (Platform.environment['S1_UAT_PASSWORD'] ?? '');
  final productName = const String.fromEnvironment('S1_UAT_PRODUCT').isNotEmpty
      ? const String.fromEnvironment('S1_UAT_PRODUCT')
      : (Platform.environment['S1_UAT_PRODUCT'] ?? '');
  final outDir = const String.fromEnvironment(
    'S1_UAT_SCREENSHOT_DIR',
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
    expect(context, isNotNull);
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
    await settle(tester, ticks: 20);
  }

  Future<void> searchProduct(WidgetTester tester) async {
    final search = find.widgetWithText(
      TextField,
      'Buscar por nombre, código o categoría',
    );
    expect(search, findsOneWidget);
    await tester.enterText(search.first, productName);
    await settle(tester, ticks: 8);
    expect(find.text(productName), findsWidgets);
  }

  testWidgets(
    'S1 UAT stock persists after official adjustment',
    (tester) async {
      expect(password, isNotEmpty, reason: 'Pass S1_UAT_PASSWORD');
      expect(productName, isNotEmpty, reason: 'Pass S1_UAT_PRODUCT');

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1366, 768);

      await TokenStorage().clearTokens();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      app.main();
      await login(tester);

      await go(tester, Routes.catalogo);
      await searchProduct(tester);
      expect(find.text('7 u'), findsWidgets);
      await shot(tester, 's1-05-products-readonly-7u');

      await go(tester, Routes.registrarVenta);
      await shot(tester, 's1-06-pos-opened-readonly');
      final posSearch = find.widgetWithText(TextField, 'Buscar producto');
      if (posSearch.evaluate().isNotEmpty) {
        await tester.enterText(posSearch.first, productName);
        await settle(tester, ticks: 10);
      }
      expect(find.text(productName), findsWidgets);
      expect(find.text('7'), findsWidgets);
      await shot(tester, 's1-07-pos-readonly-7u');

      await go(tester, Routes.catalogo);
      final refresh = find.byTooltip('Actualizar');
      if (refresh.evaluate().isNotEmpty) {
        await tester.tap(refresh.first);
        await settle(tester, ticks: 16);
      }
      await searchProduct(tester);
      expect(find.text('7 u'), findsWidgets);
      await shot(tester, 's1-08-products-reload-readonly-7u');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
