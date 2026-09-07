import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'local_database_migration.dart';
import 'windows_product_paths.dart';

Future<String> resolveLocalDatabasePath(String fileName) async {
  if (kIsWeb) {
    throw UnsupportedError('SQLite local path is not available on web');
  }

  final windowsDatabaseDir = WindowsProductPaths.folder(
    WindowsProductFolder.databases,
  );
  if (windowsDatabaseDir != null) {
    await windowsDatabaseDir.create(recursive: true);
    final targetPath = p.join(windowsDatabaseDir.path, fileName);
    await copyLegacyDatabaseIfNeeded(
      fileName: fileName,
      targetPath: targetPath,
      legacyDirectories: await _legacyDatabaseDirectories(),
    );
    return targetPath;
  }

  final candidates = <Future<Directory> Function()>[
    () async {
      final platform = defaultTargetPlatform;
      if (platform == TargetPlatform.windows ||
          platform == TargetPlatform.linux ||
          platform == TargetPlatform.macOS) {
        final supportDir = await getApplicationSupportDirectory();
        return Directory(p.join(supportDir.path, 'databases'));
      }

      final dbPath = await getDatabasesPath();
      return Directory(dbPath);
    },
    () async {
      final dbPath = await getDatabasesPath();
      return Directory(dbPath);
    },
    () async {
      final tempDir = await getTemporaryDirectory();
      return Directory(p.join(tempDir.path, 'fulltech', 'databases'));
    },
  ];

  Object? lastError;
  for (final candidate in candidates) {
    try {
      final directory = await candidate();
      await directory.create(recursive: true);
      return p.join(directory.path, fileName);
    } catch (error) {
      lastError = error;
    }
  }

  throw StateError(
    'No se pudo resolver una ruta local para la base de datos $fileName${lastError == null ? '' : ': $lastError'}',
  );
}

Future<List<Directory>> _legacyDatabaseDirectories() async {
  final dirs = <Directory>[];

  try {
    final supportDir = await getApplicationSupportDirectory();
    dirs.add(Directory(p.join(supportDir.path, 'databases')));
  } catch (_) {}

  try {
    dirs.add(Directory(await getDatabasesPath()));
  } catch (_) {}

  try {
    final tempDir = await getTemporaryDirectory();
    dirs.add(Directory(p.join(tempDir.path, 'fulltech', 'databases')));
  } catch (_) {}

  final appData = (Platform.environment['APPDATA'] ?? '').trim();
  if (appData.isNotEmpty) {
    for (final parts in const <List<String>>[
      ['FullPOS Cloud', 'FullPOS Cloud - Sistema de facturacion', 'databases'],
      ['FullTech', 'FullTech', 'databases'],
      ['DaleVenta POS', 'DaleVenta POS - Sistema de facturacion', 'databases'],
      ['DaleVentas POS', 'DaleVentas POS', 'databases'],
    ]) {
      dirs.add(Directory(p.joinAll([appData, ...parts])));
    }
  }

  return dirs;
}
