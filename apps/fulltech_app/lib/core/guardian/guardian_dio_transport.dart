import 'package:dio/dio.dart';

import 'guardian_event.dart';
import 'guardian_transport.dart';

/// Transporte HTTP hacia `POST /guardian/incidents`.
///
/// Interpreta la respuesta del servidor por evento (aceptado / duplicado /
/// rechazado) y clasifica el fallo global como recuperable o permanente.
class DioGuardianTransport implements GuardianTransport {
  DioGuardianTransport({
    required this.baseUrl,
    required this.path,
    required Future<String?> Function() tokenProvider,
    Dio? dio,
    this.timeout = const Duration(seconds: 20),
  })  : _tokenProvider = tokenProvider,
        _dio = dio ??
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
  final Dio _dio;
  final Duration timeout;
  final Future<String?> Function() _tokenProvider;

  @override
  Future<GuardianSendResult> send(List<GuardianEvent> events) async {
    if (events.isEmpty) return const GuardianSendResult(acked: []);

    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      return const GuardianSendResult(retryable: true, reason: 'SIN_TOKEN');
    }

    Response<dynamic> response;
    try {
      response = await _dio
          .post<dynamic>(
            '$baseUrl$path',
            data: <String, dynamic>{
              'events': events.map((event) => event.toApiJson()).toList(),
            },
            options: Options(
              headers: <String, String>{
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            ),
          )
          .timeout(timeout);
    } on DioException catch (error) {
      return GuardianSendResult(retryable: true, reason: error.type.name);
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      return _parseSuccess(response.data, events);
    }

    if (status == 400 || status == 413 || status == 422) {
      return GuardianSendResult(
        rejected: events.map((event) => event.eventId).toList(),
        retryable: false,
        reason: 'HTTP_$status',
      );
    }

    return GuardianSendResult(retryable: true, reason: 'HTTP_$status');
  }

  GuardianSendResult _parseSuccess(dynamic data, List<GuardianEvent> events) {
    final result = data is Map ? (data['results'] as List?) : null;
    if (result == null) {
      // Servidor 2xx sin detalle: asumimos aceptados (contrato mínimo).
      return GuardianSendResult(acked: events.map((event) => event.eventId).toList());
    }

    final acked = <String>[];
    final duplicates = <String>[];
    final rejected = <String>[];
    String? reason;

    for (final item in result) {
      if (item is! Map) continue;
      final eventId = item['eventId']?.toString();
      final status = item['status']?.toString();
      if (eventId == null || eventId.isEmpty) continue;

      switch (status) {
        case 'accepted':
          acked.add(eventId);
          break;
        case 'duplicate':
          duplicates.add(eventId);
          break;
        case 'rejected':
          rejected.add(eventId);
          reason = item['reason']?.toString() ?? reason;
          break;
        default:
          break;
      }
    }

    return GuardianSendResult(
      acked: acked,
      duplicates: duplicates,
      rejected: rejected,
      retryable: false,
      reason: reason,
    );
  }
}
