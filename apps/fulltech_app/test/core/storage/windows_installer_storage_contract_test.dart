import 'dart:io';

import 'package:daleventa_pos/core/storage/windows_product_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'installer provisions every Windows mutable client folder for standard users',
    () {
      final installer = File('../../installer/setup.iss').readAsStringSync();
      final dirs = installer.split('[Dirs]').last.split('[Files]').first;
      for (final folder in WindowsProductFolder.values) {
        if (folder == WindowsProductFolder.app) continue;
        final relative = p.relative(
          WindowsProductPaths.pathForRoot('product-root', folder),
          from: 'product-root',
        );
        final declaration = dirs
            .split('\n')
            .where((line) => line.contains('Name: "{app}\\$relative";'));
        expect(
          declaration,
          hasLength(1),
          reason: 'Missing installer folder: $relative',
        );
        expect(declaration.single, contains('Permissions: users-modify;'));
        expect(declaration.single, contains('Flags: uninsneveruninstall'));
      }
      final runtime = dirs
          .split('\n')
          .singleWhere((line) => line.trim() == 'Name: "{app}\\app"');
      expect(runtime, isNot(contains('users-modify')));
    },
  );
}
