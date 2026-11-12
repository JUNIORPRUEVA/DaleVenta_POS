import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';

enum DosaDiagnosticFailure { accessDenied, companyMismatch, unavailable }

class DosaDiagnosticException implements Exception {
  const DosaDiagnosticException(this.failure);

  final DosaDiagnosticFailure failure;
}

class DosaDiagnosticAttempt {
  const DosaDiagnosticAttempt({
    required this.number,
    required this.status,
    required this.recordedProvider,
    required this.effectiveProvider,
    required this.hasEffectiveAttribution,
    required this.hasProviderSessionUrl,
    required this.hasProviderPostulationId,
  });

  final int number;
  final String status;
  final String recordedProvider;
  final String effectiveProvider;
  final bool hasEffectiveAttribution;
  final bool hasProviderSessionUrl;
  final bool hasProviderPostulationId;
}

class DosaCertificationDiagnostic {
  const DosaCertificationDiagnostic({
    required this.companyId,
    required this.attempt,
    required this.providerHistory,
  });

  final String companyId;
  final DosaDiagnosticAttempt? attempt;
  final List<String> providerHistory;

  /// Misma regla conservadora que la compuerta de tickets del backend.
  bool get requiresReconciliation =>
      attempt != null &&
      (attempt!.effectiveProvider != 'DOSA' ||
          (!attempt!.hasEffectiveAttribution &&
              (providerHistory.isEmpty ||
                  providerHistory.any((provider) => provider != 'DOSA'))));

  factory DosaCertificationDiagnostic.fromJson(Map<String, dynamic> json) {
    final companyId = json['companyId'];
    final rawAttempt = json['intention'];
    final rawHistory = json['audit'];
    if (companyId is! String ||
        companyId.trim().isEmpty ||
        (rawAttempt != null && rawAttempt is! Map<String, dynamic>) ||
        rawHistory is! List) {
      throw const DosaDiagnosticException(DosaDiagnosticFailure.unavailable);
    }
    final attempt = rawAttempt as Map<String, dynamic>?;
    final number = (attempt?['attemptNo'] as num?)?.toInt();
    if (attempt != null && (number == null || number < 1)) {
      throw const DosaDiagnosticException(DosaDiagnosticFailure.unavailable);
    }
    return DosaCertificationDiagnostic(
      companyId: companyId,
      attempt: attempt == null
          ? null
          : DosaDiagnosticAttempt(
              number: number!,
              status: '${attempt['status'] ?? ''}',
              recordedProvider: '${attempt['recordedProvider'] ?? ''}',
              effectiveProvider:
                  '${attempt['effectiveProvider'] ?? attempt['recordedProvider'] ?? ''}',
              hasEffectiveAttribution: attempt.containsKey('effectiveProvider'),
              hasProviderSessionUrl: attempt['hasProviderSessionUrl'] == true,
              hasProviderPostulationId:
                  attempt['hasProviderPostulationId'] == true,
            ),
      providerHistory: List<String>.unmodifiable(
        rawHistory
            .where(
              (entry) =>
                  entry is! Map<String, dynamic> ||
                  entry['action'] == null ||
                  entry['action'] == 'ONBOARDING_STARTED',
            )
            .map((entry) {
              if (entry is! Map<String, dynamic>) return 'UNVERIFIED';
              return '${entry['recordedProvider'] ?? 'UNVERIFIED'}';
            }),
      ),
    );
  }
}

class DosaCertificationDiagnosticApi {
  const DosaCertificationDiagnosticApi(this._dio);

  final Dio _dio;

  Future<DosaCertificationDiagnostic> read() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        ApiRoutes.ecfDosaCertificationDiagnostic,
      );
      return DosaCertificationDiagnostic.fromJson(response.data ?? const {});
    } on DioException catch (error) {
      if (error.response?.statusCode == 401 ||
          error.response?.statusCode == 403) {
        throw const DosaDiagnosticException(DosaDiagnosticFailure.accessDenied);
      }
      throw const DosaDiagnosticException(DosaDiagnosticFailure.unavailable);
    }
  }
}

final dosaCertificationDiagnosticApiProvider =
    Provider<DosaCertificationDiagnosticApi>((ref) {
      return DosaCertificationDiagnosticApi(ref.watch(dioProvider));
    });

/// La empresa viene del JWT; la clave local impide mostrar una respuesta ajena
/// si la sesión cambia mientras la petición de solo lectura sigue en vuelo.
final dosaCertificationDiagnosticProvider = FutureProvider.autoDispose
    .family<DosaCertificationDiagnostic, String>((ref, companyId) async {
      final user = ref.watch(authStateProvider).user;
      if (user?.companyId?.trim() != companyId ||
          !hasUserPermission(user, AppPermission.manageEcfOnboarding)) {
        throw const DosaDiagnosticException(DosaDiagnosticFailure.accessDenied);
      }
      final result = await ref
          .watch(dosaCertificationDiagnosticApiProvider)
          .read();
      final currentUser = ref.read(authStateProvider).user;
      if (currentUser?.companyId?.trim() != companyId ||
          !hasUserPermission(currentUser, AppPermission.manageEcfOnboarding) ||
          result.companyId != companyId) {
        throw const DosaDiagnosticException(
          DosaDiagnosticFailure.companyMismatch,
        );
      }
      return result;
    });
