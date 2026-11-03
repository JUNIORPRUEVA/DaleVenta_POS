import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../ecf_platform_models.dart';

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map) return data.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asRows(dynamic data) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList(growable: false);
  }
  if (data is Map && data['items'] is List) {
    return (data['items'] as List)
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

final ecfPlatformRepositoryProvider = Provider<EcfPlatformRepository>((ref) {
  return EcfPlatformRepository(ref.watch(dioProvider));
});

/// `true` solo cuando el backend confirma que la sesión es personal de
/// plataforma.
///
/// La pregunta se hace al servidor a propósito: el cliente no deduce el rol de
/// la apariencia ni de una constante de compilación. Un `403` significa "no es
/// personal"; cualquier otro fallo se propaga como error para no disfrazar un
/// problema de red con un "sin acceso".
final ecfPlatformStaffProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(ecfPlatformRepositoryProvider).isPlatformStaff();
});

/// Bandeja multiempresa filtrada por estado (`null` = todos).
final ecfPlatformApplicationsProvider = FutureProvider.autoDispose
    .family<EcfPlatformApplicationPage, String?>((ref, state) {
      return ref
          .watch(ecfPlatformRepositoryProvider)
          .listApplications(state: state);
    });

/// Expediente de una empresa concreta.
final ecfPlatformApplicationProvider = FutureProvider.autoDispose
    .family<EcfPlatformApplicationDetail, String>((ref, companyId) {
      return ref
          .watch(ecfPlatformRepositoryProvider)
          .applicationDetail(companyId);
    });

/// Requisitos del expediente con su seguimiento interno.
final ecfPlatformRequirementsProvider = FutureProvider.autoDispose
    .family<List<EcfPlatformRequirement>, String>((ref, companyId) {
      return ref
          .watch(ecfPlatformRepositoryProvider)
          .listRequirements(companyId);
    });

/// Estado del motor de activación de una empresa (solo lectura).
final ecfPlatformActivationProvider = FutureProvider.autoDispose
    .family<EcfPlatformActivation, String>((ref, companyId) {
      return ref.watch(ecfPlatformRepositoryProvider).activation(companyId);
    });

/// Alcance con el que se está accediendo al expediente (concedido por la
/// empresa y con caducidad).
final ecfPlatformAccessProvider = FutureProvider.autoDispose
    .family<EcfPlatformAccess, String>((ref, companyId) {
      return ref.watch(ecfPlatformRepositoryProvider).access(companyId);
    });

/// Cliente de la superficie de PLATAFORMA.
///
/// Existe separado del cliente de la empresa para que la diferencia de
/// autorización sea visible en el código: aquí la empresa se pasa por parámetro
/// y el backend exige personal de plataforma; allí la empresa sale del token y
/// nunca se acepta un identificador ajeno.
class EcfPlatformRepository {
  EcfPlatformRepository(this._dio);

  final Dio _dio;

  /// Consulta la pertenencia al personal de plataforma.
  Future<bool> isPlatformStaff() async {
    try {
      final res = await _dio.get(ApiRoutes.ecfPlatformMe);
      return _asMap(res.data)['isPlatformStaff'] == true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 403) return false;
      rethrow;
    }
  }

  /// Bandeja paginada. `state` vacío o nulo significa "todos".
  Future<EcfPlatformApplicationPage> listApplications({
    String? state,
    int take = 50,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{'take': take, 'skip': skip};
    final normalized = state?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      query['state'] = normalized;
    }
    final res = await _dio.get(
      ApiRoutes.ecfPlatformApplications,
      queryParameters: query,
    );
    final payload = _asMap(res.data);
    final items = _asRows(
      res.data,
    ).map(EcfPlatformApplication.fromJson).toList(growable: false);
    final rawTotal = payload['total'];
    return EcfPlatformApplicationPage(
      items: items,
      total: rawTotal is num ? rawTotal.toInt() : skip + items.length,
      take: take,
      skip: skip,
    );
  }

  Future<EcfPlatformApplicationDetail> applicationDetail(
    String companyId,
  ) async {
    final res = await _dio.get(ApiRoutes.ecfPlatformApplication(companyId));
    return EcfPlatformApplicationDetail.fromJson(_asMap(res.data));
  }

  /// Envía una decisión de revisión.
  ///
  /// No existe un parámetro de aprobación: la aprobación oficial no es una
  /// decisión de interfaz. Enviar `APPROVED` sin registro oficial lo rechaza el
  /// backend con `ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD`.
  Future<void> decide({
    required String companyId,
    String? state,
    String? reviewState,
    String? observations,
  }) async {
    final body = <String, dynamic>{};
    if (state != null) body['state'] = state;
    if (reviewState != null) body['reviewState'] = reviewState;
    if (observations != null) body['observations'] = observations;
    await _dio.patch(
      ApiRoutes.ecfPlatformApplication(companyId),
      data: body,
    );
  }

  /// Requisitos del catálogo con su seguimiento (o `tracking` nulo).
  Future<List<EcfPlatformRequirement>> listRequirements(
    String companyId,
  ) async {
    final res = await _dio.get(ApiRoutes.ecfPlatformRequirements(companyId));
    return _asRows(
      res.data,
    ).map(EcfPlatformRequirement.fromJson).toList(growable: false);
  }

  /// Estado del motor de activación de la empresa.
  ///
  /// Solo lectura: no existe un método para ejecutar pasos desde plataforma.
  /// El motor lo gobierna la empresa dueña del expediente.
  Future<EcfPlatformActivation> activation(String companyId) async {
    final res = await _dio.get(ApiRoutes.ecfPlatformActivation(companyId));
    return EcfPlatformActivation.fromJson(_asMap(res.data));
  }

  /// Alcance efectivo que autoriza esta visita.
  ///
  /// Nunca se deduce en el cliente: si la empresa revoca, esta lectura deja de
  /// devolver la concesión y la siguiente llamada al expediente responde 403.
  Future<EcfPlatformAccess> access(String companyId) async {
    final res = await _dio.get(ApiRoutes.ecfPlatformAccess(companyId));
    return EcfPlatformAccess.fromJson(_asMap(res.data));
  }

  /// Registra la revisión de UN requisito.
  ///
  /// No mueve el estado del expediente: revisar un requisito no aprueba nada.
  Future<void> reviewRequirement({
    required String companyId,
    required String key,
    required String status,
    String? note,
  }) async {
    await _dio.patch(
      ApiRoutes.ecfPlatformRequirement(companyId, key),
      data: {'status': status, if (note != null) 'note': note},
    );
  }

  /// Revisa internamente una evidencia. Un rechazo exige motivo (lo valida el
  /// backend). Marcar como revisada no otorga autorización oficial.
  Future<void> reviewEvidence({
    required String companyId,
    required String evidenceId,
    required String decision,
    String? note,
  }) async {
    await _dio.patch(
      ApiRoutes.ecfPlatformEvidence(companyId, evidenceId),
      data: {'decision': decision, if (note != null) 'note': note},
    );
  }

  /// Descarga autorizada del documento de una evidencia.
  ///
  /// El servidor comprueba que la evidencia pertenece a esa empresa; un
  /// identificador ajeno responde igual que uno inexistente.
  Future<Uint8List> downloadDocument({
    required String companyId,
    required String evidenceId,
  }) async {
    final res = await _dio.get<List<int>>(
      ApiRoutes.ecfPlatformDocumentFile(companyId, evidenceId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }
}
