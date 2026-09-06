import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/windows_product_paths.dart';

Future<String?> saveLocalMediaCopy({
  required String module,
  required String scopeId,
  required String fileName,
  List<int>? bytes,
  String? sourcePath,
}) async {
  final normalizedSource = (sourcePath ?? '').trim();
  final normalizedModule = module.trim().replaceAll(
    RegExp(r'[^a-zA-Z0-9_-]'),
    '_',
  );
  final normalizedScope = scopeId.trim().replaceAll(
    RegExp(r'[^a-zA-Z0-9_-]'),
    '_',
  );
  final safeFileName = _sanitizeFileName(fileName);

  if (normalizedModule.isEmpty ||
      normalizedScope.isEmpty ||
      safeFileName.isEmpty) {
    return normalizedSource.isEmpty ? null : normalizedSource;
  }

  final supportDir =
      WindowsProductPaths.folder(WindowsProductFolder.mediaCache) ??
      await getApplicationSupportDirectory();
  final targetDir = Directory(
    p.join(
      supportDir.path,
      WindowsProductPaths.isOfficialWindowsStorageEnabled
          ? ''
          : 'fulltech_media_cache',
      normalizedModule,
      normalizedScope,
    ),
  );
  await targetDir.create(recursive: true);

  final extension = p.extension(safeFileName);
  final stem = extension.isEmpty
      ? safeFileName
      : safeFileName.substring(0, safeFileName.length - extension.length);
  final targetPath = p.join(
    targetDir.path,
    '${DateTime.now().microsecondsSinceEpoch}_$stem$extension',
  );
  final targetFile = File(targetPath);

  if (bytes != null && bytes.isNotEmpty) {
    await targetFile.writeAsBytes(bytes, flush: true);
    return targetFile.path;
  }

  if (normalizedSource.isNotEmpty) {
    final sourceFile = File(normalizedSource);
    if (await sourceFile.exists()) {
      await sourceFile.copy(targetFile.path);
      return targetFile.path;
    }
  }

  return normalizedSource.isEmpty ? null : normalizedSource;
}

String _sanitizeFileName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
