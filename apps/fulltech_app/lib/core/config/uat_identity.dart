/// Identidad y separación del build UAT.
///
/// Reglas de seguridad (Fase 1):
///  - Un build UAT nunca debe poder confundirse con el de producción.
///  - Un build UAT no debe compartir almacenamiento local (SQLite, caché,
///    credenciales) con la instalación real del mismo equipo.
///  - Las builds de producción NO cambian: todos los valores por defecto siguen
///    siendo exactamente los de antes (`fulltech_offline.db`, `ft_cache:`, sin
///    prefijo de credenciales y el título original).
///
/// Todo se activa con `--dart-define=FULLPOS_UAT_BUILD=true`, que es el mismo
/// interruptor que `Env` usa para rechazar hosts productivos.
library;

/// `true` solo en compilaciones UAT explícitas.
const bool kUatBuild = bool.fromEnvironment(
  'FULLPOS_UAT_BUILD',
  defaultValue: false,
);

/// Etiqueta visible (permite distinguir varios entornos UAT: QA, cliente, etc.).
const String kUatLabelDefine = String.fromEnvironment(
  'FULLPOS_UAT_LABEL',
  defaultValue: 'UAT',
);

class UatIdentity {
  UatIdentity._();

  static const String _productionTitle =
      'FullPOS Cloud - Sistema de facturacion';
  static const String _productionOfflineDatabase = 'fulltech_offline.db';
  static const String _productionWebCachePrefix = 'ft_db_cache:';
  static const String _productionCachePrefix = 'ft_cache:';
  static const String _productionStorageKeyPrefix = '';

  static const String _uatOfflineDatabase = 'fulltech_offline.uat.db';
  static const String _uatWebCachePrefix = 'ft_db_cache_uat:';
  static const String _uatCachePrefix = 'ft_cache_uat:';
  static const String _uatStorageKeyPrefix = 'uat.';

  /// `true` en un build UAT.
  static bool get isUat => kUatBuild;

  /// Etiqueta corta y visible del entorno.
  static String get label {
    final raw = kUatLabelDefine.trim();
    return raw.isEmpty ? 'UAT' : raw;
  }

  /// Título de la ventana / aplicación. El sufijo UAT es inequívoco y no
  /// depende de configuración en tiempo de ejecución.
  static String appTitle({bool? uat}) {
    if (!(uat ?? isUat)) return _productionTitle;
    return 'FullPOS Cloud [$label] — ENTORNO DE PRUEBAS (no producción)';
  }

  /// Nombre del archivo SQLite del outbox/offline. En UAT va separado para no
  /// mezclar operaciones pendientes con la instalación real del equipo.
  static String offlineDatabaseFileName({bool? uat}) =>
      (uat ?? isUat) ? _uatOfflineDatabase : _productionOfflineDatabase;

  /// Prefijo de la caché JSON local. En UAT no comparte claves con producción.
  static String cachePrefix({bool? uat}) =>
      (uat ?? isUat) ? _uatCachePrefix : _productionCachePrefix;

  /// Prefijo de claves en almacenamiento web (IndexedDB/localStorage).
  static String webCachePrefix({bool? uat}) =>
      (uat ?? isUat) ? _uatWebCachePrefix : _productionWebCachePrefix;

  /// Prefijo de credenciales (secure storage / preferencias). Evita que un
  /// login UAT reutilice o sobrescriba el token de la instalación real.
  static String storageKeyPrefix({bool? uat}) =>
      (uat ?? isUat) ? _uatStorageKeyPrefix : _productionStorageKeyPrefix;

  /// Compone una clave de almacenamiento respetando el prefijo del entorno.
  static String storageKey(String key, {bool? uat}) =>
      '${storageKeyPrefix(uat: uat)}$key';
}
