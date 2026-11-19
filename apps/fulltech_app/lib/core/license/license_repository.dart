import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_repository.dart';
import '../errors/api_exception.dart';
import 'license_demo_state.dart';

final licenseRepositoryProvider = Provider<LicenseRepository>((ref) {
  return LicenseRepository(ref.watch(dioProvider));
});

/// Licencia de la empresa.
///
/// En desarrollo se puede **simular** una empresa con otro estado
/// (`LICENSE_DEMO_STATE`): en ese caso no se llama al servidor y se devuelve una
/// licencia ficticia con la misma forma que la real, para poder revisar todas
/// las pantallas sin tocar datos ni licencias de nadie. En release el escenario
/// es siempre `off`, asi que esto no puede saltarse ninguna restriccion.
final licenseStatusProvider = FutureProvider<LicenseStatusModel>((ref) async {
  final demo = ref.watch(licenseDemoScenarioProvider);
  if (demo.isOn) {
    return LicenseStatusModel.fromJson(demoLicenseJson(demo));
  }
  return ref.watch(licenseRepositoryProvider).getLicense();
});

class LicenseRepository {
  LicenseRepository(this._dio);

  final Dio _dio;
  static const _timeout = Duration(seconds: 18);

  Future<LicenseStatusModel> getLicense() async {
    try {
      final res = await _dio
          .get(
            ApiRoutes.license,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_timeout);
      return LicenseStatusModel.fromJson(_map(res.data));
    } on TimeoutException {
      throw ApiException('La licencia tardó demasiado en cargar.');
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data), e.response?.statusCode);
    }
  }

  // `activate`, `block` y `updateLimits` se eliminaron con sus rutas del
  // servidor: la licencia solo cambia por el flujo de planes (orden +
  // comprobante) o desde el equipo con el secreto de administracion. Dejarlos
  // aqui solo servia para volver a abrir el atajo que permitia activarse sin
  // pagar.

  static Map<String, dynamic> _map(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((key, value) => MapEntry('$key', value));
    throw ApiException('La API devolvió una licencia inválida.');
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
    return 'No se pudo completar la operación de licencia.';
  }
}

/// Estado de la proxima cuota.
///
/// `state` llega calculado del servidor y solo puede ser uno de estos cuatro:
/// `CURRENT` (al dia), `UPCOMING` (cuota proxima, se puede pagar ya),
/// `IN_REVIEW` (pago enviado, esperando verificacion) y `OVERDUE` (vencida).
class RenewalInfo {
  const RenewalInfo({
    required this.state,
    this.dueDate,
    this.daysLeft,
    this.amount,
    this.currency = 'DOP',
    this.planCode,
    this.planName,
    this.windowDays = 10,
    this.order,
  });

  final String state;
  final DateTime? dueDate;
  final int? daysLeft;
  final double? amount;
  final String currency;
  final String? planCode;
  final String? planName;
  final int windowDays;
  final RenewalOrderInfo? order;

  bool get isUpcoming => state == 'UPCOMING';
  bool get isInReview => state == 'IN_REVIEW';
  bool get isOverdue => state == 'OVERDUE';

  /// Todavia se puede pagar sin interrupcion (cuota proxima o vencida).
  bool get canPay => isUpcoming || isOverdue;

  factory RenewalInfo.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const RenewalInfo(state: 'CURRENT');
    }
    return RenewalInfo(
      state: (raw['state'] ?? 'CURRENT').toString().toUpperCase(),
      dueDate: LicenseStatusModel._date(raw['dueDate']),
      daysLeft: (raw['daysLeft'] as num?)?.toInt(),
      amount: (raw['amount'] as num?)?.toDouble(),
      currency: (raw['currency'] ?? 'DOP').toString(),
      planCode: raw['planCode']?.toString(),
      planName: raw['planName']?.toString(),
      windowDays: (raw['windowDays'] as num?)?.toInt() ?? 10,
      order: RenewalOrderInfo.fromJson(raw['order']),
    );
  }
}

/// Orden abierta que respalda la proxima cuota (si ya existe).
class RenewalOrderInfo {
  const RenewalOrderInfo({
    required this.id,
    required this.reference,
    required this.amount,
    required this.currency,
    required this.status,
    required this.months,
  });

  final String id;
  final String reference;
  final double amount;
  final String currency;
  final String status;
  final int months;

  /// La orden existe y todavia no tiene comprobante: hay que pagarla.
  bool get isPayable =>
      status.toUpperCase() == 'AWAITING_TRANSFER' ||
      status.toUpperCase() == 'CREATED';

  factory RenewalOrderInfo.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const RenewalOrderInfo(
        id: '',
        reference: '',
        amount: 0,
        currency: 'DOP',
        status: '',
        months: 1,
      );
    }
    return RenewalOrderInfo(
      id: (raw['id'] ?? '').toString(),
      reference: (raw['reference'] ?? '').toString(),
      amount: (raw['amount'] as num?)?.toDouble() ?? 0,
      currency: (raw['currency'] ?? 'DOP').toString(),
      status: (raw['status'] ?? '').toString(),
      months: (raw['months'] as num?)?.toInt() ?? 1,
    );
  }
}

class LicenseStatusModel {
  const LicenseStatusModel({    required this.companyId,
    required this.companyName,
    required this.plan,
    required this.status,
    required this.isUsable,
    required this.maxUsers,
    required this.maxProducts,
    required this.users,
    required this.products,
    this.blockReason,
    this.trialStartedAt,
    this.trialEndsAt,
    this.licenseActivatedAt,
    this.licenseExpiresAt,
    this.licenseBlockedAt,
    this.periodStartedAt,
    this.periodEndsAtOverride,
    this.licenseType,
    this.licenseTypeLabel,
    this.licenseKey,
    this.notes,
    this.daysRemaining,
    this.account,
    this.planCode,
    this.maxWarehouses = 1,
    this.renewal,
    this.access,
  });

  final String companyId;
  final String companyName;
  final String plan;
  final String status;
  final bool isUsable;
  final String? blockReason;
  final DateTime? trialStartedAt;
  final DateTime? trialEndsAt;
  final DateTime? licenseActivatedAt;
  final DateTime? licenseExpiresAt;
  final DateTime? licenseBlockedAt;
  final DateTime? periodStartedAt;
  final DateTime? periodEndsAtOverride;
  final String? licenseType;
  final String? licenseTypeLabel;
  final String? licenseKey;
  final String? notes;
  final int maxUsers;
  final int maxProducts;
  /// Cuantos almacenes permite el plan (1 / 3 / 5 / 10 segun catalogo).
  final int maxWarehouses;
  final int users;
  final int products;
  final int? daysRemaining;
  final LicenseAccountInfo? account;
  /// Codigo del plan del catalogo (`basico`, `negocio`, `pro`, `empresa`).
  final String? planCode;

  /// Estado de la proxima cuota. Lo calcula el servidor: la pantalla no
  /// decide por su cuenta si una cuota esta pendiente.
  final RenewalInfo? renewal;

  /// Nivel de acceso efectivo (FULL/RESTRICTED/BLOCKED) que calcula el
  /// servidor con la misma politica que usa el guard.
  final LicenseAccessInfo? access;

  /// La licencia vencio y el cliente tiene que renovar para volver a trabajar.
  ///
  /// Manda el nivel que calcula el servidor (`access`). Si una version
  /// anterior de la API no lo envia, se usan los datos que si publica: la
  /// licencia no es usable y el periodo ya termino. Nunca se deduce de la
  /// cuota (`renewal`): un comprobante en revision no es una licencia vencida.
  bool get isLicenseExpired {
    final level = access?.level;
    if (level != null && level.isNotEmpty) return level == 'RESTRICTED';
    if (!isUsable && status.toUpperCase() != 'BLOCKED') {
      final end = licenseExpiresAt ?? trialEndsAt;
      return end != null && end.isBefore(DateTime.now());
    }
    return false;
  }

  /// La **demo** (los días de prueba) terminó y el cliente nunca pasó a un plan
  /// de pago: tiene su propia pantalla, no la de «plan vencido».
  ///
  /// Manda el servidor (`access.reason == 'TRIAL_EXPIRED'`). El respaldo sirve
  /// para APIs anteriores que no envían `access`: la licencia de prueba venció
  /// y no hay ninguna activación de pago. Una empresa que ya pagó y luego venció
  /// conserva `licenseActivatedAt`, así que no se confunde con la demo.
  bool get isTrialExpired {
    final current = access;
    if (current != null && current.level.isNotEmpty) return current.isTrialExpired;
    final trialEnd = trialEndsAt;
    return status.toUpperCase() == 'EXPIRED' &&
        licenseActivatedAt == null &&
        trialEnd != null &&
        trialEnd.isBefore(DateTime.now());
  }

  factory LicenseStatusModel.fromJson(Map<String, dynamic> json) {
    final limits = (json['limits'] as Map?) ?? const {};
    final usage = (json['usage'] as Map?) ?? const {};
    return LicenseStatusModel(
      companyId: (json['companyId'] ?? '').toString(),
      companyName: (json['companyName'] ?? '').toString(),
      plan: (json['plan'] ?? 'STANDARD').toString(),
      planCode: json['planCode']?.toString(),
      status: (json['status'] ?? 'TRIAL').toString(),
      isUsable: json['isUsable'] == true,
      blockReason: json['blockReason']?.toString(),
      trialStartedAt: _date(json['trialStartedAt']),
      trialEndsAt: _date(json['trialEndsAt']),
      licenseActivatedAt: _date(json['licenseActivatedAt']),
      licenseExpiresAt: _date(json['licenseExpiresAt']),
      licenseBlockedAt: _date(json['licenseBlockedAt']),
      periodStartedAt: _date(json['periodStartedAt']),
      periodEndsAtOverride: _date(json['periodEndsAt']),
      licenseType: json['licenseType']?.toString(),
      licenseTypeLabel: json['licenseTypeLabel']?.toString(),
      licenseKey: json['licenseKey']?.toString(),
      notes: json['notes']?.toString(),
      maxUsers: (limits['maxUsers'] as num?)?.toInt() ?? 2,
      maxProducts: (limits['maxProducts'] as num?)?.toInt() ?? 100,
      maxWarehouses: (limits['maxWarehouses'] as num?)?.toInt() ?? 1,
      users: (usage['users'] as num?)?.toInt() ?? 0,
      products: (usage['products'] as num?)?.toInt() ?? 0,
      daysRemaining: (json['daysRemaining'] as num?)?.toInt(),
      account: LicenseAccountInfo.fromJson(json['account']),
      renewal: RenewalInfo.fromJson(json['renewal']),
      access: LicenseAccessInfo.fromJson(json['access']),
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }

  String get planLabel {
    final cleaned = plan.trim();
    if (cleaned.isEmpty || cleaned.toUpperCase() == 'STANDARD') {
      return 'Plan basico';
    }
    if (cleaned.toUpperCase() == 'ENTERPRISE') return 'Plan enterprise';
    return cleaned;
  }

  String get typeLabel {
    final label = licenseTypeLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    final type = licenseType?.trim().toUpperCase();
    if (type == 'TRIAL') return 'Plan demo';
    if (type == 'BASIC_EXTENDED') return 'Plan basico ampliado';
    if (type == 'ENTERPRISE') return 'Plan enterprise';
    return planLabel;
  }

  DateTime? get acquiredAt {
    if (periodStartedAt != null) return periodStartedAt;
    if (licenseActivatedAt != null) return licenseActivatedAt;
    return trialStartedAt;
  }

  DateTime? get periodEndsAt {
    if (periodEndsAtOverride != null) return periodEndsAtOverride;
    if (status.toUpperCase() == 'TRIAL') return trialEndsAt;
    return licenseExpiresAt;
  }
}

/// Nivel de acceso efectivo de la empresa a la aplicacion.
///
/// Lo calcula **solo** el servidor (`license.access.policy.ts`) para que la
/// app, el login y el guard no puedan decir cosas distintas.
class LicenseAccessInfo {
  const LicenseAccessInfo({
    required this.level,
    required this.reason,
    this.daysRemaining,
    this.periodEndsAt,
    this.effectiveStatus,
  });

  /// `FULL` trabaja con normalidad, `RESTRICTED` licencia vencida (solo Planes
  /// y Soporte), `BLOCKED` suspendida por decision humana.
  final String level;

  /// Motivo: `TRIAL`, `ACTIVE`, `EXPIRED`, `TRIAL_EXPIRED`, `BLOCKED`...
  final String reason;

  final int? daysRemaining;
  final DateTime? periodEndsAt;
  final String? effectiveStatus;

  bool get isRestricted => level == 'RESTRICTED';

  /// El periodo que venció fue la **prueba**, no un plan pagado.
  bool get isTrialExpired => reason == 'TRIAL_EXPIRED';

  factory LicenseAccessInfo.fromJson(dynamic raw) {
    if (raw is! Map) {
      return const LicenseAccessInfo(level: '', reason: '');
    }
    return LicenseAccessInfo(
      level: (raw['level'] ?? '').toString().toUpperCase(),
      reason: (raw['reason'] ?? '').toString().toUpperCase(),
      daysRemaining: (raw['daysRemaining'] as num?)?.toInt(),
      periodEndsAt: LicenseStatusModel._date(raw['periodEndsAt']),
      effectiveStatus: raw['effectiveStatus']?.toString(),
    );
  }
}

class LicenseAccountInfo {
  const LicenseAccountInfo({
    this.businessName,
    this.taxId,
    this.businessPhone,
    this.businessAddress,
    this.businessType,
    this.responsibleName,
    this.responsibleEmail,
    this.responsibleWhatsapp,
    this.responsibleUserId,
    this.legalRepresentativeName,
    this.legalRepresentativeCedula,
    this.legalRepresentativeRole,
  });

  final String? businessName;
  final String? taxId;
  final String? businessPhone;
  final String? businessAddress;
  final String? businessType;
  final String? responsibleName;
  final String? responsibleEmail;
  final String? responsibleWhatsapp;
  final String? responsibleUserId;
  final String? legalRepresentativeName;
  final String? legalRepresentativeCedula;
  final String? legalRepresentativeRole;

  factory LicenseAccountInfo.fromJson(dynamic value) {
    if (value is! Map) return const LicenseAccountInfo();
    String? read(String key) {
      final raw = value[key]?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    return LicenseAccountInfo(
      businessName: read('businessName'),
      taxId: read('taxId'),
      businessPhone: read('businessPhone'),
      businessAddress: read('businessAddress'),
      businessType: read('businessType'),
      responsibleName: read('responsibleName'),
      responsibleEmail: read('responsibleEmail'),
      responsibleWhatsapp: read('responsibleWhatsapp'),
      responsibleUserId: read('responsibleUserId'),
      legalRepresentativeName: read('legalRepresentativeName'),
      legalRepresentativeCedula: read('legalRepresentativeCedula'),
      legalRepresentativeRole: read('legalRepresentativeRole'),
    );
  }
}
