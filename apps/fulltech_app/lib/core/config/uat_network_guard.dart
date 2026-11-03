/// Guardia centralizada de destinos de red para el perfil UAT.
///
/// Motivo: una compilación de validación llegó a hablar con producción porque
/// `Env.apiBaseUrl` usa `ProductConfig.productionApiBaseUrl` como valor por
/// defecto. Aquel incidente se corrigió recompilando con `--dart-define`, pero
/// el riesgo seguía siendo de procedimiento. Esta clase lo convierte en una
/// **garantía de ejecución**.
///
/// Reglas:
///
/// - Se activa si `FULLPOS_UAT_PROFILE=true` **o** `APP_ENV=uat`. Así un build
///   con solo `APP_ENV=uat` tampoco puede caer en producción.
/// - Exige una URL explícita. **No hay valor por defecto.**
/// - Solo admite destinos locales, comparando **host y puerto** parseados, no
///   subcadenas de texto.
/// - Rechaza hosts productivos conocidos y cualquier subdominio de EasyPanel.
/// - Un build comercial (`isUat == false`) no pasa por aquí: su comportamiento
///   queda intacto.
///
/// La validación se aplica **antes** de construir el cliente HTTP, de enviar
/// credenciales y de adjuntar cabeceras de telemetría.
class UatNetworkGuard {
  UatNetworkGuard._();

  /// Entorno declarado en tiempo de compilación (`--dart-define=APP_ENV=...`).
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: '',
  );

  /// Bandera de perfil blindado (`--dart-define=FULLPOS_UAT_PROFILE=true`).
  static const bool uatProfileFlag = bool.fromEnvironment(
    'FULLPOS_UAT_PROFILE',
    defaultValue: false,
  );

  /// `true` cuando la aplicación se está ejecutando como validación UAT.
  static bool get isUat =>
      uatProfileFlag || appEnv.trim().toLowerCase() == 'uat';

  /// Prefijo de almacenamiento local. Vacío en builds comerciales para no
  /// alterar las claves existentes de los clientes.
  static String storageNamespaceFor({bool? uat}) =>
      (uat ?? isUat) ? 'uat.' : '';

  static String get storageNamespace => storageNamespaceFor();

  /// Nombre de la base SQLite local. En UAT se usa un fichero distinto para no
  /// leer datos comerciales ya sincronizados en el equipo.
  static String offlineDatabaseFileNameFor({bool? uat}) =>
      (uat ?? isUat) ? 'fulltech_offline_uat.db' : 'fulltech_offline.db';

  static String get offlineDatabaseFileName => offlineDatabaseFileNameFor();

  /// Únicos hosts admitidos mientras UAT esté activo.
  static const Set<String> allowedHosts = {'127.0.0.1', 'localhost', '::1'};

  /// Único puerto admitido mientras UAT esté activo.
  static const Set<int> allowedPorts = {4004};

  /// Hosts productivos conocidos. Se comparan por **host exacto**.
  static const Set<String> forbiddenHosts = {
    'daleventapos-backend.gcdndd.easypanel.host',
    'fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host',
    'fullpos-backend-fullpos-backend.onqyr1.easypanel.host',
    'fulltech-tienda-fulltechapppwa.gcdndd.easypanel.host',
  };

  /// Sufijos de infraestructura remota. Se comparan por **sufijo de host**.
  static const List<String> forbiddenHostSuffixes = [
    '.easypanel.host',
    '.onqyr1.easypanel.host',
    '.gcdndd.easypanel.host',
  ];

  /// Direcciones IP productivas conocidas.
  static const Set<String> forbiddenIps = {'31.97.99.70'};

  /// Motivo de rechazo de [uri] para un build UAT, o `null` si es aceptable.
  ///
  /// Es una función pura: no lanza. Útil para pruebas y diagnósticos.
  static String? rejectionReason(Uri uri) {
    if (!uri.hasScheme) return 'URL_WITHOUT_SCHEME';
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'URL_INVALID_SCHEME';
    }
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return 'URL_WITHOUT_HOST';

    if (forbiddenIps.contains(host)) return 'URL_POINTS_TO_PRODUCTION';
    if (forbiddenHosts.contains(host)) return 'URL_POINTS_TO_PRODUCTION';
    for (final suffix in forbiddenHostSuffixes) {
      if (host.endsWith(suffix)) return 'URL_POINTS_TO_PRODUCTION';
    }

    if (!allowedHosts.contains(host)) return 'URL_MUST_BE_LOCAL';

    // Puerto explícito obligatorio: un `http://127.0.0.1` sin puerto iría al 80,
    // que no es el backend UAT.
    if (!uri.hasPort) return 'URL_PORT_REQUIRED';
    if (!allowedPorts.contains(uri.port)) return 'URL_PORT_NOT_ALLOWED';

    return null;
  }

  /// Valida [raw] y devuelve la URL normalizada, o lanza [StateError].
  ///
  /// El mensaje empieza por `UAT_CONFIG_REFUSED` para que sea inequívoco en
  /// cualquier visor de errores o registro.
  static String requireAllowedUrl(String raw, {required String key}) {
    final value = raw.trim();
    if (value.isEmpty) {
      throw StateError(
        'UAT_CONFIG_REFUSED (${key}_REQUIRED): el perfil UAT exige $key '
        'explícita. No se usa ningún valor por defecto y no se contactará con '
        'ningún backend remoto.',
      );
    }

    final uri = Uri.tryParse(value);
    if (uri == null) {
      throw StateError(
        'UAT_CONFIG_REFUSED (${key}_INVALID): "$value" no es una URL válida.',
      );
    }

    final reason = rejectionReason(uri);
    if (reason != null) {
      throw StateError(
        'UAT_CONFIG_REFUSED ($key/$reason): "$value" no está permitido en un '
        'build UAT. Solo se admiten hosts locales (${allowedHosts.join(', ')}) '
        'en el puerto ${allowedPorts.join(', ')}.',
      );
    }

    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  /// Comprueba un [Uri] ya construido (p. ej. el destino real de una petición).
  ///
  /// [uat] permite inyectar el modo en pruebas: en producción se omite y manda
  /// la constante de compilación.
  static void assertAllowedUri(Uri uri, {required String key, bool? uat}) {
    if (!(uat ?? isUat)) return;
    final reason = rejectionReason(uri);
    if (reason != null) {
      throw StateError(
        'UAT_CONFIG_REFUSED ($key/$reason): destino no permitido en UAT '
        '"${uri.toString()}". Petición bloqueada antes de enviarse.',
      );
    }
  }
}
