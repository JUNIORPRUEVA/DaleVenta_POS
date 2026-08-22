import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/cache/cache_repair.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fulltech_cache_guard_test');
  });

  tearDown(() async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  Future<File> writeInfo(String key, String content) {
    return File('${dir.path}/$key.json').writeAsString(content);
  }

  test('borra el índice cuando está vacío (0 bytes)', () async {
    final file = await writeInfo('fulltechProductImagesV5', '');
    await CacheInfoFileGuard.repairJsonInfoFile(
      cacheKey: 'fulltechProductImagesV5',
      directory: dir,
    );
    expect(await file.exists(), isFalse);
  });

  test('borra el índice cuando solo contiene espacios', () async {
    final file = await writeInfo('fulltechProductImagesV5', '   \n \t ');
    await CacheInfoFileGuard.repairJsonInfoFile(
      cacheKey: 'fulltechProductImagesV5',
      directory: dir,
    );
    expect(await file.exists(), isFalse);
  });

  test('borra el índice cuando el JSON está corrupto', () async {
    final file = await writeInfo('fulltechProductImagesV5', '{not-json');
    await CacheInfoFileGuard.repairJsonInfoFile(
      cacheKey: 'fulltechProductImagesV5',
      directory: dir,
    );
    expect(await file.exists(), isFalse);
  });

  test('mantiene el índice cuando el JSON es válido', () async {
    final content = jsonEncode(<Object>[]);
    final file = await writeInfo('fulltechProductImagesV5', content);
    await CacheInfoFileGuard.repairJsonInfoFile(
      cacheKey: 'fulltechProductImagesV5',
      directory: dir,
    );
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), content);
  });

  test('no falla cuando el archivo de índice no existe', () async {
    await CacheInfoFileGuard.repairJsonInfoFile(
      cacheKey: 'missing',
      directory: dir,
    );
    expect(await File('${dir.path}/missing.json').exists(), isFalse);
  });

  test('repara el índice del DefaultCacheManager en el directorio inyectado', () async {
    final file = await writeInfo('libCachedImageData', '');
    await CacheInfoFileGuard.repairJsonInfoFile(
      cacheKey: 'libCachedImageData',
      directory: dir,
    );
    expect(await file.exists(), isFalse);
  });
}
