import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/main.dart' as app;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _S2ImagePicker extends FilePicker {
  _S2ImagePicker({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    onFileLoading?.call(FilePickerStatus.picking);
    onFileLoading?.call(FilePickerStatus.done);
    return FilePickerResult([
      PlatformFile(
        name: 's2-product-image.png',
        path: path,
        size: bytes.length,
        bytes: bytes,
      ),
    ]);
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = const String.fromEnvironment('S2_UAT_EMAIL').isNotEmpty
      ? const String.fromEnvironment('S2_UAT_EMAIL')
      : (Platform.environment['S2_UAT_EMAIL'] ?? 'uat.admin@daleventa.local');
  final password = const String.fromEnvironment('S2_UAT_PASSWORD').isNotEmpty
      ? const String.fromEnvironment('S2_UAT_PASSWORD')
      : (Platform.environment['S2_UAT_PASSWORD'] ?? '');
  final caseName = const String.fromEnvironment('S2_CASE').isNotEmpty
      ? const String.fromEnvironment('S2_CASE')
      : (Platform.environment['S2_CASE'] ?? 'tax-off-ncf-off');
  final productName = const String.fromEnvironment('S2_PRODUCT').isNotEmpty
      ? const String.fromEnvironment('S2_PRODUCT')
      : (Platform.environment['S2_PRODUCT'] ?? 'S2 Imagen UAT');
  final imagePath = const String.fromEnvironment('S2_IMAGE_PATH').isNotEmpty
      ? const String.fromEnvironment('S2_IMAGE_PATH')
      : (Platform.environment['S2_IMAGE_PATH'] ?? '');
  final outDir = const String.fromEnvironment(
    'S2_SCREENSHOT_DIR',
    defaultValue: '../../docs/final-production-uat/s2',
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
    File(
      '${dir.path}/$caseName-$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
  }

  void logStep(String message) {
    // ignore: avoid_print
    print('[S2_UAT] $message');
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

  Future<void> waitForText(
    WidgetTester tester,
    String text, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text(text).evaluate().isNotEmpty) return;
    }
    expect(find.text(text), findsWidgets);
  }

  testWidgets(
    'S2 product image and notifications in UAT',
    (tester) async {
      expect(password, isNotEmpty, reason: 'Pass S2_UAT_PASSWORD');
      expect(imagePath, isNotEmpty, reason: 'Pass S2_IMAGE_PATH');
      final imageFile = File(imagePath);
      expect(imageFile.existsSync(), isTrue);
      FilePicker.platform = _S2ImagePicker(
        path: imagePath,
        bytes: imageFile.readAsBytesSync(),
      );

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
      logStep('app started');
      await login(tester);
      logStep('login complete');

      await go(tester, Routes.catalogo);
      logStep('catalog opened');
      await tester.tap(find.text('Nuevo producto').first);
      await settle(tester, ticks: 10);
      expect(find.text('Nuevo producto'), findsWidgets);
      logStep('new product panel opened');

      await tester.enterText(
        find.widgetWithText(TextField, 'Nombre del producto').first,
        productName,
      );
      await tester.enterText(
        find
            .widgetWithText(TextField, 'Código / código de barra (opcional)')
            .first,
        'S2-${caseName.hashCode.abs()}-${productName.hashCode.abs()}',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Precio').first,
        '150',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Costo').first,
        '80',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Stock disponible').first,
        '4',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Categoría').first,
        'S2 UAT',
      );

      await tester.tap(find.text('Subir imagen desde el ordenador').first);
      await settle(tester, ticks: 16);
      expect(find.text('s2-product-image.png'), findsOneWidget);
      await shot(tester, '01-form-image-preview');
      logStep('image preview captured');

      await tester.tap(find.text('Crear producto').last);
      await waitForText(tester, 'Producto creado');
      await shot(tester, '02-product-created-top-right');
      await settle(tester, ticks: 8);
      logStep('product created notification captured');

      await searchProduct(tester);
      await shot(tester, '03-products-image-visible');
      logStep('products image captured');

      await go(tester, Routes.registrarVenta);
      final posSearch = find.widgetWithText(TextField, 'Buscar producto');
      if (posSearch.evaluate().isNotEmpty) {
        await tester.enterText(posSearch.first, productName);
        await settle(tester, ticks: 10);
      }
      expect(find.text(productName), findsWidgets);
      await shot(tester, '04-pos-image-visible');
      logStep('pos image captured');

      await go(tester, Routes.catalogo);
      final refresh = find.byTooltip('Actualizar');
      if (refresh.evaluate().isNotEmpty) {
        await tester.tap(refresh.first);
        await settle(tester, ticks: 16);
      }
      await searchProduct(tester);
      await shot(tester, '05-products-reload-image-visible');
      logStep('products reload image captured');

      await tester.tap(find.byTooltip('Editar').first);
      await settle(tester, ticks: 12);
      expect(find.text('Editar producto'), findsOneWidget);
      await shot(tester, '06-edit-existing-image-visible');
      logStep('edit image captured');

      await tester.tap(find.text('Ajustar stock').last);
      await settle(tester, ticks: 12);
      expect(find.text('Ajustar stock'), findsWidgets);
      expect(find.text(productName), findsWidgets);
      await tester.tap(find.text('Aplicar ajuste').last);
      await waitForText(tester, 'Stock actualizado');
      await shot(tester, '07-stock-updated-top-right');
      logStep('stock notification captured');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
