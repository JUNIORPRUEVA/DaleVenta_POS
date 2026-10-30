import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';

/// Versión del texto de consentimiento tal como la reporta el servidor.
///
/// El cliente NUNCA la inventa ni la fija en código: la recibe en el borrador.
/// Si el backend cambia el texto, la app lo muestra y envía la versión vigente.
Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map) return data.cast<String, dynamic>();
  return const <String, dynamic>{};
}

/// Borrador persistente del expediente + lo que falta para enviarlo.
class EcfApplicationDraft {
  const EcfApplicationDraft({
    required this.state,
    required this.draft,
    required this.missingFields,
    required this.draftUpdatedAt,
    required this.draftRevision,
    required this.currentSnapshotVersion,
    required this.consentVersion,
    required this.requiredConsentVersion,
    required this.consentPurpose,
  });

  final String state;
  final Map<String, dynamic>? draft;
  final List<String> missingFields;
  final DateTime? draftUpdatedAt;

  /// Revisión del borrador en el servidor. Se envía de vuelta en cada guardado
  /// para que un guardado tardío no pueda pisar uno más reciente.
  final int draftRevision;
  final int currentSnapshotVersion;
  final String? consentVersion;
  final String requiredConsentVersion;
  final String consentPurpose;

  bool get hasDraft => draft != null;
  bool get isComplete => missingFields.isEmpty && hasDraft;
  bool get consentAlreadyAccepted => consentVersion == requiredConsentVersion;

  String? read(String path) {
    final parts = path.split('.');
    dynamic current = draft;
    for (final part in parts) {
      if (current is! Map) return null;
      current = current[part];
    }
    return current is String && current.trim().isNotEmpty ? current : null;
  }

  factory EcfApplicationDraft.fromJson(Map<String, dynamic> json) {
    final rawDraft = json['draft'];
    final rawMissing = json['missingFields'];
    return EcfApplicationDraft(
      state: json['state'] is String ? json['state'] as String : 'NOT_STARTED',
      draft: rawDraft is Map ? rawDraft.cast<String, dynamic>() : null,
      missingFields: rawMissing is List
          ? rawMissing.whereType<String>().toList(growable: false)
          : const <String>[],
      draftUpdatedAt: json['draftUpdatedAt'] is String
          ? DateTime.tryParse(json['draftUpdatedAt'] as String)
          : null,
      draftRevision: json['draftRevision'] is num
          ? (json['draftRevision'] as num).toInt()
          : 0,
      currentSnapshotVersion: json['currentSnapshotVersion'] is num
          ? (json['currentSnapshotVersion'] as num).toInt()
          : 0,
      consentVersion: json['consentVersion'] as String?,
      requiredConsentVersion:
          (json['requiredConsentVersion'] as String?) ?? '',
      consentPurpose: (json['consentPurpose'] as String?) ?? '',
    );
  }
}

/// Resultado de un envío. `idempotent` significa que no se creó versión nueva.
class EcfApplicationSubmitResult {
  const EcfApplicationSubmitResult({
    required this.idempotent,
    required this.version,
    required this.state,
  });

  final bool idempotent;
  final int version;
  final String state;

  factory EcfApplicationSubmitResult.fromJson(Map<String, dynamic> json) {
    return EcfApplicationSubmitResult(
      idempotent: json['idempotent'] == true,
      version: json['version'] is num ? (json['version'] as num).toInt() : 0,
      state: (json['state'] as String?) ?? '',
    );
  }
}

/// Una versión enviada del expediente (histórico inmutable).
class EcfApplicationSnapshot {
  const EcfApplicationSnapshot({
    required this.version,
    required this.payloadHash,
    required this.documentsHash,
    required this.consentVersion,
    required this.submittedAt,
  });

  final int version;
  final String payloadHash;
  final String documentsHash;
  final String consentVersion;
  final DateTime? submittedAt;

  factory EcfApplicationSnapshot.fromJson(Map<String, dynamic> json) {
    return EcfApplicationSnapshot(
      version: json['version'] is num ? (json['version'] as num).toInt() : 0,
      payloadHash: (json['payloadHash'] as String?) ?? '',
      documentsHash: (json['documentsHash'] as String?) ?? '',
      consentVersion: (json['consentVersion'] as String?) ?? '',
      submittedAt: json['submittedAt'] is String
          ? DateTime.tryParse(json['submittedAt'] as String)
          : null,
    );
  }
}

final ecfApplicationRepositoryProvider = Provider<EcfApplicationRepository>((
  ref,
) {
  return EcfApplicationRepository(ref.watch(dioProvider));
});

/// Borrador actual del expediente de la empresa autenticada.
final ecfApplicationDraftProvider =
    FutureProvider.autoDispose<EcfApplicationDraft>((ref) {
      return ref.watch(ecfApplicationRepositoryProvider).draft();
    });

/// Cliente del expediente (borrador, envío y versiones).
///
/// La empresa sale siempre del token: ninguna ruta acepta un `companyId`.
class EcfApplicationRepository {
  EcfApplicationRepository(this._dio);

  final Dio _dio;

  Future<EcfApplicationDraft> draft() async {
    final res = await _dio.get('/ecf/dgii/application/draft');
    return EcfApplicationDraft.fromJson(_asMap(res.data));
  }

  Future<EcfApplicationDraft> saveDraft(
    Map<String, dynamic> payload, {
    int? expectedRevision,
  }) async {
    final res = await _dio.put(
      '/ecf/dgii/application/draft',
      data: {
        'payload': payload,
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
      },
    );
    return EcfApplicationDraft.fromJson(_asMap(res.data));
  }

  /// Envía el expediente creando una versión inmutable en el servidor.
  Future<EcfApplicationSubmitResult> submit({
    required String consentVersion,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _dio.post(
      '/ecf/dgii/application/submit',
      data: {'consentVersion': consentVersion, 'payload': payload},
    );
    return EcfApplicationSubmitResult.fromJson(_asMap(res.data));
  }

  Future<List<EcfApplicationSnapshot>> snapshots() async {
    final res = await _dio.get('/ecf/dgii/application/snapshots');
    final data = res.data;
    if (data is! List) return const <EcfApplicationSnapshot>[];
    return data
        .whereType<Map>()
        .map((row) => EcfApplicationSnapshot.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }
}
