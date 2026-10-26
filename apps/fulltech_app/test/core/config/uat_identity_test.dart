import 'package:daleventa_pos/core/config/uat_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fase 1 — separación de identidad y almacenamiento UAT.
///
/// Invariantes:
///  - Producción no cambia ni un byte: mismos nombres de base, prefijos y
///    título que antes del blindaje.
///  - Un build UAT usa almacenamiento propio (SQLite, caché, credenciales) y
///    un título inequívoco, de modo que no puede mezclar datos ni sobrescribir
///    la instalación real del equipo.
class _MemoryBacked {
  static String get offlineDb => UatIdentity.offlineDatabaseFileName(uat: true);
}

void main() {
  group('UatIdentity · producción intacta', () {
    test('título de producción se conserva literal', () {
      expect(
        UatIdentity.appTitle(uat: false),
        'FullPOS Cloud - Sistema de facturacion',
      );
    });

    test('base offline de producción se conserva', () {
      expect(
        UatIdentity.offlineDatabaseFileName(uat: false),
        'fulltech_offline.db',
      );
    });

    test('prefijos de caché y credenciales de producción se conservan', () {
      expect(UatIdentity.cachePrefix(uat: false), 'ft_cache:');
      expect(UatIdentity.webCachePrefix(uat: false), 'ft_db_cache:');
      expect(UatIdentity.storageKeyPrefix(uat: false), '');
      expect(UatIdentity.storageKey('accessToken', uat: false), 'accessToken');
    });
  });

  group('UatIdentity · aislamiento UAT', () {
    test('título UAT es inequívoco y no contiene el de producción', () {
      final title = UatIdentity.appTitle(uat: true);
      expect(title.toUpperCase(), contains('UAT'));
      expect(title.toUpperCase(), contains('NO PRODUCCIÓN'));
      expect(title, isNot('FullPOS Cloud - Sistema de facturacion'));
    });

    test('base offline UAT es distinta de la real', () {
      expect(
        UatIdentity.offlineDatabaseFileName(uat: true),
        'fulltech_offline.uat.db',
      );
      expect(
        UatIdentity.offlineDatabaseFileName(uat: true),
        isNot(UatIdentity.offlineDatabaseFileName(uat: false)),
      );
    });

    test('prefijos UAT no colisionan con producción', () {
      expect(UatIdentity.cachePrefix(uat: true), 'ft_cache_uat:');
      expect(UatIdentity.webCachePrefix(uat: true), 'ft_db_cache_uat:');
      expect(UatIdentity.storageKeyPrefix(uat: true), 'uat.');
      expect(UatIdentity.storageKey('accessToken', uat: true), 'uat.accessToken');
      expect(
        UatIdentity.storageKey('accessToken', uat: true),
        isNot(UatIdentity.storageKey('accessToken', uat: false)),
      );
    });

    test('todas las claves de credenciales quedan prefijadas en UAT', () {
      const keys = ['accessToken', 'refreshToken', 'authUserSnapshot'];
      for (final key in keys) {
        expect(UatIdentity.storageKey(key, uat: true), startsWith('uat.'));
      }
    });

    test('la base UAT usada por el store coincide con la identidad UAT', () {
      expect(_MemoryBacked.offlineDb, 'fulltech_offline.uat.db');
    });
  });

  group('UatIdentity · interruptor de compilación', () {
    test('kUatBuild refleja el dart-define FULLPOS_UAT_BUILD', () {
      const expected = bool.fromEnvironment('FULLPOS_UAT_BUILD');
      expect(kUatBuild, expected);
      expect(UatIdentity.isUat, expected);
    });

    test('sin define, producción queda como valor por defecto', () {
      if (kUatBuild) return; // la variante UAT se valida en su propia corrida
      expect(UatIdentity.appTitle(), contains('Sistema de facturacion'));
      expect(
        UatIdentity.offlineDatabaseFileName(),
        'fulltech_offline.db',
      );
    });
  });
}
