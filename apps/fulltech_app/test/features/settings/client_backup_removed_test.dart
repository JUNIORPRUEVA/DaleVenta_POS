import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guarantee: the client-side backup/restore workflow was removed on
/// purpose. Backups are now a server-side/FULLTECH responsibility, so the POS
/// client must never create a local backup, build an enterprise ZIP, inspect it,
/// validate required modules (the old `FormatException` source) or expose any
/// backup/restore UI, route or startup hook.
///
/// These tests fail if any of that is reintroduced into the client.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('client backup removal guarantee', () {
    test('backup services and screens no longer exist', () {
      expect(
        File(
          'lib/features/settings/data/cloud_backup_service.dart',
        ).existsSync(),
        isFalse,
        reason: 'CloudBackupService must stay removed from the client',
      );
      expect(
        File(
          'lib/features/settings/data/backup_open_intent_service.dart',
        ).existsSync(),
        isFalse,
        reason: 'BackupOpenIntentService must stay removed from the client',
      );
    });

    test('login/startup must not touch backup', () {
      for (final path in const [
        'lib/main.dart',
        'lib/features/home/home_shell.dart',
        'lib/core/auth/auth_provider.dart',
      ]) {
        final source = read(path);
        expect(
          source.contains('cloudBackupServiceProvider'),
          isFalse,
          reason: '$path must not reference cloudBackupServiceProvider',
        );
        expect(
          source.contains('createAutomaticBackupIfDue'),
          isFalse,
          reason: '$path must not schedule automatic backups',
        );
        expect(
          source.contains('BackupOpenIntentService'),
          isFalse,
          reason: '$path must not handle backup open intents',
        );
      }
    });

    test('routing has no backup route or screen', () {
      final routes = read('lib/core/routing/routes.dart');
      final router = read('lib/core/routing/app_router.dart');
      expect(routes.contains('configuracionBackup'), isFalse);
      expect(router.contains('configuracionBackup'), isFalse);
      expect(router.contains('AccountBackupSettingsScreen'), isFalse);
    });

    test('settings and account menus expose no backup entry', () {
      for (final path in const [
        'lib/features/account/account_menu_screens.dart',
        'lib/modules/cotizaciones/cotizaciones_screen.dart',
        'lib/modules/ventas/registrar_venta_screen.dart',
      ]) {
        final source = read(path);
        expect(
          source.contains('Respaldo'),
          isFalse,
          reason: '$path must not contain a backup menu entry',
        );
        expect(
          source.contains('configuracionBackup'),
          isFalse,
          reason: '$path must not link to the removed backup route',
        );
      }
    });

    test(
      'client never generates a backup ZIP or validates required modules',
      () {
        final libFiles = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'));

        for (final file in libFiles) {
          final source = file.readAsStringSync();
          expect(
            source.contains('requiredModuleNames'),
            isFalse,
            reason: '${file.path} reintroduces requiredModuleNames validation',
          );
          expect(
            source.contains('inspectBackupZipForCompany'),
            isFalse,
            reason: '${file.path} reintroduces backup ZIP inspection',
          );
          expect(
            source.contains('createCloudBackup'),
            isFalse,
            reason: '${file.path} reintroduces client backup creation',
          );
          expect(
            source.contains('dvbackup'),
            isFalse,
            reason: '${file.path} reintroduces .dvbackup handling',
          );
        }
      },
    );
  });
}
