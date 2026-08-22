// Los mocks oficiales de image_picker/path_provider (ImagePickerPlatform y
// PathProviderPlatform) son paquetes transitivos. Se importan SOLO en tests
// mediante el mecanismo oficial de mock, por lo que no se declaran como
// dependencias directas para no alterar pubspec en esta fase.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:daleventa_pos/core/utils/file_utils.dart';
import 'package:daleventa_pos/core/utils/mobile_product_image_picker.dart';
import 'package:daleventa_pos/core/utils/mobile_product_image_platform_io.dart'
    as mobile_io;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Magic bytes reales de cada formato (lo que detectamos por contenido).
final _jpegMagic = Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
]);
final _pngMagic = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
]);
final _webpMagic = Uint8List.fromList([
  0x52,
  0x49,
  0x46,
  0x46,
  0x00,
  0x00,
  0x00,
  0x00,
  0x57,
  0x45,
  0x42,
  0x50,
]);
final _heicMagic = Uint8List.fromList([
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x68,
  0x65,
  0x69,
  0x63,
]);

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

class _FakeLostDataImagePickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _FakeLostDataImagePickerPlatform(this.onGetLostData);

  final Future<LostDataResponse> Function() onGetLostData;

  @override
  Future<LostDataResponse> getLostData() => onGetLostData();
}

void main() {
  late Directory sourceDir;
  late Directory appTempDir;

  setUp(() async {
    sourceDir = await Directory.systemTemp.createTemp('mobile_pipeline_src');
    appTempDir = await Directory.systemTemp.createTemp('mobile_pipeline_app');
    PathProviderPlatform.instance = _FakePathProviderPlatform(appTempDir);
    // Fuerza la plataforma móvil para que `isMobileImagePlatform()` sea true
    // solo dentro de estas pruebas (mecanismo oficial de Flutter).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    try {
      sourceDir.deleteSync(recursive: true);
    } catch (_) {}
    try {
      appTempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final file = File('${sourceDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  group(
    'processPickedMobileImage (formato real → extensión/MIME coherentes)',
    () {
      test(
        'JPEG: extensión .jpg, MIME image/jpeg, copia no vacía y limpia el temporal del plugin',
        () async {
          final source = await writeFile('foto.jpg', _jpegMagic);
          final result = await processPickedMobileImage(XFile(source.path));

          expect(result.filename.toLowerCase().endsWith('.jpg'), isTrue);
          expect(detectImageMime(result.filename)?.mimeType, 'image/jpeg');
          expect(result.filePath, isNot(source.path));

          final copy = File(result.filePath);
          expect(await copy.exists(), isTrue);
          expect(await copy.length(), greaterThan(0));

          // El temporal del plugin se limpia de forma segura tras la copia.
          expect(await source.exists(), isFalse);
        },
      );

      test(
        'PNG: extensión .png, MIME image/png y NO se etiqueta como jpeg',
        () async {
          final source = await writeFile('foto.png', _pngMagic);
          final result = await processPickedMobileImage(XFile(source.path));

          expect(result.filename.toLowerCase().endsWith('.png'), isTrue);
          expect(detectImageMime(result.filename)?.mimeType, 'image/png');
          expect(
            detectImageMime(result.filename)?.mimeType,
            isNot('image/jpeg'),
          );
          expect(await source.exists(), isFalse);
        },
      );

      test('WebP: extensión .webp, MIME image/webp', () async {
        final source = await writeFile('foto.webp', _webpMagic);
        final result = await processPickedMobileImage(XFile(source.path));

        expect(result.filename.toLowerCase().endsWith('.webp'), isTrue);
        expect(detectImageMime(result.filename)?.mimeType, 'image/webp');
      });

      test('contenido HEIC no se etiqueta falsamente como jpeg', () async {
        // Escenario de Android (raro) donde el picker no pudo normalizar.
        final source = await writeFile('foto.heic', _heicMagic);
        final result = await processPickedMobileImage(XFile(source.path));

        expect(result.filename.toLowerCase().endsWith('.heic'), isTrue);
        // Coherente: no se manda como image/jpeg si el contenido no es JPEG.
        expect(detectImageMime(result.filename), isNull);
      });

      test(
        'origen inexistente propaga error controlado (copia falla)',
        () async {
          await expectLater(
            processPickedMobileImage(XFile('${sourceDir.path}/no_existe.jpg')),
            throwsA(isA<FileSystemException>()),
          );
        },
      );
    },
  );

  group('pickMobileProductImage (con ImagePickerPlatform mockeado)', () {
    test(
      'pasa maxWidth/maxHeight/imageQuality/requestFullMetadata y procesa JPEG',
      () async {
        final source = await writeFile('foto.jpg', _jpegMagic);
        ImageSource? receivedSource;
        ImagePickerOptions? receivedOptions;
        ImagePickerPlatform.instance = _FakeImagePickerPlatform((
          src,
          options,
        ) async {
          receivedSource = src;
          receivedOptions = options;
          return XFile(source.path);
        });

        final result = await pickMobileProductImage(
          source: MobileProductImageSource.gallery,
        );

        expect(receivedSource, ImageSource.gallery);
        expect(receivedOptions?.maxWidth, 1600);
        expect(receivedOptions?.maxHeight, 1600);
        expect(receivedOptions?.imageQuality, 85);
        expect(receivedOptions?.requestFullMetadata, isFalse);
        expect(result, isNotNull);
        expect(detectImageMime(result!.filename)?.mimeType, 'image/jpeg');
      },
    );

    test(
      'usuario cancela → null, sin error y sin archivo propio creado',
      () async {
        ImagePickerPlatform.instance = _FakeImagePickerPlatform(
          (source, options) async => null,
        );

        final result = await pickMobileProductImage(
          source: MobileProductImageSource.gallery,
        );

        expect(result, isNull);
        final ownDir = Directory('${appTempDir.path}/fulltech_product_images');
        expect(await ownDir.exists(), isFalse);
      },
    );

    test('error del picker se propaga de forma controlada', () async {
      ImagePickerPlatform.instance = _FakeImagePickerPlatform((
        source,
        options,
      ) async {
        throw PlatformException(
          code: 'camera_access_denied',
          message: 'Camera permission denied',
        );
      });

      await expectLater(
        pickMobileProductImage(source: MobileProductImageSource.camera),
        throwsA(isA<PlatformException>()),
      );
    });
  });

  group('deletePluginTempSafely (limpieza segura del temporal del plugin)', () {
    test(
      'elimina solo cuando la copia propia existe, no está vacía y es distinta',
      () async {
        // Caso 1: copia presente y distinta → se elimina el temporal del plugin.
        final pluginA = await writeFile('plugin_a.jpg', _jpegMagic);
        final copyA = await writeFile('copy_a.jpg', _jpegMagic);
        await mobile_io.deletePluginTempSafely(
          pluginA.path,
          ownCopyPath: copyA.path,
        );
        expect(await pluginA.exists(), isFalse);
        expect(await copyA.exists(), isTrue);

        // Caso 2: misma ruta → nunca se borra.
        final pluginB = await writeFile('plugin_b.jpg', _jpegMagic);
        await mobile_io.deletePluginTempSafely(
          pluginB.path,
          ownCopyPath: pluginB.path,
        );
        expect(await pluginB.exists(), isTrue);

        // Caso 3: copia inexistente (p. ej. la copia falló) → no se borra.
        final pluginC = await writeFile('plugin_c.jpg', _jpegMagic);
        await mobile_io.deletePluginTempSafely(
          pluginC.path,
          ownCopyPath: '${appTempDir.path}/missing_copy.jpg',
        );
        expect(await pluginC.exists(), isTrue);

        // Caso 4: copia vacía → no se borra.
        final pluginD = await writeFile('plugin_d.jpg', _jpegMagic);
        final emptyCopy = await writeFile('empty_copy.jpg', const []);
        await mobile_io.deletePluginTempSafely(
          pluginD.path,
          ownCopyPath: emptyCopy.path,
        );
        expect(await pluginD.exists(), isTrue);
      },
    );
  });

  group('isMobileImagePlatform', () {
    test('false sin override (ruta desktop/tests)', () {
      debugDefaultTargetPlatformOverride = null;
      expect(isMobileImagePlatform(), isFalse);
    });

    test('true con override iOS/Android (pruebas del pipeline móvil)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(isMobileImagePlatform(), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(isMobileImagePlatform(), isTrue);
    });
  });

  group('recoverLostMobileImage (lost data de Android)', () {
    test('recupera y procesa una imagen perdida', () async {
      final source = await writeFile('lost.jpg', _jpegMagic);
      ImagePickerPlatform.instance = _FakeLostDataImagePickerPlatform(
        () async => LostDataResponse(file: XFile(source.path)),
      );

      final result = await recoverLostMobileImage();

      expect(result, isNotNull);
      expect(result!.filename.toLowerCase().endsWith('.jpg'), isTrue);
      expect(detectImageMime(result.filename)?.mimeType, 'image/jpeg');
      // El temporal del plugin se limpia tras procesar.
      expect(await source.exists(), isFalse);
    });

    test('respuesta vacía → null sin error', () async {
      ImagePickerPlatform.instance = _FakeLostDataImagePickerPlatform(
        () async => LostDataResponse.empty(),
      );
      expect(await recoverLostMobileImage(), isNull);
    });

    test(
      'plataforma sin getLostData (UnimplementedError) → null sin crash',
      () async {
        ImagePickerPlatform.instance = _FakeLostDataImagePickerPlatform(
          () async => throw UnimplementedError(
            'getLostData() has not been implemented.',
          ),
        );
        expect(await recoverLostMobileImage(), isNull);
      },
    );

    test('excepción de permiso previa → null sin crash', () async {
      ImagePickerPlatform.instance = _FakeLostDataImagePickerPlatform(
        () async => LostDataResponse(
          exception: PlatformException(
            code: 'camera_access_denied',
            message: 'denied',
          ),
        ),
      );
      expect(await recoverLostMobileImage(), isNull);
    });
  });

  group('mensajes de error y permisos (UX)', () {
    test('camera_access_denied → mensaje claro y detectado como permiso', () {
      final error = PlatformException(
        code: 'camera_access_denied',
        message: 'Camera permission denied',
      );
      expect(mobileProductImageErrorMessage(error), contains('permisos'));
      expect(isMobilePermissionError(error), isTrue);
    });

    test('photo_access_denied → detectado como permiso', () {
      final error = PlatformException(
        code: 'photo_access_denied',
        message: 'denied',
      );
      expect(isMobilePermissionError(error), isTrue);
    });

    test(
      'error de espacio (FileSystemException ENOSPC) → mensaje de almacenamiento',
      () {
        final error = FileSystemException(
          'No space left on device',
          '/tmp/x.jpg',
        );
        expect(mobileProductImageErrorMessage(error), contains('espacio'));
        expect(isMobilePermissionError(error), isFalse);
      },
    );

    test('error de formato no se mapea a permiso', () {
      expect(
        isMobilePermissionError(Exception('invalid image format')),
        isFalse,
      );
    });
  });

  group('deleteMobileProductImageTemp (reemplazo/limpieza)', () {
    test('tras reemplazar 3 veces solo queda el temporal actual', () async {
      // Simula seleccionar A → B → C: cada reemplazo borra el temporal previo.
      final a = await writeFile('own_a.jpg', _jpegMagic);
      final b = await writeFile('own_b.jpg', _jpegMagic);
      final c = await writeFile('own_c.jpg', _jpegMagic);

      await deleteMobileProductImageTemp(a.path);
      await deleteMobileProductImageTemp(b.path);

      expect(await a.exists(), isFalse);
      expect(await b.exists(), isFalse);
      expect(await c.exists(), isTrue); // solo el actual se conserva
    });

    test(
      'nunca borra el archivo fuente del picker (foto de la app), no el original del usuario',
      () async {
        final source = await writeFile('source_keep.jpg', _jpegMagic);
        // deleteTemp solo borra la ruta indicada; la fuente no se pasa.
        await deleteMobileProductImageTemp('${sourceDir.path}/nada.jpg');
        expect(await source.exists(), isTrue);
      },
    );
  });
}
