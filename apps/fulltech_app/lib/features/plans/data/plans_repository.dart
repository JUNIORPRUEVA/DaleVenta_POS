import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';

/// Planes, acceso y ordenes de pago.
///
/// **Los precios y los limites nunca se escriben aqui**: llegan de
/// `GET /license/plans`. Si el catalogo cambia en el servidor, la app cambia
/// sin publicar una version nueva.
final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  return PlansRepository(ref.watch(dioProvider));
});

final plansCatalogProvider = FutureProvider<List<PlanOffer>>((ref) async {
  return ref.watch(plansRepositoryProvider).fetchPlans();
});

/// Crea el ticket de soporte para ampliar el plan.
///
/// Se expone como funcion (y no como llamada directa desde la pantalla) para
/// poder probar el flujo sin red.
typedef PlanUpgradeRequester =
    Future<PlanUpgradeRequest> Function({String? planCode, String? message});

final planUpgradeRequesterProvider = Provider<PlanUpgradeRequester>((ref) {
  final repo = ref.watch(plansRepositoryProvider);
  return ({String? planCode, String? message}) =>
      repo.requestPlanUpgrade(planCode: planCode, message: message);
});

/// Ticket de mejora que ya esta abierto (si lo hay).
final planUpgradeOpenProvider = FutureProvider<PlanUpgradeRequest?>((ref) async {
  return ref.watch(plansRepositoryProvider).fetchOpenPlanUpgrade();
});

final paymentInstructionsProvider =
    FutureProvider<PaymentInstructions>((ref) async {
  return ref.watch(plansRepositoryProvider).fetchPaymentInstructions();
});

final licenseOrdersProvider = FutureProvider<List<LicenseOrder>>((ref) async {
  return ref.watch(plansRepositoryProvider).fetchOrders();
});

/// Importe a transferir para un plan y unos meses concretos. La cuenta la
/// hace el servidor: incluye el credito de los dias no consumidos cuando el
/// cliente cambia de plan.
final orderQuoteProvider =
    FutureProvider.family<OrderQuote, ({String planCode, int months})>((
      ref,
      params,
    ) async {
      return ref
          .watch(plansRepositoryProvider)
          .fetchQuote(planCode: params.planCode, months: params.months);
    });

class PlansRepository {
  PlansRepository(this._dio);

  final Dio _dio;
  static const _timeout = Duration(seconds: 20);
  Options get _silent => Options(extra: const {'skipLoader': true});

  Future<List<PlanOffer>> fetchPlans() async {
    final data = await _get(ApiRoutes.licensePlans);
    final raw = data['plans'];
    if (raw is! List) throw ApiException('La API no devolvio el catalogo de planes.');
    return raw
        .whereType<Map>()
        .map((row) => PlanOffer.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<PaymentInstructions> fetchPaymentInstructions() async {
    return PaymentInstructions.fromJson(await _get(ApiRoutes.licensePaymentInstructions));
  }

  Future<List<LicenseOrder>> fetchOrders() async {
    final data = await _get(ApiRoutes.licenseOrders);
    final raw = data['orders'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) => LicenseOrder.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<LicenseOrder> createOrder(String planCode, {int months = 1}) async {
    final data = await _post(ApiRoutes.licenseOrders, {
      'planCode': planCode,
      'months': months,
    });
    return LicenseOrder.fromJson(data);
  }

  Future<OrderQuote> fetchQuote({
    required String planCode,
    int months = 1,
  }) async {
    final data = await _get(
      '${ApiRoutes.licenseOrderQuote}?planCode=$planCode&months=$months',
    );
    return OrderQuote.fromJson(data);
  }

  /// Abre un ticket de soporte para ampliar el plan cuando la empresa ya esta
  /// en el ultimo del catalogo. El servidor no repite la solicitud si ya hay
  /// una abierta: devuelve la misma referencia.
  Future<PlanUpgradeRequest> requestPlanUpgrade({
    String? planCode,
    String? message,
  }) async {
    final data = await _post(ApiRoutes.licensePlanRequests, {
      if (planCode != null && planCode.trim().isNotEmpty) 'planCode': planCode,
      if (message != null && message.trim().isNotEmpty) 'message': message,
    });
    final request = data['request'];
    return PlanUpgradeRequest.fromJson(request);
  }

  /// Solicitud de mejora ya abierta, para no pedirla dos veces.
  Future<PlanUpgradeRequest?> fetchOpenPlanUpgrade() async {
    final data = await _get(ApiRoutes.licensePlanRequests);
    final request = data['request'];
    if (request == null) return null;
    return PlanUpgradeRequest.fromJson(request);
  }

  Future<void> cancelOrder(String orderId) async {
    await _post(ApiRoutes.licenseOrderCancel(orderId), const {});
  }

  /// Sube el comprobante. El servidor valida la firma real del archivo y deja
  /// el pago registrado; la licencia se actualiza cuando el pago se verifica.
  Future<EvidenceUploadResult> uploadEvidence({
    required String orderId,
    required String filePath,
    required String fileName,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    try {
      final res = await _dio
          .post(
            ApiRoutes.licenseOrderEvidence(orderId),
            data: form,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_timeout);
      final data = _map(res.data);
      return EvidenceUploadResult(
        activated: data['license'] is Map,
        message: (data['message'] ?? '').toString(),
      );
    } on TimeoutException {
      throw ApiException('El comprobante tardo demasiado en subir.');
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data), e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final res = await _dio.get(path, options: _silent).timeout(_timeout);
      return _map(res.data);
    } on TimeoutException {
      throw ApiException('El servidor tardo demasiado en responder.');
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data), e.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _dio
          .post(path, data: payload, options: _silent)
          .timeout(_timeout);
      return _map(res.data);
    } on TimeoutException {
      throw ApiException('El servidor tardo demasiado en responder.');
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data), e.response?.statusCode);
    }
  }

  static Map<String, dynamic> _map(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((key, value) => MapEntry('$key', value));
    throw ApiException('La API devolvio una respuesta inesperada.');
  }

  static String _message(dynamic data) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        return message.map((item) => '$item').join(' | ');
      }
    }
    return 'No se pudo completar la operacion con el plan.';
  }
}

class PlanFeatureFlags {
  const PlanFeatureFlags({
    required this.multiWarehouse,
    required this.wholesale,
    required this.uom,
    required this.ecf,
    required this.taxes,
  });

  final bool multiWarehouse;
  final bool wholesale;
  final bool uom;
  final bool ecf;
  final bool taxes;

  factory PlanFeatureFlags.fromJson(dynamic value) {
    final map = value is Map ? value : const {};
    bool read(String key) => map[key] == true;
    return PlanFeatureFlags(
      multiWarehouse: read('multiWarehouse'),
      wholesale: read('wholesale'),
      uom: read('uom'),
      ecf: read('ecf'),
      taxes: read('taxes'),
    );
  }
}

class PlanOffer {
  const PlanOffer({
    required this.code,
    required this.name,
    required this.version,
    required this.monthlyPrice,
    required this.currency,
    required this.maxUsers,
    required this.maxProducts,
    required this.maxWarehouses,
    required this.features,
    this.ecfMonthlyQuota,
    this.highlight = false,
  });

  final String code;
  final String name;
  final int version;
  final double monthlyPrice;
  final String currency;
  final int maxUsers;
  final int maxProducts;
  final int maxWarehouses;
  final PlanFeatureFlags features;
  final int? ecfMonthlyQuota;

  /// El plan que la web marca como «Mas elegido». Se calcula por codigo para
  /// que el servidor no tenga que publicar decisiones comerciales.
  final bool highlight;

  String get shortName {
    final parts = name.trim().split(' ');
    return parts.isEmpty ? name : parts.last;
  }

  /// Lo que se puede afirmar de cada funcion, con el mismo texto de la web.
  List<String> get included {
    return [
      '$maxUsers ${maxUsers == 1 ? 'usuario' : 'usuarios'}',
      '$maxProducts productos',
      maxWarehouses > 1 ? 'Hasta $maxWarehouses almacenes' : '1 almacén',
      if (features.ecf) 'Facturación electrónica',
      if (features.taxes) 'Impuestos (ITBIS)',
      if (features.wholesale) 'Mayoreo y listas de precio',
      if (features.uom) 'Unidad de medida',
      if (features.multiWarehouse) 'Multi-almacén',
    ];
  }

  List<String> get excluded {
    return [
      if (!features.ecf) 'Facturación electrónica',
      if (!features.taxes) 'Impuestos (ITBIS)',
      if (!features.wholesale) 'Mayoreo y listas de precio',
      if (!features.multiWarehouse) 'Multi-almacén',
    ];
  }

  factory PlanOffer.fromJson(Map<String, dynamic> json) {
    final limits = json['limits'] is Map ? json['limits'] as Map : const {};
    final code = (json['code'] ?? '').toString();
    return PlanOffer(
      code: code,
      name: (json['name'] ?? code).toString(),
      version: (json['version'] as num?)?.toInt() ?? 1,
      monthlyPrice: double.tryParse('${json['monthlyPrice'] ?? 0}') ?? 0,
      currency: (json['currency'] ?? 'DOP').toString(),
      maxUsers: (limits['maxUsers'] as num?)?.toInt() ?? 0,
      maxProducts: (limits['maxProducts'] as num?)?.toInt() ?? 0,
      maxWarehouses: (limits['maxWarehouses'] as num?)?.toInt() ?? 1,
      features: PlanFeatureFlags.fromJson(json['features']),
      ecfMonthlyQuota: (json['ecfMonthlyQuota'] as num?)?.toInt(),
      highlight: code.toLowerCase() == 'negocio',
    );
  }
}

class PaymentInstructions {
  const PaymentInstructions({
    required this.configured,
    required this.instructions,
    this.bankName,
    this.accountNumber,
    this.accountType,
    this.holder,
    this.holderTaxId,
    this.singleAccount = true,
    this.beforeTransfer,
    this.otherBankNote,
  });

  final bool configured;
  final String instructions;
  final String? bankName;
  final String? accountNumber;
  final String? accountType;
  final String? holder;
  final String? holderTaxId;
  /// Solo hay una cuenta para pagos.
  final bool singleAccount;
  /// Recordatorio previo: monto exacto y a nombre de quien se transfiere.
  final String? beforeTransfer;
  /// Que hacer si el banco del cliente es distinto (pago al instante + RNC).
  final String? otherBankNote;

  factory PaymentInstructions.fromJson(Map<String, dynamic> json) {
    String? read(String key) {
      final raw = json[key]?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    return PaymentInstructions(
      configured: json['configured'] == true,
      instructions: read('instructions') ?? '',
      bankName: read('bankName'),
      accountNumber: read('accountNumber'),
      accountType: read('accountType'),
      holder: read('holder'),
      holderTaxId: read('holderTaxId'),
      singleAccount: json['singleAccount'] != false,
      beforeTransfer: read('beforeTransfer'),
      otherBankNote: read('otherBankNote'),
    );
  }
}

class LicenseOrderEvidence {
  const LicenseOrderEvidence({
    required this.id,
    required this.mime,
    required this.sizeBytes,
    this.createdAt,
  });

  final String id;
  final String mime;
  final int sizeBytes;
  final DateTime? createdAt;

  factory LicenseOrderEvidence.fromJson(Map<String, dynamic> json) {
    return LicenseOrderEvidence(
      id: (json['id'] ?? '').toString(),
      mime: (json['mime'] ?? '').toString(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
    );
  }
}

/// Lo que el cliente debe transferir hoy: precio x meses menos el credito de
/// los dias que aun no ha consumido (solo al cambiar de plan).
class OrderQuote {
  const OrderQuote({
    required this.planCode,
    required this.planName,
    required this.months,
    required this.currency,
    required this.monthlyPrice,
    required this.subtotal,
    required this.credit,
    required this.creditDays,
    required this.creditPlanCode,
    required this.amountDue,
    required this.planChange,
  });

  final String planCode;
  final String planName;
  final int months;
  final String currency;
  final double monthlyPrice;
  final double subtotal;
  final double credit;
  final int creditDays;
  final String? creditPlanCode;
  final double amountDue;

  /// `true` cuando el saldo a favor cubre toda la diferencia: la mejora no
  /// necesita transferencia.
  bool get covered => amountDue <= 0;
  final bool planChange;

  bool get hasCredit => credit > 0;

  factory OrderQuote.fromJson(Map<String, dynamic> json) {
    double money(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return OrderQuote(
      planCode: (json['planCode'] ?? '').toString(),
      planName: (json['planName'] ?? '').toString(),
      months: (json['months'] as num?)?.toInt() ?? 1,
      currency: (json['currency'] ?? 'DOP').toString(),
      monthlyPrice: money(json['monthlyPrice']),
      subtotal: money(json['subtotal']),
      credit: money(json['credit']),
      creditDays: (json['creditDays'] as num?)?.toInt() ?? 0,
      creditPlanCode: json['creditPlanCode']?.toString(),
      amountDue: money(json['amountDue']),
      planChange: json['planChange'] == true,
    );
  }
}

class LicenseOrder {
  const LicenseOrder({
    required this.id,
    required this.planCode,
    required this.amount,
    required this.currency,
    required this.months,
    required this.status,
    required this.reference,
    this.planName,
    this.expiresAt,
    this.periodStart,
    this.periodEnd,
    this.createdAt,
    this.evidences = const [],
  });

  final String id;
  final String planCode;
  final String? planName;
  final double amount;
  final String currency;
  final int months;
  final String status;
  final String reference;
  final DateTime? expiresAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? createdAt;
  final List<LicenseOrderEvidence> evidences;

  bool get isOpen => status == 'CREATED' || status == 'AWAITING_TRANSFER';

  bool get hasEvidence => evidences.isNotEmpty;

  String get statusLabel {
    switch (status) {
      case 'AWAITING_TRANSFER':
        return 'Esperando tu transferencia';
      case 'EVIDENCE_RECEIVED':
      case 'UNCONFIRMED':
        return 'Comprobante en revisión';
      case 'SETTLED':
        return 'Pagada';
      case 'REJECTED':
        return 'Rechazada';
      case 'CANCELLED':
        return 'Cancelada';
      case 'EXPIRED':
        return 'Vencida';
      default:
        return status;
    }
  }

  factory LicenseOrder.fromJson(Map<String, dynamic> json) {
    final raw = json['evidences'];
    return LicenseOrder(
      id: (json['id'] ?? '').toString(),
      planCode: (json['planCode'] ?? '').toString(),
      planName: json['planName']?.toString(),
      amount: double.tryParse('${json['amount'] ?? 0}') ?? 0,
      currency: (json['currency'] ?? 'DOP').toString(),
      months: (json['months'] as num?)?.toInt() ?? 1,
      status: (json['status'] ?? 'CREATED').toString(),
      reference: (json['reference'] ?? '').toString(),
      expiresAt: DateTime.tryParse('${json['expiresAt'] ?? ''}'),
      periodStart: DateTime.tryParse('${json['periodStart'] ?? ''}'),
      periodEnd: DateTime.tryParse('${json['periodEnd'] ?? ''}'),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      evidences: raw is List
          ? raw
              .whereType<Map>()
              .map((row) => LicenseOrderEvidence.fromJson(Map<String, dynamic>.from(row)))
              .toList(growable: false)
          : const [],
    );
  }
}

/// Ticket de soporte para ampliar el plan cuando ya se esta en el ultimo.
class PlanUpgradeRequest {
  const PlanUpgradeRequest({
    required this.id,
    required this.reference,
    required this.status,
  });

  final String id;
  final String reference;
  final String status;

  factory PlanUpgradeRequest.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const PlanUpgradeRequest(id: '', reference: '', status: 'OPEN');
    }
    return PlanUpgradeRequest(
      id: (raw['id'] ?? '').toString(),
      reference: (raw['reference'] ?? '').toString(),
      status: (raw['status'] ?? 'OPEN').toString(),
    );
  }
}

class EvidenceUploadResult {  const EvidenceUploadResult({required this.activated, required this.message});

  final bool activated;
  final String message;
}
