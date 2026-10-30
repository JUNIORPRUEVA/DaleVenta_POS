import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../ecf_models.dart';
import '../ecf_support_grant_models.dart';

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

final ecfEligibleOriginalsProvider = FutureProvider.autoDispose<
  List<EcfEligibleOriginal>
>((ref) {
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

/// Cliente de solo lectura para la superficie e-CF.
///
/// No existe ningún método de emisión: el backend no expone endpoint de envío al
/// proveedor, por lo que la aplicación nunca puede disparar una emisión real.
class EcfRepository {
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
    return _asList(res.data)
        .map(EcfSequenceInfo.fromJson)
        .toList(growable: false);
  }

  Future<List<EcfEligibleOriginal>> eligibleOriginals() async {
    final res = await _dio.get(ApiRoutes.ecfDocumentsEligibleOriginals);
    return _asList(res.data)
        .map(EcfEligibleOriginal.fromJson)
        .toList(growable: false);
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
    final res = await _dio.get(ApiRoutes.ecfDocumentDetail(id));
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
    final res = await _dio.post(ApiRoutes.ecfDocumentsPrepare, data: {
      'saleId': saleId,
      'documentType': 'E31',
      'paymentType': paymentType,
      if (incomeType != null) 'incomeType': incomeType,
      if (sequenceDueDate != null && sequenceDueDate.isNotEmpty)
        'sequenceDueDate': sequenceDueDate,
      if (paymentDeadline != null && paymentDeadline.isNotEmpty)
        'paymentDeadline': paymentDeadline,
    });
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
      message: (payload['safeMessage'] as String?) ??
          'No se pudo preparar el comprobante.',
    );
  }

  /// Prepara un borrador local de CONSUMO (E32) desde una venta real.
  ///
  /// Es un flujo independiente de E31: el backend NO consume numeración de la
  /// empresa y NO toca el cupo único de sandbox, así que el borrador queda sin
  /// e-NCF hasta que ese cupo lo entregue. No emite.
  Future<EcfPreparationOutcome> prepareConsumoFromSale({
    required String saleId,
    required int paymentType,
    int? incomeType,
  }) async {
    final res = await _dio.post(
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
      message: (payload['safeMessage'] as String?) ??
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
    final res = await _dio.post(
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
      message: (payload['safeMessage'] as String?) ??
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
    return _asList(res.data)
        .map(EcfDgiiHistoryEntry.fromJson)
        .toList(growable: false);
  }

  /// Evidencias registradas por la empresa.
  Future<List<EcfDgiiEvidenceView>> dgiiEvidence() async {
    final res = await _dio.get(ApiRoutes.ecfDgiiEvidence);
    return _asList(res.data)
        .map(EcfDgiiEvidenceView.fromJson)
        .toList(growable: false);
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
        if (reason != null && reason.trim().isNotEmpty)
          'reason': reason.trim(),
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
