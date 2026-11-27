import 'package:dio/dio.dart';

import 'guardian_event.dart';
import 'guardian_transport.dart';
import 'guardian_machine_transport.dart';
import 'guardian_identity.dart';
import '../api/retry_after.dart';

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
  }) : _tokenProvider = tokenProvider,
       _dio =
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
    if (events.any(
      (event) =>
          event.context?['_guardianCompanyId'] != null &&
          event.context?['_guardianCompanyId'] !=
              guardianCompanyFromToken(token),
    )) {
      return const GuardianSendResult(
        retryable: true,
        reason: 'COMPANY_SCOPE_CHANGED',
      );
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
      return parseGuardianIngestResponse(response.data, events);
    }

    if (status == 400 || status == 413 || status == 422) {
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
