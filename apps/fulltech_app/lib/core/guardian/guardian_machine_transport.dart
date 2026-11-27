import 'package:dio/dio.dart';
import '../api/retry_after.dart';

import 'guardian_event.dart';
import 'guardian_transport.dart';

/// Interpreta la respuesta del endpoint de ingesta (común a ambos transportes).
GuardianSendResult parseGuardianIngestResponse(
  dynamic data,
  List<GuardianEvent> events,
) {
  final rawResults = data is Map ? data['results'] : null;
  final results = rawResults is List ? rawResults : null;
  if (results == null) {
    return const GuardianSendResult(
      retryable: true,
      reason: 'UNCONFIRMED_RESPONSE',
    );
  }

  final acked = <String>[];
  final duplicates = <String>[];
  final rejected = <String>[];
  String? reason;

  for (final item in results) {
    if (item is! Map) continue;
    final eventId = item['eventId']?.toString();
    final status = item['status']?.toString();
    if (eventId == null || eventId.isEmpty) continue;
    if (!events.any((event) => event.eventId == eventId) ||
        results
                .where((entry) => entry is Map && entry['eventId'] == eventId)
                .length !=
            1) {
      continue;
    }

    switch (status) {
      case 'accepted':
        acked.add(eventId);
        break;
      case 'duplicate':
        duplicates.add(eventId);
        break;
      case 'rejected':
        reason = item['reason']?.toString() ?? reason;
        // Validation is terminal; policy changes, quotas and DB failures are not.
        if (item['reason'] == 'INVALID_OCCURRED_AT') rejected.add(eventId);
        break;
      default:
        break;
    }
  }

  return GuardianSendResult(
    acked: acked,
    duplicates: duplicates,
    rejected: rejected,
    retryable:
        acked.length + duplicates.length + rejected.length < events.length,
    reason: reason,
    retryAfterMs: data is Map && data['retryAfterSeconds'] is num
        ? ((data['retryAfterSeconds'] as num) * 1000).toInt()
        : null,
  );
}

/// Transporte con **credencial de instalación** (`x-guardian-key`).
///
/// Se usa cuando la instalación ya está enrolada. Ventaja frente al JWT de
/// usuario: funciona antes del login (fallos de arranque, actualizador, SQLite)
/// y no depende de que haya una sesión activa.
///
/// Nunca incrusta un secreto: la credencial se obtiene por enrolamiento, caduca
/// y es revocable desde el servidor.
class MachineGuardianTransport implements GuardianTransport {
  MachineGuardianTransport({
    required this.baseUrl,
    required this.path,
    required this.credential,
    this.onCredentialRejected,
    Dio? dio,
    this.timeout = const Duration(seconds: 20),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
               validateStatus: (_) => true,
             ),
           );

  final String baseUrl;
  final String path;
  final String credential;

  /// Se invoca si el servidor rechaza la credencial (401/403): permite borrarla
  /// para que el siguiente arranque vuelva a enrolarse con un código válido.
  final Future<void> Function()? onCredentialRejected;

  final Duration timeout;
  final Dio _dio;

  @override
  Future<GuardianSendResult> send(List<GuardianEvent> events) async {
    if (events.isEmpty) return const GuardianSendResult(acked: []);
    if (credential.isEmpty) {
      return const GuardianSendResult(
        retryable: true,
        reason: 'SIN_CREDENCIAL',
      );
    }

    final normalizedBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    Response<dynamic> response;
    try {
      response = await _dio
          .post<dynamic>(
            '$normalizedBase$path',
            data: <String, dynamic>{
              'events': events.map((event) => event.toApiJson()).toList(),
            },
            options: Options(
              // El transporte decide el resultado a partir del código HTTP:
              // no debe depender de la `validateStatus` del Dio inyectado.
              validateStatus: (_) => true,
              headers: <String, String>{
                'x-guardian-key': credential,
                'x-guardian-ts':
                    '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
                'content-type': 'application/json',
              },
            ),
          )
          .timeout(timeout);
    } on DioException catch (error) {
      return GuardianSendResult(retryable: true, reason: error.type.name);
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      return parseGuardianIngestResponse(response.data, events);
    }
    if (status == 401 || status == 403) {
      await onCredentialRejected?.call();
      return GuardianSendResult(retryable: true, reason: 'HTTP_$status');
    }

    if (status == 400 || status == 413 || status == 422) {
      // Credencial inválida/caducada o lote rechazado: no reintentar en bucle.
      if (status == 401 || status == 403) {
        await onCredentialRejected?.call();
      }
      return GuardianSendResult(
        rejected: events.map((event) => event.eventId).toList(),
        retryable: false,
        reason: 'HTTP_$status',
      );
    }

    return GuardianSendResult(
      retryable: true,
      reason: 'HTTP_$status',
      retryAfterMs: parseRetryAfter(
        response.headers.value('retry-after'),
      )?.inMilliseconds,
    );
  }
}
