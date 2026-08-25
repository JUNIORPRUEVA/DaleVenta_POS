// Los mocks oficiales de image_picker/path_provider (ImagePickerPlatform y
// PathProviderPlatform) son paquetes transitivos. Se importan SOLO en tests
// mediante el mecanismo oficial de mock, por lo que no se declaran como
// dependencias directas para no alterar pubspec en esta fase.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository() : super(Dio());

  int uploads = 0;
  String? lastUploadFilePath;
  String? lastUploadFilename;

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    return const [];
  }

  @override
  Future<List<ProductModel>> getCachedProducts({Duration? maxAge}) async {
    return const [];
  }

  @override
  Future<void> saveProductsSnapshot(List<ProductModel> items) async {}

  @override
  Future<String> uploadImage({
    List<int>? bytes,
    String? filePath,
    required String filename,
  }) async {
    uploads += 1;
    lastUploadFilePath = filePath;
    lastUploadFilename = filename;
    return '/uploads/$filename';
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);

  final Directory tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

class _FakeImagePickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _FakeImagePickerPlatform(this.handler);

  final Future<XFile?> Function(ImageSource source, ImagePickerOptions options)
  handler;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) {
    return handler(source, options);
  }
}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required _FakeCatalogRepository repo,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        productTaxUiConfigProvider.overrideWith(
          (ref) async => ProductTaxUiConfig(
            settings: CompanySettings.empty(),
            activeTaxes: const [],
          ),
        ),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push<ProductFormResult>(
                      MaterialPageRoute<ProductFormResult>(
                        builder: (_) => const InventoryProductEditorPage(
                          product: null,
                          categories: ['General', 'Herramientas'],
                        ),
                      ),
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// En testWidgets el cuerpo corre en FakeAsync: cada `await` de IO real
/// necesita que el evento de IO real se dispare (runAsync) y que después se
/// vacíen los microtasks del fake (pump). Este helper alterna ambos para dejar
/// que el pipeline móvil (detección/copia/limpieza/subida) complete.
Future<void> pumpRealIo(WidgetTester tester, {int rounds = 15}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pump();
  }
}

Future<Finder> _pumpUntilHitTestable(
  WidgetTester tester,
  Finder finder, {
  int rounds = 10,
}) async {
  for (var i = 0; i < rounds; i++) {
    final hitTestableFinder = finder.hitTestable();
    if (hitTestableFinder.evaluate().isNotEmpty) {
      return hitTestableFinder;
    }
    await tester.pump(const Duration(milliseconds: 120));
  }
  fail('No hit-testable widget found for $finder');
}

void main() {
  late Directory sourceDir;
  late Directory appTempDir;
  late File jpegFile;
  late File jpegFile2;
  late Uint8List validJpeg;

  setUpAll(() {
    // Imagen JPEG válida y decodificable para la preview (Image.file).
    final image = img.Image(width: 4, height: 4, numChannels: 3);
    validJpeg = Uint8List.fromList(img.encodeJpg(image, quality: 90));
  });

  setUp(() async {
    // NOTA: el cuerpo de testWidgets corre en FakeAsync; las operaciones de
    // IO real no completan ahí. Por eso los archivos se crean en setUp
    // (zona normal) y solo el IO del pipeline se deja completar con runAsync.
    sourceDir = await Directory.systemTemp.createTemp('mobile_form_src');
    appTempDir = await Directory.systemTemp.createTemp('mobile_form_app');
    jpegFile = File('${sourceDir.path}/foto.jpg');
    jpegFile2 = File('${sourceDir.path}/foto2.jpg');
    await jpegFile.writeAsBytes(validJpeg);
    await jpegFile2.writeAsBytes(validJpeg);
    PathProviderPlatform.instance = _FakePathProviderPlatform(appTempDir);
  });

  tearDown(() {
    try {
      sourceDir.deleteSync(recursive: true);
    } catch (_) {}
    try {
      appTempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets(
    'móvil: elegir de galería procesa, usa la nueva ruta y sube por archivo',
    (tester) async {
      // Forzar plataforma móvil dentro del cuerpo y restablecerlo con
      // try/finally: la invariante de Flutter se verifica antes de los
      // addTearDown, por lo que el reset debe ocurrir dentro del cuerpo.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final repo = _FakeCatalogRepository();
        ImagePickerPlatform.instance = _FakeImagePickerPlatform(
          (source, options) async => XFile(jpegFile.path),
        );

        await _pumpEditor(tester, repo: repo);

        await tester.ensureVisible(
          find.text('Subir imagen desde el ordenador'),
        );
        final uploadButton = await _pumpUntilHitTestable(
          tester,
          find.text('Subir imagen desde el ordenador'),
        );
        await tester.tap(uploadButton);
        await tester.pump();
        final galleryOption = await _pumpUntilHitTestable(
          tester,
          find.text('Elegir de galería'),
        );

        // Elige galería (tap fuera de runAsync) y deja que el pipeline (IO
        // real) complete su trabajo con ciclos runAsync + pump.
        await tester.tap(galleryOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await pumpRealIo(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(repo.uploads, 1);
        // La subida móvil usa la ruta del archivo optimizado (fromFile).
        expect(repo.lastUploadFilePath, isNotNull);
        expect(repo.lastUploadFilePath!.endsWith('.jpg'), isTrue);
        expect(repo.lastUploadFilename, isNotNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );

  testWidgets(
    'móvil: doble selección no abre el selector dos veces ni lanza dos uploads',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final repo = _FakeCatalogRepository();
        final gate = Completer<XFile>();
        var pickerCalls = 0;
        ImagePickerPlatform.instance = _FakeImagePickerPlatform((
          source,
          options,
        ) {
          pickerCalls += 1;
          return gate.future;
        });

        await _pumpEditor(tester, repo: repo);

        await tester.ensureVisible(
          find.text('Subir imagen desde el ordenador'),
        );
        final uploadButton = await _pumpUntilHitTestable(
          tester,
          find.text('Subir imagen desde el ordenador'),
        );
        await tester.tap(uploadButton);
        await tester.pump();
        final galleryOption = await _pumpUntilHitTestable(
          tester,
          find.text('Elegir de galería'),
        );

        // El picker queda pendiente (sin IO): se elige galería y se espera.
        await tester.tap(galleryOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Mientras el picker está pendiente, un segundo toque no abre nada
        // nuevo (el botón está deshabilitado por `_isPickingImage`).
        await tester.tap(
          find.text('Seleccionando imagen...'),
          warnIfMissed: false,
        );
        await tester.pump();

        expect(pickerCalls, 1);
        expect(find.text('Agregar fotografía'), findsNothing);

        // Completar la selección: se produce exactamente un upload.
        gate.complete(XFile(jpegFile2.path));
        await tester.pump();
        await pumpRealIo(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(repo.uploads, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}
