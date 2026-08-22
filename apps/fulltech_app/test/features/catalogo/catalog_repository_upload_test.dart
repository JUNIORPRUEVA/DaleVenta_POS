import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/cache/local_json_cache.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_test');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<File> writeImage(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<ResponseBody> jsonResponse(Object data) async {
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  test(
    'uploadImage con filePath usa MultipartFile.fromFile con filename y MIME coherentes',
    () async {
      final jpegMagic = Uint8List.fromList([
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
      final pngMagic = Uint8List.fromList([
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
      ]);

      // JPEG: filename .jpg → MIME image/jpeg
      final jpeg = await writeImage('producto.jpg', jpegMagic);
      FormData? jpegForm;
      final dioJpeg = _fakeDio((options) async {
        jpegForm = options.data as FormData?;
        return jsonResponse({'url': '/uploads/producto.jpg'});
      });
      final repoJpeg = CatalogRepository(
        dioJpeg,
        _FakeTokenStorage('company-u'),
        null,
        Duration(minutes: 2),
        _MemoryJsonCache(),
      );
      final jpegPath = await repoJpeg.uploadImage(
        filePath: jpeg.path,
        filename: 'producto.jpg',
      );
      expect(jpegPath, '/uploads/producto.jpg');
      expect(jpegForm, isNotNull);
      final jpegPart = jpegForm!.files.single.value;
      expect(jpegPart.filename, 'producto.jpg');
      expect(jpegPart.contentType?.mimeType, 'image/jpeg');

      // PNG: filename .png → MIME image/png (no etiquetado como jpeg)
      final png = await writeImage('producto.png', pngMagic);
      FormData? pngForm;
      final dioPng = _fakeDio((options) async {
        pngForm = options.data as FormData?;
        return jsonResponse({'url': '/uploads/producto.png'});
      });
      final repoPng = CatalogRepository(
        dioPng,
        _FakeTokenStorage('company-u'),
        null,
        Duration(minutes: 2),
        _MemoryJsonCache(),
      );
      final pngPath = await repoPng.uploadImage(
        filePath: png.path,
        filename: 'producto.png',
      );
      expect(pngPath, '/uploads/producto.png');
      expect(pngForm, isNotNull);
      final pngPart = pngForm!.files.single.value;
      expect(pngPart.filename, 'producto.png');
      expect(pngPart.contentType?.mimeType, 'image/png');
      expect(pngPart.contentType?.mimeType, isNot('image/jpeg'));
    },
  );
}

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage(this._companyId);

  final String? _companyId;

  @override
  Future<UserModel?> getUserSnapshot() async {
    if (_companyId == null) return null;
    return UserModel(
      id: 'user-$_companyId',
      email: 'test@example.com',
      nombreCompleto: 'Test',
      telefono: '',
      companyId: _companyId,
    );
  }
}

class _MemoryJsonCache extends LocalJsonCache {
  final Map<String, Map<String, dynamic>> _values = {};
  final Map<String, DateTime> _writtenAt = {};

  @override
  Future<Map<String, dynamic>?> readMap(String key, {Duration? maxAge}) async {
    final value = _values[key];
    if (value == null) return null;
    final age = DateTime.now().difference(_writtenAt[key]!);
    if (maxAge != null && (maxAge <= Duration.zero || age > maxAge)) {
      return null;
    }
    return Map<String, dynamic>.from(value);
  }

  @override
  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    _values[key] = Map<String, dynamic>.from(value);
    _writtenAt[key] = DateTime.now();
  }
}

Dio _fakeDio(Future<ResponseBody> Function(RequestOptions options) handler) {
  final dio = Dio(BaseOptions(baseUrl: 'https://products.test'));
  dio.httpClientAdapter = _FakeHttpClientAdapter(handler);
  return dio;
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
