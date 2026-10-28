import 'dart:async';
import 'dart:convert';

import '../debug/app_error_reporter.dart';
import '../usage/client_telemetry_headers.dart';
import 'guardian_agent_log.dart';
import 'guardian_client.dart';
import 'guardian_event.dart';
import 'guardian_redaction.dart';

/// Puente entre el reportero de errores existente y la cola de Guardian.
///
/// No instala manejadores globales nuevos: escucha `AppErrorReporter.lastRecorded`,
/// que ya recibe `FlutterError.onError`, `PlatformDispatcher.onError`, la zona
/// raíz y los errores de UI/HTTP mapeados. Se usa `lastRecorded` (y no
/// `lastError`) para incluir los fallos **silenciosos**, que son justamente los
/// que la UI no muestra y la observabilidad sí necesita.
class GuardianReporter {
  GuardianReporter({required this.client});

  final GuardianClient client;

  Map<String, String>? _clientIdentity;
  bool _attached = false;
  DateTime? _lastEventAt;

  void attach() {
    if (_attached) return;
    _attached = true;
    AppErrorReporter.instance.lastRecorded.addListener(_onError);
    unawaited(_loadIdentity());
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    AppErrorReporter.instance.lastRecorded.removeListener(_onError);
  }

  Future<void> _loadIdentity() async {
    try {
      _clientIdentity = await ClientTelemetryHeaders.instance.headers();
    } catch (_) {
      _clientIdentity = const <String, String>{};
    }
  }

  void _onError() {
    final details = AppErrorReporter.instance.lastRecorded.value;
    if (details == null) return;
    // Evita reprocesar el mismo objeto en notificaciones repetidas.
    final signature = '${details.eventId}';
    if (_lastEventAt != null && _lastSignature == signature) return;
    _lastSignature = signature;
    _lastEventAt = DateTime.now();

    final event = toEvent(details);
    if (event == null) {
      unawaited(GuardianAgentLog.info(
        'evento descartado por el reportero kind=${details.kind.name} type=${details.errorType}',
      ));
      return;
    }
    unawaited(GuardianAgentLog.info(
      'evento convertido sev=${event.severity} mod=${event.module} op=${event.operation}',
    ));
    unawaited(client.record(event));
  }

  String? _lastSignature;

  /// Convierte un error de la app en un incidente de Guardian.
  /// Devuelve `null` para ruido esperado que no debe reportarse.
  GuardianEvent? toEvent(AppErrorDetails details) {
    final kind = details.kind;
    if (kind.name == 'media') return null;

    final module = moduleFor(details.endpointUrl, details.context);
    final severity = severityFor(details, module);
    final operation = operationFor(details);
    final stack = redactText(details.stackTrace, maxChars: 20000);
    final message = redactText(details.primaryTechnicalMessage, maxChars: 600);
    final correlationId = _extractRequestId(details.apiResponse);
    final identity = _clientIdentity ?? const <String, String>{};
    final now = DateTime.now();

    return GuardianEvent(
      eventId: _buildEventId(now),
      severity: severity,
      module: module,
      operation: operation,
      occurredAt: details.capturedAt,
      exceptionType: details.errorType,
      platform: identity['x-client-platform'],
      appVersion: identity['x-client-app-version'],
      deviceId: identity['x-client-device-id'],
      correlationId: correlationId,
      stack: stack.isEmpty ? null : stack,
      message: message.isEmpty ? null : message,
      context: <String, dynamic>{
        if (details.endpointUrl != null) 'endpoint': redactText(details.endpointUrl, maxChars: 200),
        if (details.method != null) 'method': details.method,
        'kind': kind.name,
        if (details.context != null) 'context': redactText(details.context, maxChars: 200),
        'severity': details.severity.name,
      },
    );
  }

  String _buildEventId(DateTime now) {
    final micros = now.microsecondsSinceEpoch.toRadixString(36);
    final salt = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'gd-$micros-$salt';
  }

  String moduleFor(String? endpointUrl, String? context) {
    final url = (endpointUrl ?? '').toLowerCase();
    final ctx = (context ?? '').toLowerCase();
    bool has(String needle) => url.contains(needle) || ctx.contains(needle);

    if (has('/cash')) return 'cash';
    if (has('/sales')) return 'sales';
    if (has('/sync') || has('sincroniz')) return 'sync';
    if (has('/license') || has('licencia')) return 'license';
    if (has('/app-updates') || has('/app_update') || has('actualizaci')) return 'updater';
    if (has('/auth') || has('/login') || has('session')) return 'auth';
    if (has('/products') || has('/inventory') || has('/warehouses')) return 'inventory';
    if (has('/reports')) return 'reporting';
    if (has('/tax') || has('/ncf') || has('/ecf')) return 'fiscal';
    if (has('print') || has('impresi')) return 'printing';
    return 'flutter';
  }

  String severityFor(AppErrorDetails details, String module) {
    if (details.severity == AppErrorSeverity.fatal) return 'SEV1';

    switch (details.kind.name) {
      case 'network':
      case 'timeout':
      case 'media':
        return 'SEV4';
      case 'server':
        return (module == 'cash' || module == 'sales' || module == 'fiscal') ? 'SEV1' : 'SEV2';
      case 'sync':
      case 'auth':
      case 'permission':
        return 'SEV2';
      case 'printing':
      default:
        return 'SEV3';
    }
  }

  String operationFor(AppErrorDetails details) {
    final method = (details.method ?? '').toUpperCase();
    final path = _normalizePath(details.endpointUrl ?? details.context ?? 'app');
    final operation = method.isEmpty ? path : '$method $path';
    return operation.length <= 80 ? operation : operation.substring(0, 80);
  }

  String _normalizePath(String raw) {
    var value = raw.trim();
    // Sin esquema ni host: la operación debe ser estable entre entornos.
    final authorityIndex = value.indexOf('://');
    if (authorityIndex >= 0) {
      final slashIndex = value.indexOf('/', authorityIndex + 3);
      value = slashIndex >= 0 ? value.substring(slashIndex) : '/';
    }
    final queryIndex = value.indexOf('?');
    if (queryIndex >= 0) value = value.substring(0, queryIndex);
    // Reemplaza identificadores (UUID / numéricos largos) por marcador.
    value = value.replaceAll(
      RegExp(r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'),
      ':id',
    );
    value = value.replaceAll(RegExp(r'/\d{3,}'), '/:id');
    if (value.length <= 120) return value;
    return value.substring(0, 120);
  }

  String? _extractRequestId(String? apiResponse) {
    if (apiResponse == null || apiResponse.isEmpty) return null;
    try {
      final decoded = jsonDecode(apiResponse);
      if (decoded is Map) {
        final id = decoded['requestId'] ?? decoded['request_id'];
        if (id is String && id.isNotEmpty) return id;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
