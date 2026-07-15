import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

Future<String> resolveLocalDatabasePath(String fileName) async {
  if (kIsWeb) {
    throw UnsupportedError('SQLite local path is not available on web');
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
