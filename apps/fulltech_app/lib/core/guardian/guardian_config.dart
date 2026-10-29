import 'package:flutter/foundation.dart';

import 'guardian_runtime_env.dart';

/// Configuración del cliente Guardian en la app POS.
///
/// **Desactivado por defecto**: en un build sin `--dart-define` no se captura ni
/// se envía nada, por lo que las versiones ya instaladas no cambian su comportamiento.
class GuardianConfig {
  const GuardianConfig({
    required this.enabled,
    required this.endpointPath,
    required this.maxEvents,
    required this.maxBytes,
    required this.batchSize,
    required this.minSeverityToPersist,
    required this.sampleRateSev3Sev4,
    required this.flushInterval,
    this.baseUrl = '',
    this.useMachineApi = false,
    this.enrollmentCode = '',
    this.enrollmentCodeFile = '',
    this.selfTest = false,
  });

  /// Interruptor maestro.
  final bool enabled;

  /// Ruta relativa al `baseUrl` del API.
  final String endpointPath;

  /// Límite de eventos almacenados localmente.
  final int maxEvents;

  /// Límite de bytes almacenados localmente.
  final int maxBytes;

  /// Tamaño máximo de lote por envío.
  final int batchSize;

  /// Severidad mínima que se persiste (SEV1..SEV4).
  final String minSeverityToPersist;

  /// Muestreo para SEV3/SEV4 (1.0 = todos).
  final double sampleRateSev3Sev4;

  /// Periodicidad del flush automático.
  final Duration flushInterval;

  /// URL base de Guardian. Vacío = usar la del API del POS (`Env.apiBaseUrl`).
  final String baseUrl;

  /// Usa el endpoint de ingesta con credencial de instalación
  /// (`/guardian/machine/incidents`) en lugar del JWT de sesión.
  final bool useMachineApi;

  /// Código de enrolamiento de un solo uso (VACÍO en builds de cliente).
  ///
  /// **Nunca se compila dentro del ejecutable.** Solo se usa si el proceso ya
  /// lo trae en el entorno en tiempo de ejecución (ver `enrollmentCodeFile`).
  final String enrollmentCode;

  /// Ruta a un archivo que contiene el código de enrolamiento de un solo uso.
  ///
  /// La ruta no es un secreto (se puede compilar); el código sí, y se lee en
  /// tiempo de ejecución. Tras canjearlo el archivo se elimina.
  final String enrollmentCodeFile;

  /// Sonda sintética de UAT: provoca **un** fallo técnico controlado al arrancar.
  /// Solo existe si se compila explícitamente con `--dart-define`.
  final bool selfTest;

  static const String machineEndpointPath = '/guardian/machine/incidents';

  /// Ruta efectiva de ingesta según el modo configurado.
  String get effectiveEndpointPath =>
      useMachineApi ? machineEndpointPath : endpointPath;

  static const GuardianConfig disabled = GuardianConfig(
    enabled: false,
    endpointPath: '/guardian/incidents',
    maxEvents: 200,
    maxBytes: 5 * 1024 * 1024,
    batchSize: 20,
    minSeverityToPersist: 'SEV3',
    sampleRateSev3Sev4: 0.25,
    flushInterval: Duration(minutes: 2),
  );

  /// Lee los flags de compilación (`--dart-define`). Sin defines → desactivado.
  factory GuardianConfig.fromEnvironment() {
    const enabled = bool.fromEnvironment('GUARDIAN_ENABLED', defaultValue: false);
    if (!enabled) return GuardianConfig.disabled;

    return GuardianConfig(
      enabled: true,
      endpointPath: String.fromEnvironment(
        'GUARDIAN_ENDPOINT_PATH',
        defaultValue: '/guardian/incidents',
      ),
      maxEvents: int.fromEnvironment('GUARDIAN_MAX_EVENTS', defaultValue: 200),
      maxBytes: int.fromEnvironment('GUARDIAN_MAX_BYTES', defaultValue: 5242880),
      batchSize: int.fromEnvironment('GUARDIAN_BATCH_SIZE', defaultValue: 20),
      minSeverityToPersist: String.fromEnvironment(
        'GUARDIAN_MIN_SEVERITY',
        defaultValue: 'SEV3',
      ),
      sampleRateSev3Sev4: _readDouble(
        const String.fromEnvironment('GUARDIAN_SAMPLE_SEV34', defaultValue: '0.25'),
        0.25,
      ),
      flushInterval: Duration(seconds: _resolveFlushSeconds()),
      baseUrl: const String.fromEnvironment('GUARDIAN_BASE_URL', defaultValue: ''),
      useMachineApi: const bool.fromEnvironment('GUARDIAN_USE_MACHINE_API', defaultValue: false),
      // El código NUNCA se compila: solo la ruta del archivo que lo contiene.
      enrollmentCodeFile:
          const String.fromEnvironment('GUARDIAN_ENROLLMENT_CODE_FILE', defaultValue: ''),
      selfTest: const bool.fromEnvironment('GUARDIAN_SELFTEST', defaultValue: false),
    );
  }

  bool get isPersistenceSupported => !kIsWeb;
  int severityRank(String value) {
    switch (value) {
      case 'SEV1':
        return 1;
      case 'SEV2':
        return 2;
      case 'SEV3':
        return 3;
      case 'SEV4':
        return 4;
      default:
        return 4;
    }
  }

  bool shouldPersist(String severity) {
    return severityRank(severity) <= severityRank(minSeverityToPersist);
  }
}

double _readDouble(String raw, double fallback) {
  final parsed = double.tryParse(raw.trim());
  if (parsed == null || parsed.isNaN) return fallback;
  return parsed.clamp(0.0, 1.0);
}

/// Cadencia del envío periódico.
///
/// Se puede ajustar **en tiempo de ejecución** con la variable de entorno
/// `GUARDIAN_FLUSH_SECONDS` (operación de UAT/piloto sin recompilar) y, si no
/// existe, con `--dart-define=GUARDIAN_FLUSH_SECONDS`.
int _resolveFlushSeconds() {
  const compileTime = int.fromEnvironment('GUARDIAN_FLUSH_SECONDS', defaultValue: 120);
  final fromEnv = int.tryParse(guardianRuntimeEnv('GUARDIAN_FLUSH_SECONDS') ?? '');
  final value = fromEnv ?? compileTime;
  if (value < 5) return 5;
  if (value > 3600) return 3600;
  return value;
}
