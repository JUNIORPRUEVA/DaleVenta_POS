import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';

/// Preasociación empresa ↔ RNC antes de abrir el asistente DOSA.
///
/// El backend es quien decide la empresa (por el token) y el RNC (por el
/// expediente fiscal). Este cliente **no envía** ni `companyId` ni un RNC que
/// pretenda ser identidad: solo pide registrar la intención y leer su estado.
class DosaCertificationIntent {
  const DosaCertificationIntent({
    required this.companyId,
    required this.rnc,
    required this.sessionId,
    required this.attemptNo,
    required this.created,
    required this.status,
    required this.provider,
    required this.ecfEnabled,
  });

  final String companyId;
  final String rnc;
  final String sessionId;
  final int attemptNo;
  final bool created;
  final String status;
  final String provider;
  final bool ecfEnabled;

  /// SIEMPRE `false`: preparar la certificación no autoriza a emitir.
  bool get fiscalAuthorizationGranted => false;

  factory DosaCertificationIntent.fromJson(Map<String, dynamic> json) {
    return DosaCertificationIntent(
      companyId: '${json['companyId'] ?? ''}',
      rnc: '${json['rnc'] ?? ''}',
      sessionId: '${json['sessionId'] ?? ''}',
      attemptNo: (json['attemptNo'] as num?)?.toInt() ?? 0,
      created: json['created'] == true,
      status: '${json['status'] ?? ''}',
      provider: '${json['provider'] ?? ''}',
      ecfEnabled: json['ecfEnabled'] == true,
    );
  }
}

/// Estado interno de la preparación, para consultarlo al volver al sistema.
/// Modo de integración DOSA que el backend declara para la empresa.
///
/// Es la ÚNICA fuente de verdad para elegir la ruta. El cliente no deduce el
/// modo a partir de un código de error: un error desconocido no autoriza a
/// continuar por otra vía.
enum DosaCertificationMode {
  /// El backend puede abrir (o reutilizar) la sesión privada de DOSA.
  privateSession,

  /// El backend no puede abrir sesiones: la ruta oficial es el portal con
  /// boleto de un solo uso y el asistente público.
  publicPortal,

  /// Backend antiguo o respuesta incompleta: se intenta la sesión privada y
  /// **solo** un estado explícito de la apertura deshabilitada permite el
  /// portal. Un error de transporte no habilita nada.
  unknown;

  static DosaCertificationMode parse(Object? raw) {
    switch ('${raw ?? ''}'.trim()) {
      case 'PRIVATE_SESSION':
        return DosaCertificationMode.privateSession;
      case 'PUBLIC_PORTAL':
        return DosaCertificationMode.publicPortal;
      default:
        return DosaCertificationMode.unknown;
    }
  }
}

class DosaIntentState {
  const DosaIntentState({
    required this.canonicalRnc,
    required this.canonicalSource,
    required this.ecfEnabled,
    required this.provider,
    required this.canRegister,
    required this.blockingReasons,
    required this.sessionStatus,
    required this.sessionAttemptNo,
    required this.sessionId,
    required this.sessionReusable,
    required this.credentialStatus,
    required this.historicalReviewRequired,
    this.certificationMode = DosaCertificationMode.unknown,
  });

  final String? canonicalRnc;
  final String? canonicalSource;
  final bool ecfEnabled;
  final String provider;
  final bool canRegister;
  final List<String> blockingReasons;
  final String? sessionStatus;
  final int? sessionAttemptNo;
  final String? sessionId;

  /// El backend ya confirmó que la sesión emitida sigue vigente y puede
  /// reanudarse aunque la autorización de creación haya expirado.
  final bool sessionReusable;
  final String? credentialStatus;

  /// El backend marca esto solo cuando una reconciliación histórica sigue
  /// necesitando la acción administrativa explícita. No autoriza nada.
  final bool historicalReviewRequired;

  /// Modo que el backend declara para esta empresa. Decide la ruta: sesión
  /// privada o portal público con boleto.
  final DosaCertificationMode certificationMode;

  /// SIEMPRE `false`.
  bool get fiscalAuthorizationGranted => false;

  factory DosaIntentState.fromJson(Map<String, dynamic> json) {
    final session = json['session'];
    final sessionMap = session is Map<String, dynamic> ? session : null;
    final credentials = json['credentials'];
    final credentialMap = credentials is Map<String, dynamic>
        ? credentials
        : null;
    final reasons = json['blockingReasons'];
    return DosaIntentState(
      canonicalRnc: json['canonicalRnc'] as String?,
      canonicalSource: json['canonicalSource'] as String?,
      ecfEnabled: json['ecfEnabled'] == true,
      provider: '${json['provider'] ?? ''}',
      canRegister: json['canRegister'] == true,
      blockingReasons: reasons is List
          ? reasons.map((item) => '$item').toList(growable: false)
          : const <String>[],
      sessionStatus: sessionMap?['status'] as String?,
      sessionAttemptNo: (sessionMap?['attemptNo'] as num?)?.toInt(),
      sessionId: sessionMap?['id'] as String?,
      sessionReusable: sessionMap?['reusable'] == true,
      credentialStatus: credentialMap?['status'] as String?,
      historicalReviewRequired: json['historicalReviewRequired'] == true,
      certificationMode: DosaCertificationMode.parse(json['certificationMode']),
    );
  }
}

/// Texto para el administrador a partir del código del backend.
///
/// Fuente única: lo usan tanto la excepción como el aviso del expediente, así
/// que un mismo motivo nunca se explica de dos formas distintas.
String dosaIntentReasonMessage(String code) {
  switch (code) {
    case 'COMPANY_RNC_NOT_VERIFIED':
      return 'La empresa no tiene un RNC verificado en su expediente fiscal.';
    case 'RNC_DOES_NOT_MATCH_COMPANY_IDENTITY':
      return 'El RNC de la empresa no coincide con el del expediente fiscal.';
    case 'AMBIGUOUS_RNC':
      return 'Otra empresa comparte este RNC. La asociación automática está bloqueada.';
    case 'ECF_DOSA_INTENT_IN_PROGRESS':
      return 'Ya hay una preparación en curso para esta empresa.';
    case 'SESSION_CLAIM_FAILED':
      return 'No se pudo registrar la intención. Inténtalo de nuevo en unos segundos.';
    case 'ECF_DOSA_INTENT_UNAUTHENTICATED':
      return 'La sesión no es válida. Vuelve a iniciar sesión.';
    case 'DOSA_HISTORICAL_TRANSITION_ADMIN_REQUIRED':
      return 'Solo un administrador autorizado puede aprobar esta transición.';
    case 'DOSA_HISTORICAL_TRANSITION_DISABLED':
      return 'La autorización de transiciones históricas no está habilitada.';
    case 'DOSA_HISTORICAL_TRANSITION_EVIDENCE_REQUIRED':
      return 'Faltan la referencia de aprobación o el motivo de la autorización.';
    case 'DOSA_HISTORICAL_TRANSITION_INTENT_NOT_FOUND':
      return 'El expediente ya no está disponible. Actualiza el estado.';
    case 'DOSA_HISTORICAL_TRANSITION_STATE_UNSAFE':
      return 'El expediente cambió: actualiza el estado antes de volver a intentarlo.';
    case 'DOSA_HISTORICAL_TRANSITION_NOT_RECONCILED':
      return 'Este expediente no requiere una autorización histórica.';
    case 'DOSA_HISTORICAL_TRANSITION_ALREADY_AUTHORIZED':
      return 'La transición ya tiene una autorización vigente.';
    default:
      // Sin interpolación: un código interno no es un mensaje de usuario.
      // El código sigue disponible en `DosaIntentException.code` para soporte.
      return 'No se pudo registrar la intención de certificación. Inténtalo de nuevo.';
  }
}

/// Error con el código del backend, para poder mostrar el motivo exacto sin
/// inventarlo en el cliente.
class DosaIntentException implements Exception {
  DosaIntentException(this.code);
  final String code;

  /// Texto para el administrador. Sin datos sensibles.
  String get message => dosaIntentReasonMessage(code);

  @override
  String toString() => 'DosaIntentException($code)';
}

class DosaCertificationIntentApi {
  DosaCertificationIntentApi(this._dio);

  final Dio _dio;

  /// Registra la intención. Idempotente: repetir devuelve la misma sesión.
  Future<DosaCertificationIntent> register({String? rnc}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.ecfDosaCertificationIntent,
        data: <String, dynamic>{
          // Solo se envía si ya lo tenemos: el backend lo compara, no lo acepta.
          if (rnc != null && rnc.trim().isNotEmpty) 'rnc': rnc.trim(),
        },
      );
      return DosaCertificationIntent.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  /// Consulta el estado interno de la preparación.
  Future<DosaIntentState> state() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        ApiRoutes.ecfDosaCertificationIntent,
      );
      return DosaIntentState.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  /// Autoriza la transición de un expediente histórico reconciliado.
  ///
  /// Solo un administrador con `manageEcfOnboarding` puede llegar aquí; el
  /// backend vuelve a verificarlo y exige la confirmación literal. La acción
  /// únicamente deja auditoría: no emite, no activa y no llama a DOSA.
  Future<void> authorizeHistoricalTransition({
    required String intentId,
    required String ownerApprovalReference,
    required String reason,
  }) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        ApiRoutes.ecfDosaAuthorizeHistoricalTransition,
        data: <String, dynamic>{
          'intentId': intentId,
          'ownerApprovalReference': ownerApprovalReference.trim(),
          'reason': reason.trim(),
          'confirmation': 'AUTHORIZE_HISTORICAL_TRANSITION',
        },
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  DosaIntentException _mapError(DioException error) {
    final status = error.response?.statusCode;
    final data = error.response?.data;
    final code = data is Map && data['message'] is String
        ? data['message'] as String
        : data is Map &&
              data['message'] is List &&
              (data['message'] as List).isNotEmpty
        ? '${(data['message'] as List).first}'
        : status == 401
        ? 'ECF_DOSA_INTENT_UNAUTHENTICATED'
        : 'HTTP_$status';
    return DosaIntentException(code);
  }
}

final dosaCertificationIntentApiProvider = Provider<DosaCertificationIntentApi>(
  (ref) {
    return DosaCertificationIntentApi(ref.watch(dioProvider));
  },
);

/// Estado de la preparación. Se invalida para refrescar tras registrar.
final dosaIntentStateProvider = FutureProvider.autoDispose<DosaIntentState>((
  ref,
) {
  return ref.watch(dosaCertificationIntentApiProvider).state();
});

/// Registro de la intención. **No se ejecuta al abrir el expediente**: la
/// sección del asistente solo lo observa cuando el administrador pulsa
/// «Preparar certificación con DOSA». Abrir una pantalla informativa nunca
/// escribe nada en el backend.
///
/// Es `autoDispose` y está indexado por el RNC que ya tenemos de la
/// configuración: si la empresa cambia, se registra la nueva. Repetir el registro
/// es idempotente en el backend (devuelve la misma sesión con `created: false`).
final dosaIntentRegistrationProvider = FutureProvider.autoDispose
    .family<DosaCertificationIntent, String>((ref, taxId) {
      return ref.watch(dosaCertificationIntentApiProvider).register(rnc: taxId);
    });
