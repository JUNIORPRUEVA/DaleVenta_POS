import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/auth_provider.dart';
import '../ecf_models.dart';
import '../ecf_print_document.dart';
import '../ecf_sale_fiscal.dart';
import 'ecf_connection_guard.dart';
import '../ecf_authorized_sequence_models.dart';
import '../ecf_dosa_dispatch_models.dart';
import '../ecf_dosa_activation_models.dart';
import '../ecf_support_grant_models.dart';

/// Error de numeración con el motivo que dio el servidor.
///
/// Dio no incluye el cuerpo de la respuesta en `toString()`, así que sin esto la
/// pantalla solo podía decir «Inténtalo de nuevo» y el cliente no sabía qué
/// corregir.
class EcfSequenceException implements Exception {
  EcfSequenceException(this.message, {this.minimumStartNumber});

  final String message;
  final int? minimumStartNumber;

  @override
  String toString() => message;
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map) return data.cast<String, dynamic>();
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _asList(dynamic data) {
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

final ecfRepositoryProvider = Provider<EcfRepository>((ref) {
  return EcfRepository(ref.watch(dioProvider));
});

final ecfCapabilitiesProvider = FutureProvider.autoDispose<EcfCapabilities>((
  ref,
) {
  // Las capacidades son POR EMPRESA: incluyen la excepción de vender sin e-CF
  // y los tipos habilitados. Al cambiar de empresa o de sesión se releen, en
  // lugar de dejar a la vista la configuración de la anterior.
  ref.watch(
    authStateProvider.select(
      (state) => (state.isAuthenticated, state.user?.id, state.user?.companyId),
    ),
  );
  return ref.watch(ecfRepositoryProvider).capabilities();
});

final ecfCountersProvider = FutureProvider.autoDispose<EcfCounters>((ref) {
  return ref.watch(ecfRepositoryProvider).summary();
});

/// Proceso interno de habilitación e-CF de la empresa.
final ecfOnboardingProvider = FutureProvider.autoDispose<EcfOnboardingView>((
  ref,
) {
  return ref.watch(ecfRepositoryProvider).onboarding();
});

/// Habilitación DGII de la empresa: seguimiento interno + autorización oficial.
final ecfDgiiHabilitationProvider =
    FutureProvider.autoDispose<EcfDgiiHabilitationView>((ref) {
      ref.watch(
        authStateProvider.select(
          (state) =>
              (state.isAuthenticated, state.user?.id, state.user?.companyId),
        ),
      );
      return ref.watch(ecfRepositoryProvider).dgiiHabilitation();
    });

/// Historial de cambios de habilitación de la empresa.
final ecfDgiiHistoryProvider =
    FutureProvider.autoDispose<List<EcfDgiiHistoryEntry>>((ref) {
      return ref.watch(ecfRepositoryProvider).dgiiHistory();
    });

/// Asistencia temporal concedida por la empresa al equipo de Fulltech.
///
/// Se consulta al backend y no se cachea entre pantallas: si la empresa revoca,
/// la siguiente lectura debe reflejarlo sin depender de un refresco manual.
final ecfSupportGrantsProvider =
    FutureProvider.autoDispose<EcfSupportGrantList>((ref) {
      return ref.watch(ecfRepositoryProvider).supportGrants();
    });

/// Estado de clasificación fiscal de las partidas de una venta.
///
/// Se consulta al backend: la aplicación nunca decide por su cuenta si una
/// partida está autorizada a clasificarse.
final ecfPendingClassificationsProvider = FutureProvider.autoDispose
    .family<EcfPendingClassifications, String>((ref, saleId) {
      return ref.watch(ecfRepositoryProvider).pendingClassifications(saleId);
    });

final ecfSequencesProvider = FutureProvider.autoDispose<List<EcfSequenceInfo>>((
  ref,
) {
  return ref.watch(ecfRepositoryProvider).sequences();
});

final ecfEligibleOriginalsProvider =
    FutureProvider.autoDispose<List<EcfEligibleOriginal>>((ref) {
      return ref.watch(ecfRepositoryProvider).eligibleOriginals();
    });

/// Filtro de la bandeja de comprobantes. Es `immutable` y con igualdad por
/// valor para que la familia de providers no recree la consulta en cada build.
class EcfDocumentFilter {
  const EcfDocumentFilter({this.group, this.documentType, this.search});

  final EcfStatusGroup? group;
  final String? documentType;
  final String? search;

  static const all = EcfDocumentFilter();

  EcfDocumentFilter copyWith({
    EcfStatusGroup? group,
    String? documentType,
    String? search,
  }) {
    return EcfDocumentFilter(
      group: group ?? this.group,
      documentType: documentType ?? this.documentType,
      search: search ?? this.search,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EcfDocumentFilter &&
      other.group == group &&
      other.documentType == documentType &&
      other.search == search;

  @override
  int get hashCode => Object.hash(group, documentType, search);
}

final ecfDocumentsProvider = FutureProvider.autoDispose
    .family<EcfDocumentPage, EcfDocumentFilter>((ref, filter) {
      return ref.watch(ecfRepositoryProvider).listDocumentsPage(filter: filter);
    });

final ecfDocumentDetailProvider = FutureProvider.autoDispose
    .family<EcfDocumentDetail, String>((ref, id) {
      return ref.watch(ecfRepositoryProvider).documentDetail(id);
    });

final ecfSalesFiscalProvider = FutureProvider.autoDispose.family<Map<String, EcfSaleFiscal>, String>((ref, ids) {
  ref.watch(authStateProvider.select((state) => (state.user?.id, state.user?.companyId)));
  return ref.watch(ecfRepositoryProvider).salesFiscal(ids.split(','));
});

/// Company-scoped e-CF reads and guarded preparation/dispatch operations.
class EcfRepository {
  Future<void> enableProduction({required String expectedCompanyId}) async {
    await postEcf(_dio, '/ecf/production/enable', data: {'expectedCompanyId': expectedCompanyId});
  }

  Future<Map<String, EcfSaleFiscal>> salesFiscal(List<String> ids) async {
    final valid = ids.where((id) => RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)).toSet().toList();
    final result = <String, EcfSaleFiscal>{};
    for (var offset = 0; offset < valid.length; offset += 50) {
      final chunk = valid.skip(offset).take(50).join(',');
      final response = await _dio.get('/ecf/sales/fiscal', queryParameters: {'ids': chunk}, options: Options(extra: const {'skipLoader': true, 'disableOfflineCache': true}));
      for (final row in _asList(_asMap(response.data)['items'])) {
        final fiscal = EcfSaleFiscal.fromJson(row);
        result[fiscal.saleId] = fiscal;
      }
    }
    return result;
  }

  Future<EcfPrintDocument> printDocument(String documentId) async {
    final response = await _dio.get(
      '/ecf/documents/${Uri.encodeComponent(documentId)}/print',
    );
    final data = _asMap(response.data);
    return EcfPrintDocument.fromJson(
      Map<String, dynamic>.from(data['document'] as Map),
    );
  }

  Future<EcfPrintDocument?> printForSale(String saleId, {bool requireElectronic = false}) async {
    // Offline/local receipts have no server fiscal identity yet.
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(saleId)) {
      if (requireElectronic) {
        throw StateError('La venta electrónica todavía no tiene una identidad fiscal confirmada en el servidor.');
      }
      return null;
    }
    final response = await _dio.get(
      '/ecf/sales/${Uri.encodeComponent(saleId)}/print',
    );
    final data = _asMap(response.data);
    if (data['requiresReview'] == true) {
      throw StateError(
        'La venta tiene más de un comprobante. Revisa su historial fiscal antes de imprimir.',
      );
    }
    final document = data['document'];
    if (document is! Map && requireElectronic) throw StateError('El comprobante electrónico aún no está preparado. Revisa su estado antes de imprimir.');
    return document is Map
        ? EcfPrintDocument.fromJson(document.cast<String, dynamic>())
        : null;
  }

  EcfRepository(this._dio);

  final Dio _dio;

  Future<EcfCapabilities> capabilities() async {
    final res = await _dio.get(ApiRoutes.ecfCapabilities);
    return EcfCapabilities.fromJson(_asMap(res.data));
  }

  Future<EcfCounters> summary() async {
    final res = await _dio.get(ApiRoutes.ecfDocumentsSummary);
    return EcfCounters.fromJson(_asMap(res.data));
  }

  Future<List<EcfSequenceInfo>> sequences() async {
    final res = await _dio.get(ApiRoutes.ecfSequences);
    return _asList(
      res.data,
    ).map(EcfSequenceInfo.fromJson).toList(growable: false);
  }

  /// Declara el rango de numeración (e-NCF) que la DGII asignó a la empresa.
  ///
  /// Sin un rango activo no se puede preparar ningún comprobante: el backend
  /// responde `ECF_SEQUENCE_EXHAUSTED`, que no explica nada al cliente. El
  /// prefijo NO se envía: lo deriva el backend del tipo de comprobante
  /// (`E31` → `E310000000001`).
  ///
  /// Un error aquí sí es una excepción: `ECF_SEQUENCE_ALREADY_EXISTS` (ya hay uno
  /// activo), `ECF_SEQUENCE_RANGE_INVALID` (desde/hasta incoherentes) o
  /// `ECF_SEQUENCE_REUSE_BLOCKED` (empezar por debajo de lo ya consumido).
  Future<void> registerSequence({
    required String documentType,
    String? expectedEnvironment,
    required int startNumber,
    required int endNumber,
    String? validUntil,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.ecfSequences,
        data: {
          'documentType': documentType,
          if (expectedEnvironment != null)
            'expectedEnvironment': expectedEnvironment,
          'startNumber': startNumber,
          'endNumber': endNumber,
          if (validUntil != null && validUntil.trim().isNotEmpty)
            'validUntil': validUntil.trim(),
        },
      );
    } on DioException catch (error) {
      final body = error.response?.data;
      final minimum = body is Map ? body['minimumStartNumber'] : null;
      final reviewedTestFrontier = expectedEnvironment == 'SANDBOX' &&
          error.response?.statusCode == 409 && body is Map &&
          body['code'] == 'ECF_SEQUENCE_LEGACY_TEST_REUSE_BLOCKED' &&
          minimum is int && minimum > startNumber && minimum <= endNumber;
      throw EcfSequenceException(
        _sequenceServerMessage(error),
        minimumStartNumber: reviewedTestFrontier ? minimum : null,
      );
    }
  }

  /// Renueva el rango activo cuando se agotó o venció.
  ///
  /// El backend exige que el nuevo rango empiece en el número ya consumido o
  /// después (`ECF_SEQUENCE_REUSE_BLOCKED`) y que quepa en la autorización
  /// vigente de la DGII (`ECF_SEQUENCE_EXCEEDS_AUTHORIZED`). El rango anterior
  /// se desactiva: no se borra, queda como historial.
  Future<void> renewSequence({
    required String documentType,
    String? expectedEnvironment,
    required int startNumber,
    required int endNumber,
    String? validUntil,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.ecfSequencesRenew,
        data: {
          'documentType': documentType,
          if (expectedEnvironment != null)
            'expectedEnvironment': expectedEnvironment,
          'startNumber': startNumber,
          'endNumber': endNumber,
          if (validUntil != null && validUntil.trim().isNotEmpty)
            'validUntil': validUntil.trim(),
        },
      );
    } on DioException catch (error) {
      throw EcfSequenceException(_sequenceServerMessage(error));
    }
  }

  /// Numeración que la DGII autorizó a esta empresa, por tipo de comprobante.
  Future<EcfAuthorizedSequencesView> authorizedSequences() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiAuthorizedSequences);
    return EcfAuthorizedSequencesView.fromJson(_asMap(res.data));
  }

  /// Declara lo que la DGII autorizó. El backend guarda quién lo declaró, cuándo
  /// y la versión del texto aceptado; sin esta fila no se puede declarar
  /// numeración (`ECF_SEQUENCE_NOT_AUTHORIZED`).
  Future<void> declareAuthorizedSequence({
    required String documentType,
    String? expectedEnvironment,
    required String authorizationNumber,
    required int rangeFrom,
    required int rangeTo,
    required int approvedQuantity,
    String? expiresAt,
    required bool declarationAccepted,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.ecfDgiiAuthorizedSequences,
        data: {
          'documentType': documentType,
          if (expectedEnvironment != null)
            'expectedEnvironment': expectedEnvironment,
          'authorizationNumber': authorizationNumber.trim(),
          'rangeFrom': rangeFrom,
          'rangeTo': rangeTo,
          'approvedQuantity': approvedQuantity,
          if (expiresAt != null && expiresAt.trim().isNotEmpty)
            'expiresAt': expiresAt.trim(),
          'declarationAccepted': declarationAccepted,
        },
      );
    } on DioException catch (error) {
      throw EcfSequenceException(_sequenceServerMessage(error));
    }
  }

  /// Motivo legible de un error de numeración.
  ///
  /// Los DTO de Nest responden en inglés con el nombre del campo. Se traduce el
  /// caso que el cliente puede provocar solo y el resto se conserva tal cual,
  /// que siempre es mejor que un «Inténtalo de nuevo» sin motivo.
  String _sequenceServerMessage(DioException error) {
    final data = error.response?.data;
    String? message;
    if (data is Map) {
      final raw = data['message'];
      if (raw is String && raw.trim().isNotEmpty) {
        message = raw.trim();
      } else if (raw is List && raw.isNotEmpty) {
        message = raw.first.toString().trim();
      }
    }
    if (message == null || message.isEmpty) {
      return 'No se pudo guardar la numeración. Inténtalo de nuevo.';
    }
    if (message.contains('ECF_NUMBERING_ENVIRONMENT_CHANGED')) {
      return 'El ambiente de facturación cambió. Vuelve a abrir la numeración antes de guardar.';
    }
    if (message.contains('documentType must be one of the following values')) {
      return 'La DGII todavía no admite ese tipo de comprobante para numeración.';
    }
    return message;
  }

  Future<List<EcfEligibleOriginal>> eligibleOriginals() async {
    final res = await _dio.get(ApiRoutes.ecfDocumentsEligibleOriginals);
    return _asList(
      res.data,
    ).map(EcfEligibleOriginal.fromJson).toList(growable: false);
  }

  /// Sube un documento del expediente DGII.
  ///
  /// El tipo real lo decide el servidor por el contenido del archivo; aquí solo
  /// se declara la clase documental y el nombre original. Devuelve el id de la
  /// evidencia creada (o la existente, si era un duplicado).
  Future<String> uploadDgiiDocument({
    required String kind,
    required List<int> bytes,
    required String fileName,
    String? mimeType,
  }) async {
    final form = FormData.fromMap({
      'kind': kind,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: mimeType == null ? null : DioMediaType.parse(mimeType),
      ),
    });
    final res = await _dio.post(ApiRoutes.ecfDgiiDocuments, data: form);
    final payload = _asMap(res.data);
    final id = payload['id'];
    return id is String ? id : '';
  }

  /// Descarga un documento del expediente.
  ///
  /// El servidor comprueba que la evidencia pertenece a la empresa de la
  /// sesión; un id ajeno responde igual que uno inexistente.
  Future<Uint8List> downloadDgiiDocument(String evidenceId) async {
    final res = await _dio.get<List<int>>(
      ApiRoutes.ecfDgiiDocumentFile(evidenceId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }

  /// Una página de la bandeja, con el total autoritativo del servidor.
  ///
  /// El total lo calcula el backend sobre el mismo filtro: la aplicación no lo
  /// estima a partir de las filas que ya tiene.
  Future<EcfDocumentPage> listDocumentsPage({
    EcfDocumentFilter filter = EcfDocumentFilter.all,
    int take = 25,
    int skip = 0,
  }) async {
    final query = <String, dynamic>{'take': take, 'skip': skip};
    final group = filter.group;
    if (group != null && group.apiValue.isNotEmpty) {
      query['group'] = group.apiValue;
    }
    final documentType = filter.documentType;
    if (documentType != null && documentType.isNotEmpty) {
      query['documentType'] = documentType;
    }
    final search = filter.search?.trim();
    if (search != null && search.isNotEmpty) {
      query['search'] = search;
    }
    final res = await _dio.get(ApiRoutes.ecfDocuments, queryParameters: query);
    final payload = _asMap(res.data);
    final rawItems = payload['items'] is List
        ? payload['items'] as List
        : res.data is List
        ? res.data as List
        : const [];
    final items = rawItems
        .whereType<Map>()
        .map((row) => EcfDocumentSummary.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
    final rawTotal = payload['total'];
    return EcfDocumentPage(
      items: items,
      // Sin total del servidor se asume lo visible: nunca se inventa un total
      // mayor que el que la aplicación puede demostrar.
      total: rawTotal is num ? rawTotal.toInt() : skip + items.length,
      take: take,
      skip: skip,
    );
  }

  Future<List<EcfDocumentSummary>> listDocuments({
    EcfDocumentFilter filter = EcfDocumentFilter.all,
    int take = 50,
  }) async {
    final page = await listDocumentsPage(filter: filter, take: take);
    return page.items;
  }

  Future<EcfDocumentDetail> documentDetail(String id) async {
    final res = await _dio.get(ApiRoutes.ecfDocumentDetail(id),
      options: Options(extra: const {'disableOfflineCache': true}));
    return EcfDocumentDetail.fromJson(_asMap(res.data));
  }

  /// Habilita o deshabilita e-CF para la empresa.
  ///
  /// Solo cambia el interruptor de configuración: no emite, no consume
  /// secuencias y no contacta al proveedor. Requiere el permiso
  /// `manageEcfConfig` en el backend.
  Future<void> updateEnabled({required bool enabled}) async {
    await _dio.patch(ApiRoutes.ecfConfig, data: {'enabled': enabled});
  }

  /// Habilita o deshabilita registrar ventas SIN comprobante electrónico.
  ///
  /// Es una excepción fiscal: el backend la respalda con el registro de
  /// excepciones, que guarda motivo y usuario de cada uso. Requiere el permiso
  /// `manageEcfConfig`.
  Future<void> updateAllowSalesWithoutEcf({required bool allow}) async {
    await _dio.patch(
      ApiRoutes.ecfConfig,
      data: {'allowSalesWithoutEcf': allow},
    );
  }

  /// Registra que una venta se cerró SIN comprobante electrónico.
  ///
  /// Falla si la empresa no habilitó la excepción o si la venta ya tiene
  /// comprobante: el servidor manda, la interfaz no improvisa.
  Future<void> registerSaleWithoutDocument({
    required String saleId,
    required String reason,
    String? expectedDocumentType,
  }) async {
    await _dio.post(
      ApiRoutes.ecfSalesWithoutDocument,
      data: {
        'saleId': saleId,
        'reason': reason,
        if (expectedDocumentType != null)
          'expectedDocumentType': expectedDocumentType,
      },
    );
  }

  /// Proceso INTERNO de habilitación e-CF de la empresa.
  ///
  /// Los estados que devuelve son internos del proceso administrativo: no
  /// acreditan certificación ante la DGII.
  Future<EcfOnboardingView> onboarding() async {
    final res = await _dio.get(ApiRoutes.ecfOnboarding);
    return EcfOnboardingView.fromJson(_asMap(res.data));
  }

  /// Marca un paso del proceso interno. No habilita emisión real por sí solo.
  Future<void> updateOnboardingStep({
    required String stepKey,
    required String status,
    String? resultSummary,
  }) async {
    await _dio.patch(
      ApiRoutes.ecfOnboardingStep(stepKey),
      data: {
        'status': status,
        if (resultSummary != null) 'resultSummary': resultSummary,
      },
    );
  }

  /// DESPACHO SIMULADO contra el proveedor simulado del backend.
  ///
  /// No es emisión: el backend solo acepta esta llamada en una UAT local con el
  /// transporte real apagado, y el resultado nunca es aceptación de la DGII
  /// (acaba en revisión humana). Se usa para validar la cadena completa.
  Future<EcfSimulatedDispatchOutcome> simulateDispatch({
    required String documentId,
    required String scenario,
  }) async {
    final res = await _dio.post(
      ApiRoutes.ecfDocumentSimulateDispatch(documentId),
      data: {'scenario': scenario},
    );
    return EcfSimulatedDispatchOutcome.fromJson(_asMap(res.data));
  }

  /// DESPACHO AUTORIZADO al proveedor DOSA de la empresa.
  ///
  /// A diferencia del despacho simulado, este camino es el real: el backend
  /// aplica barrera del documento, compuerta fiscal y credenciales de ESTA
  /// empresa y ESTE ambiente.
  ///
  /// Un rechazo fiscal no lanza: llega con `ok: false`, `code` y
  /// `blockingReasons` para que la interfaz explique qué falta. Los códigos 4xx
  /// sí son excepciones (permiso, documento inexistente, doble intento).
  Future<EcfDosaDispatchOutcome> recoverDosa(String documentId) async {
    final response = await postEcf(_dio, '/ecf/documents/${Uri.encodeComponent(documentId)}/recover-dosa');
    return EcfDosaDispatchOutcome.fromJson(_asMap(response.data));
  }

  Future<EcfDosaDispatchOutcome> dispatchDosa(String documentId) async {
    final res = await postEcf(_dio, ApiRoutes.ecfDocumentDispatchDosa(documentId));
    return EcfDosaDispatchOutcome.fromJson(_asMap(res.data));
  }

  /// Intenta ACTIVAR y AUTORIZAR la emisión con la evidencia del cliente.
  ///
  /// Es la llamada que permite al cliente terminar el proceso sin que nadie de
  /// Fulltech intervenga: el backend evalúa la sesión, la confirmación de DOSA,
  /// la aprobación de la DGII y la autorización del propio cliente, y si están
  /// las cuatro activa la credencial y deriva el estado de certificación.
  ///
  /// Un «todavía no» NO lanza: llega con `ok: false` y `blockingReasons`, que la
  /// interfaz muestra tal cual. Repetir la llamada es seguro (idempotente).
  Future<EcfDosaActivationOutcome> attemptDosaActivation() async {
    final res = await _dio.post(ApiRoutes.ecfDosaActivationAttempt);
    return EcfDosaActivationOutcome.fromJson(_asMap(res.data));
  }

  /// Prepara un borrador local (E31) a partir de una venta real.
  ///
  /// NO emite: el backend no expone ninguna ruta que contacte al proveedor.
  /// Consume numeración, así que exige empresa habilitada y permiso
  /// `prepareEcfDocuments`. Un fallo de elegibilidad llega en el CUERPO
  /// (`ok: false` + código), no como error de red: así la interfaz puede
  /// explicar exactamente por qué la venta no es elegible.
  Future<EcfPreparationOutcome> prepareFromSale({
    required String saleId,
    required int paymentType,
    int? incomeType,
    String? sequenceDueDate,
    String? paymentDeadline,
  }) async {
    final res = await postEcf(_dio,
      ApiRoutes.ecfDocumentsPrepare,
      data: {
        'saleId': saleId,
        'documentType': 'E31',
        'paymentType': paymentType,
        if (incomeType != null) 'incomeType': incomeType,
        if (sequenceDueDate != null && sequenceDueDate.isNotEmpty)
          'sequenceDueDate': sequenceDueDate,
        if (paymentDeadline != null && paymentDeadline.isNotEmpty)
          'paymentDeadline': paymentDeadline,
      },
    );
    final payload = _asMap(res.data);
    if (payload['ok'] == true) {
      final value = _asMap(payload['value']);
      return EcfPreparationOutcome.success(
        documentId: (value['documentId'] as String?) ?? '',
        encf: (value['encf'] as String?) ?? '',
        status: (value['status'] as String?) ?? '',
      );
    }
    return EcfPreparationOutcome.failure(
      code: (payload['code'] as String?) ?? 'ECF_PREPARATION_FAILED',
      message:
          (payload['safeMessage'] as String?) ??
          'No se pudo preparar el comprobante.',
    );
  }

  /// Prepara un borrador local de CONSUMO (E32) desde una venta real.
  ///
  /// Numera igual que E31: el backend consume un e-NCF del rango que la DGII
  /// autorizó para facturas de consumo, de forma idempotente por venta (un
  /// reintento reutiliza el número ya asignado). No emite.
  Future<EcfPreparationOutcome> prepareConsumoFromSale({
    required String saleId,
    required int paymentType,
    int? incomeType,
  }) async {
    final res = await postEcf(_dio,
      ApiRoutes.ecfDocumentsPrepareConsumo,
      data: {
        'saleId': saleId,
        'documentType': 'E32',
        'paymentType': paymentType,
        if (incomeType != null) 'incomeType': incomeType,
      },
    );
    final payload = _asMap(res.data);
    if (payload['ok'] == true) {
      final value = _asMap(payload['value']);
      return EcfPreparationOutcome.success(
        documentId: (value['documentId'] as String?) ?? '',
        encf: (value['encf'] as String?) ?? '',
        status: (value['status'] as String?) ?? '',
      );
    }
    return EcfPreparationOutcome.failure(
      code: (payload['code'] as String?) ?? 'ECF_CONSUMO_PREPARATION_FAILED',
      message:
          (payload['safeMessage'] as String?) ??
          'No se pudo preparar el comprobante de consumo.',
    );
  }

  /// Solo reserva el crédito FISCAL: no toca inventario, caja, turnos, pagos ni
  /// abonos, y no emite. Las líneas y su clasificación las toma el servidor del
  /// original; aquí solo se decide QUÉ se acredita.
  Future<EcfPreparationOutcome> prepareCreditNote({
    required String originalDocumentId,
    required String clientRequestId,
    required String refundKind,
    required int modificationCode,
    required String modificationReason,
    required int paymentType,
    required int creditNoteIndicator,
    List<Map<String, dynamic>>? lines,
  }) async {
    final res = await postEcf(_dio,
      ApiRoutes.ecfDocumentsPrepareCreditNote,
      data: {
        'originalDocumentId': originalDocumentId,
        'clientRequestId': clientRequestId,
        'refundKind': refundKind,
        'modificationCode': modificationCode,
        'modificationReason': modificationReason,
        'paymentType': paymentType,
        'creditNoteIndicator': creditNoteIndicator,
        if (lines != null && lines.isNotEmpty) 'lines': lines,
      },
    );
    final payload = _asMap(res.data);
    if (payload['ok'] == true) {
      final value = _asMap(payload['value']);
      return EcfPreparationOutcome.success(
        documentId: (value['documentId'] as String?) ?? '',
        encf: (value['encf'] as String?) ?? '',
        status: (value['status'] as String?) ?? '',
      );
    }
    return EcfPreparationOutcome.failure(
      code: (payload['code'] as String?) ?? 'ECF_CREDIT_NOTE_FAILED',
      message:
          (payload['safeMessage'] as String?) ??
          'No se pudo preparar la nota de crédito.',
    );
  }

  // ---------------------------------------------------------------------------
  // Habilitación DGII POR EMPRESA
  //
  // Todas las rutas están acotadas en el backend a la empresa autenticada: la
  // aplicación nunca envía un `companyId`. NINGUNA de estas llamadas emite ni
  // consume numeración; el seguimiento no sustituye una resolución oficial.
  // ---------------------------------------------------------------------------

  /// Habilitación DGII de la empresa del contexto.
  Future<EcfDgiiHabilitationView> dgiiHabilitation() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiHabilitation);
    return EcfDgiiHabilitationView.fromJson(_asMap(res.data));
  }

  /// Historial de cambios de la habilitación.
  Future<List<EcfDgiiHistoryEntry>> dgiiHistory() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiHistory);
    return _asList(
      res.data,
    ).map(EcfDgiiHistoryEntry.fromJson).toList(growable: false);
  }

  /// Evidencias registradas por la empresa.
  Future<List<EcfDgiiEvidenceView>> dgiiEvidence() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiEvidence);
    return _asList(
      res.data,
    ).map(EcfDgiiEvidenceView.fromJson).toList(growable: false);
  }

  /// Avanza el seguimiento INTERNO del proceso.
  ///
  /// No aprueba nada: el backend rechaza `APPROVED` sin un registro oficial
  /// verificado y la interfaz no ofrece ese estado.
  Future<void> updateDgiiHabilitation({
    String? state,
    String? reviewState,
    String? observations,
  }) async {
    await _dio.patch(
      ApiRoutes.ecfDgiiHabilitation,
      data: {
        if (state != null) 'state': state,
        if (reviewState != null) 'reviewState': reviewState,
        if (observations != null) 'observations': observations,
      },
    );
  }

  /// Registra una evidencia declarando explícitamente su procedencia.
  Future<EcfDgiiEvidenceView> registerDgiiEvidence({
    required String source,
    required String kind,
    required String storageRef,
    String? description,
  }) async {
    final res = await _dio.post(
      ApiRoutes.ecfDgiiEvidence,
      data: {
        'source': source,
        'kind': kind,
        'storageRef': storageRef,
        if (description != null && description.trim().isNotEmpty)
          'description': description,
      },
    );
    return EcfDgiiEvidenceView.fromJson(_asMap(res.data));
  }

  /// Revisión INTERNA de una evidencia.
  ///
  /// Es una decisión de la empresa, no una verificación ante la DGII: marcar una
  /// evidencia como revisada **no** autoriza nada. `REJECTED` exige motivo, y el
  /// backend lo rechaza si falta.
  Future<EcfDgiiEvidenceView> reviewDgiiEvidence({
    required String evidenceId,
    required String decision,
    String? note,
  }) async {
    final res = await _dio.patch(
      ApiRoutes.ecfDgiiEvidenceReview(evidenceId),
      data: {
        'decision': decision,
        if (note != null && note.trim().isNotEmpty) 'note': note,
      },
    );
    return EcfDgiiEvidenceView.fromJson(_asMap(res.data));
  }

  /// Registra el seguimiento interno de UN requisito del catálogo.
  ///
  /// No crea requisitos: el catálogo es cerrado y vive en el backend, que
  /// rechaza cualquier clave que no conozca.
  Future<EcfDgiiHabilitationView> updateDgiiRequirement({
    required String key,
    required String status,
    String? note,
    String? responsibleUserId,
    String? dueDate,
  }) async {
    final res = await _dio.patch(
      ApiRoutes.ecfDgiiRequirement(key),
      data: {
        'status': status,
        if (note != null && note.trim().isNotEmpty) 'note': note,
        if (responsibleUserId != null) 'responsibleUserId': responsibleUserId,
        if (dueDate != null && dueDate.trim().isNotEmpty) 'dueDate': dueDate,
      },
    );
    return EcfDgiiHabilitationView.fromJson(_asMap(res.data));
  }

  /// Registra la autorización recibida.
  ///
  /// Solo la fuente `DGII_OFFICIAL_RECORD` produce autorización efectiva, y el
  /// backend exige evidencia e identificador externo. Una declaración manual se
  /// guarda como metadato y no autoriza nada.
  Future<void> recordDgiiAuthorization({
    required String source,
    String? evidenceId,
    String? externalId,
  }) async {
    await _dio.post(
      ApiRoutes.ecfDgiiAuthorization,
      data: {
        'source': source,
        if (evidenceId != null) 'evidenceId': evidenceId,
        if (externalId != null) 'externalId': externalId,
      },
    );
  }

  /// Revoca la autorización registrada y devuelve la empresa a corrección.
  Future<void> revokeDgiiAuthorization() async {
    await _dio.post(ApiRoutes.ecfDgiiAuthorizationRevoke);
  }

  /// Concesiones de asistencia de la empresa autenticada.
  ///
  /// Incluye el historial: activas, revocadas y caducadas. La pantalla necesita
  /// ver las cerradas para que el usuario entienda qué pasó con una autorización
  /// que ya no está en vigor.
  Future<EcfSupportGrantList> supportGrants() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiSupportGrants);
    return EcfSupportGrantList.fromJson(_asMap(res.data));
  }

  /// Concede asistencia temporal al equipo de Fulltech.
  ///
  /// `days` es una duración, no una fecha: el backend valida el máximo y rechaza
  /// cualquier caducidad fuera de rango. No se envía `companyId`.
  Future<EcfSupportGrant> createSupportGrant({
    required List<String> scopes,
    required int days,
    String? reason,
  }) async {
    final expiresAt = DateTime.now()
        .toUtc()
        .add(Duration(days: days))
        .toIso8601String();
    final res = await _dio.post(
      ApiRoutes.ecfDgiiSupportGrants,
      data: {
        'scopes': scopes,
        'expiresAt': expiresAt,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return EcfSupportGrant.fromJson(_asMap(res.data));
  }

  /// Revoca de inmediato una concesión vigente.
  ///
  /// Surte efecto en la siguiente petición del personal de Fulltech: el backend
  /// evalúa la concesión en cada acceso, no al iniciar sesión.
  Future<void> revokeSupportGrant(String id) async {
    await _dio.post(ApiRoutes.ecfDgiiSupportGrantRevoke(id));
  }

  /// Partidas de una venta que necesitan clasificación fiscal supervisada.
  ///
  /// Es una LECTURA: informa qué bloquea la preparación y si el backend permite
  /// confirmarlo. La aplicación no envía ningún `companyId`: el ámbito sale de la
  /// sesión autenticada.
  Future<EcfPendingClassifications> pendingClassifications(
    String saleId,
  ) async {
    final res = await _dio.get(ApiRoutes.ecfPendingClassifications(saleId));
    return EcfPendingClassifications.fromJson(_asMap(res.data));
  }

  /// Confirma la clasificación fiscal de una partida sin producto.
  ///
  /// Devuelve el estado ACTUALIZADO de la venta, ya recalculado por el backend,
  /// para que la pantalla no tenga que deducir nada por su cuenta.
  Future<EcfPendingClassifications> confirmLineClassification({
    required String saleId,
    required String saleItemId,
    required String classification,
    required String reason,
  }) async {
    final res = await _dio.post(
      ApiRoutes.ecfLineClassifications,
      data: {
        'saleId': saleId,
        'saleItemId': saleItemId,
        'classification': classification,
        'reason': reason,
      },
    );
    final payload = _asMap(res.data);
    final sale = payload['sale'];
    if (sale is Map) {
      return EcfPendingClassifications.fromJson(sale.cast<String, dynamic>());
    }
    // El backend siempre devuelve el estado recalculado; si no viniera, se
    // vuelve a preguntar en lugar de mostrar un estado inventado.
    return pendingClassifications(saleId);
  }
}

/// Resultado de preparar: éxito con e-NCF, o fallo explicable al usuario.
class EcfPreparationOutcome {
  const EcfPreparationOutcome._({
    required this.ok,
    this.documentId = '',
    this.encf = '',
    this.status = '',
    this.code = '',
    this.message = '',
  });

  factory EcfPreparationOutcome.success({
    required String documentId,
    required String encf,
    required String status,
  }) => EcfPreparationOutcome._(
    ok: true,
    documentId: documentId,
    encf: encf,
    status: status,
  );

  factory EcfPreparationOutcome.failure({
    required String code,
    required String message,
  }) => EcfPreparationOutcome._(ok: false, code: code, message: message);

  final bool ok;
  final String documentId;
  final String encf;
  final String status;
  final String code;
  final String message;
}
