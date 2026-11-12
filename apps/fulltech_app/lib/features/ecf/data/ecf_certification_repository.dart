import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../ecf_certification_models.dart';

/// Operaciones de la Postulación Inteligente sobre el motor EXISTENTE.
///
/// No inventa rutas: usa `GET /ecf/dgii/preparation`, `POST /ecf/dgii/activation/start`
/// y `GET /ecf/dgii/activation`, que son las que ya existen en el API.
class EcfCertificationRepository {
  EcfCertificationRepository(this._dio);

  final Dio _dio;

  Future<EcfPreparationMetadata> preparation() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiPreparation);
    final data = res.data;
    if (data is Map) {
      return EcfPreparationMetadata.fromJson(data.cast<String, dynamic>());
    }
    return const EcfPreparationMetadata(
      videoUrl: null,
      simulationAvailable: false,
      simulationBadge: 'MODO DE PRUEBA — NO SE ENVIARÁ NADA A DGII',
      simulationReason: null,
    );
  }

  /// Arranca o continúa el motor. Es idempotente en el servidor.
  Future<void> start() async {
    await _dio.post(ApiRoutes.ecfDgiiActivationStart);
  }

  Future<EcfActivationProgress> progress() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiActivation);
    final data = res.data;
    if (data is Map) {
      return EcfActivationProgress.fromJson(data.cast<String, dynamic>());
    }
    throw const FormatException('ECF_ACTIVATION_PROGRESS_INVALID');
  }

  /// Incorpora el XML de postulación. El servidor valida estructura y seguridad.
  /// Devuelve el estado resultante (`VALIDATED`) y las notas del backend.
  Future<EcfPostulationXmlResult> uploadPostulationXml({
    required List<int> bytes,
    required String fileName,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType('application', 'xml'),
      ),
    });
    final res = await _dio.post(ApiRoutes.ecfDgiiPostulationXml, data: form);
    final data = res.data;
    final map = data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{};
    return EcfPostulationXmlResult.fromJson(map);
  }

  /// Intentos bloqueados que necesitan reconciliación (solo de esta empresa).
  Future<List<EcfBlockedAttempt>> blockedAttempts() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiCertificationAttempts);
    final data = res.data;
    if (data is! List) return const <EcfBlockedAttempt>[];
    return data
        .whereType<Map>()
        .map((row) => EcfBlockedAttempt.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// Reconciliación explícita. Nunca es un «reintentar»: exige una decisión.
  Future<String> resolveAttempt({
    required String attemptId,
    required String decision,
    String? evidenceRef,
    String? note,
    String? externalId,
  }) async {
    final res = await _dio.post(
      ApiRoutes.ecfDgiiCertificationAttemptResolve(attemptId),
      data: {
        'decision': decision,
        if (evidenceRef != null && evidenceRef.trim().isNotEmpty)
          'evidenceRef': evidenceRef.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (externalId != null && externalId.trim().isNotEmpty)
          'externalId': externalId.trim(),
      },
    );
    final data = res.data;
    final map = data is Map
        ? data.cast<String, dynamic>()
        : const <String, dynamic>{};
    // Un rechazo del backend no se puede presentar como éxito: si `ok` no es
    // exactamente `true`, la decisión NO quedó registrada.
    if (map['ok'] != true) {
      throw Exception(
        (map['message'] as String?)?.trim().isNotEmpty == true
            ? map['message'] as String
            : 'La decisión no quedó registrada.',
      );
    }
    return (map['status'] as String?) ?? '';
  }
}

final ecfCertificationRepositoryProvider = Provider<EcfCertificationRepository>(
  (ref) => EcfCertificationRepository(ref.watch(dioProvider)),
);

final ecfPreparationProvider =
    FutureProvider.autoDispose<EcfPreparationMetadata>(
      (ref) => ref.watch(ecfCertificationRepositoryProvider).preparation(),
    );

/// Progreso del motor: al reabrir la aplicación se recupera desde el servidor.
final ecfActivationProgressProvider =
    FutureProvider.autoDispose<EcfActivationProgress>(
      (ref) => ref.watch(ecfCertificationRepositoryProvider).progress(),
    );
