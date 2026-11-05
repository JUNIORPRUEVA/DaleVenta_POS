import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';

/// Sesión de certificación emitida por DOSA para ESTA empresa.
///
/// El backend decide la empresa (por el token) y toma el RNC del expediente y el
/// correo de la configuración: la app no reenvía esos datos. `companyId` vuelve
/// en la respuesta para que el cliente compruebe que el enlace pertenece a la
/// empresa autenticada antes de abrirlo.
class DosaCertificationSession {
  const DosaCertificationSession({
    required this.companyId,
    required this.sessionUrl,
    required this.expiresAt,
    required this.attemptNo,
    required this.reused,
  });

  final String companyId;
  final String sessionUrl;
  final String expiresAt;
  final int attemptNo;

  /// `true` cuando el backend reutilizó una sesión vigente.
  final bool reused;

  factory DosaCertificationSession.fromJson(Map<String, dynamic> json) {
    return DosaCertificationSession(
      companyId: '${json['companyId'] ?? ''}',
      sessionUrl: '${json['sessionUrl'] ?? ''}',
      expiresAt: '${json['expiresAt'] ?? ''}',
      attemptNo: (json['attemptNo'] as num?)?.toInt() ?? 0,
      reused: json['reused'] == true,
    );
  }
}

/// Error con el código del backend, para explicar el motivo sin inventarlo.
class DosaCertificationSessionException implements Exception {
  DosaCertificationSessionException(this.code, {this.statusCode});

  final String code;
  final int? statusCode;

  /// La API de sesiones todavía no está habilitada (o no existe en esta
  /// versión del backend): se puede seguir con el asistente actual.
  bool get canFallBackToAssistant =>
      code == 'ECF_DOSA_SESSION_DISABLED' ||
      code == 'ECF_DOSA_SESSION_ENCRYPTION_NOT_CONFIGURED' ||
      code == 'HTTP_404' ||
      code == 'HTTP_501';

  String get message {
    switch (code) {
      case 'ECF_DOSA_SESSION_EMAIL_REQUIRED':
        return 'Configura el correo de facturación electrónica de la empresa '
            'antes de iniciar la postulación.';
      case 'ECF_DOSA_SESSION_EMAIL_INVALID':
        return 'El correo de facturación electrónica no es válido.';
      case 'ECF_DOSA_SESSION_RNC_REQUIRED':
        return 'La empresa no tiene un RNC verificado en su expediente fiscal.';
      case 'ECF_DOSA_SESSION_IN_PROGRESS':
        return 'Ya hay una apertura de sesión en curso para esta empresa.';
      case 'ECF_DOSA_SESSION_UNCERTAIN':
        return 'El proveedor no confirmó la sesión. No se reintenta '
            'automáticamente: revísalo con soporte.';
      case 'ECF_DOSA_SESSION_DISABLED':
        return 'La apertura automática aún no está habilitada.';
      case 'ECF_DOSA_SESSION_PROVIDER_ERROR':
        return 'El proveedor rechazó la apertura de la sesión.';
      case 'ECF_DOSA_SESSION_NOT_PERSISTED':
        return 'La sesión se creó pero no se pudo guardar. Revísalo con soporte.';
      case 'ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED':
        return 'Este expediente tiene una revisión histórica registrada. La '
            'apertura automática está bloqueada y requiere una operación '
            'explícita y auditada.';
      case 'ECF_DOSA_SESSION_EXPIRY_UNKNOWN':
        return 'Hay una sesión anterior sin fecha de vencimiento verificable. '
            'Revísala antes de abrir otra.';
      case 'ECF_DOSA_SESSION_ENCRYPTION_NOT_CONFIGURED':
        return 'La apertura automática aún no está configurada de forma segura.';
      case 'ECF_DOSA_SESSION_URL_UNREADABLE':
        return 'La sesión guardada no se pudo verificar. Revísala con soporte.';
      case 'ECF_DOSA_SESSION_UNAUTHENTICATED':
        return 'La sesión no es válida. Vuelve a iniciar sesión.';
      default:
        return 'No se pudo iniciar la postulación electrónica.';
    }
  }

  @override
  String toString() => 'DosaCertificationSessionException($code)';
}

class DosaCertificationSessionApi {
  DosaCertificationSessionApi(this._dio);

  final Dio _dio;

  /// Abre (o reutiliza) la sesión. Idempotente en el backend.
  Future<DosaCertificationSession> open() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.ecfDosaCertificationSession,
      );
      return DosaCertificationSession.fromJson(res.data ?? const {});
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  DosaCertificationSessionException _mapError(DioException error) {
    final status = error.response?.statusCode;
    final data = _decodedBody(error.response?.data);
    final code = data is Map && data['message'] is String
        ? data['message'] as String
        : data is Map &&
              data['message'] is List &&
              (data['message'] as List).isNotEmpty
        ? '${(data['message'] as List).first}'
        : status == 401
        ? 'ECF_DOSA_SESSION_UNAUTHENTICATED'
        : 'HTTP_$status';
    return DosaCertificationSessionException(code, statusCode: status);
  }

  /// El cuerpo del error puede llegar ya decodificado o como texto JSON.
  ///
  /// El backend responde `503 {"message":"ECF_DOSA_SESSION_DISABLED"}` cuando
  /// la apertura automática está apagada. Si el adaptador HTTP entrega ese
  /// cuerpo como cadena, `data['message']` no existe, el código se convertía en
  /// `HTTP_503` y el cliente **no** caía al asistente público: el administrador
  /// quedaba bloqueado sin abrir nada. Decodificar aquí mantiene el código real.
  static Object? _decodedBody(Object? data) {
    if (data is String) {
      final text = data.trim();
      if (text.startsWith('{') || text.startsWith('[')) {
        try {
          return jsonDecode(text);
        } catch (_) {
          return data;
        }
      }
    }
    return data;
  }
}

final dosaCertificationSessionApiProvider =
    Provider<DosaCertificationSessionApi>((ref) {
      return DosaCertificationSessionApi(ref.watch(dioProvider));
    });
