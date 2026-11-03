/// Blindaje del perfil UAT de la aplicación.
///
/// Motivo: `Env.apiBaseUrl` usa `ProductConfig.productionApiBaseUrl` como valor
/// por defecto cuando `API_BASE_URL` falta o es inválida. Ese comportamiento es
/// correcto para un build comercial (nunca queda sin backend), pero es
/// **peligroso en un build de validación**: un `--dart-define` olvidado hacía que
/// la aplicación de pruebas hablara con producción.
///
/// Este archivo se aplica **exclusivamente** cuando el build se compila con
/// `--dart-define=FULLPOS_UAT_PROFILE=true`. Con el perfil activo:
///
/// - `API_BASE_URL` es obligatoria,
/// - solo se admite un host local (`localhost` / `127.0.0.1` / `::1`),
/// - se rechazan los hosts productivos conocidos,
/// - **no existe ninguna URL por defecto**,
/// - un valor ausente o inválido **falla de forma visible** (excepción), nunca
///   cae en silencio a un backend remoto.
///
/// Los builds comerciales no pasan por aquí: `isUatProfile` es `false` por
/// defecto, así que su comportamiento permanece intacto.
class UatApiConfig {
  UatApiConfig._();

  /// Compile-time flag. `false` en cualquier build comercial.
  static const bool isUatProfile = bool.fromEnvironment(
    'FULLPOS_UAT_PROFILE',
    defaultValue: false,
  );

  /// Únicos hosts admitidos en el perfil UAT: la máquina local.
  static const Set<String> allowedHosts = {'localhost', '127.0.0.1', '::1'};

  /// Marcadores de infraestructura remota/productiva. Comparados en minúsculas
  /// contra la URL completa, no solo contra el host, para no depender de cómo se
  /// escribió la URL.
  static const List<String> forbiddenMarkers = [
    'gcdndd',
    'easypanel',
    'hostinger',
    '31.97.99.70',
    'phytoemagry',
    'ventas-fullpos-backend',
  ];

  /// Motivo por el que [raw] no sirve para un build UAT, o `null` si es válida.
  static String? rejectionReason(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return 'API_BASE_URL_REQUIRED';
    }

    final lowered = value.toLowerCase();
    for (final marker in forbiddenMarkers) {
      if (lowered.contains(marker)) {
        return 'API_BASE_URL_POINTS_TO_REMOTE';
      }
    }

    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return 'API_BASE_URL_INVALID';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'API_BASE_URL_INVALID_SCHEME';
    }

    final host = uri.host.trim().toLowerCase();
    if (!allowedHosts.contains(host)) {
      return 'API_BASE_URL_MUST_BE_LOCAL';
    }

    return null;
  }

  /// URL del backend para el perfil UAT.
  ///
  /// Lanza [StateError] si [raw] no es válida: en el perfil UAT es preferible un
  /// fallo visible a una aplicación de pruebas conectada a otro backend.
  static String resolve(String raw, {String key = 'API_BASE_URL'}) {
    final reason = rejectionReason(raw);
    if (reason != null) {
      throw StateError(
        'UAT_${key}_REFUSED ($reason): el perfil UAT exige una $key local '
        'explícita. No se usa ningún valor por defecto.',
      );
    }

    final value = raw.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  // ---------------------------------------------------------------------------
  // Políticas del perfil UAT para servicios que NO son el backend.
  //
  // Se exponen como funciones puras con [uatProfile] inyectable para poder
  // probarlas sin recompilar la aplicación: `isUatProfile` es una constante de
  // compilación y en las pruebas vale `false`. En producción se usa el valor por
  // defecto, que es el flag real del build.
  // ---------------------------------------------------------------------------

  /// ¿Se permiten actualizaciones COMERCIALES en este build?
  ///
  /// Nunca en el perfil UAT: una aplicación de validación no debe descargar ni
  /// instalar el artefacto comercial, aunque tenga configurado un servidor de
  /// releases accesible.
  static bool commercialUpdatesAllowed(
    bool configuredInBuild, {
    bool? uatProfile,
  }) {
    if (uatProfile ?? isUatProfile) return false;
    return configuredInBuild;
  }

  /// Hosts desde los que se permite descargar un instalador.
  ///
  /// En el perfil UAT no hay ninguno por defecto: el host comercial de
  /// almacenamiento no debe ser alcanzable desde una validación. Un operador
  /// puede declarar uno local explícitamente en [configured], que se respeta.
  static Set<String> allowedUpdateDownloadHosts(
    Set<String> configured, {
    bool? uatProfile,
  }) {
    if (uatProfile ?? isUatProfile) {
      return configured
          .map((entry) => entry.trim().toLowerCase())
          .where((entry) => entry.isNotEmpty && allowedHosts.contains(entry))
          .toSet();
    }
    return configured;
  }

  /// Identificador de analítica comercial (por ejemplo Meta Pixel).
  ///
  /// [null] en el perfil UAT: un build de validación no envía eventos a
  /// servicios de marketing externos.
  static String? commercialAnalyticsId(String? configured, {bool? uatProfile}) {
    if (uatProfile ?? isUatProfile) return null;
    return configured;
  }
}
