import 'package:flutter/foundation.dart';

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
      flushInterval: Duration(minutes: 2),
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
