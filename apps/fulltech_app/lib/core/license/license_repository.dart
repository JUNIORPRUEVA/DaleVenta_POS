import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_repository.dart';
import '../errors/api_exception.dart';

final licenseRepositoryProvider = Provider<LicenseRepository>((ref) {
  return LicenseRepository(ref.watch(dioProvider));
});

final licenseStatusProvider = FutureProvider<LicenseStatusModel>((ref) async {
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

  Future<LicenseStatusModel> activate({
    required int maxUsers,
    required int maxProducts,
    DateTime? expiresAt,
    String? notes,
  }) {
    return _send(ApiRoutes.licenseActivate, {
      'maxUsers': maxUsers,
      'maxProducts': maxProducts,
      'expiresAt': expiresAt?.toIso8601String(),
      'notes': notes,
    });
  }

  Future<LicenseStatusModel> block({String? notes}) {
    return _send(ApiRoutes.licenseBlock, {'notes': notes});
  }

  Future<LicenseStatusModel> updateLimits({
    required int maxUsers,
    required int maxProducts,
    DateTime? expiresAt,
    String? notes,
  }) {
    return _patch(ApiRoutes.licenseLimits, {
      'maxUsers': maxUsers,
      'maxProducts': maxProducts,
      'expiresAt': expiresAt?.toIso8601String(),
      'notes': notes,
    });
  }

  Future<LicenseStatusModel> _send(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _dio
          .post(
            path,
            data: payload,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_timeout);
      return LicenseStatusModel.fromJson(_map(res.data));
    } on TimeoutException {
      throw ApiException('La operación de licencia tardó demasiado.');
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data), e.response?.statusCode);
    }
  }

  Future<LicenseStatusModel> _patch(
    String path,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _dio
          .patch(
            path,
            data: payload,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_timeout);
      return LicenseStatusModel.fromJson(_map(res.data));
    } on TimeoutException {
      throw ApiException('La operación de licencia tardó demasiado.');
    } on DioException catch (e) {
      throw ApiException(_message(e.response?.data), e.response?.statusCode);
    }
  }

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

class LicenseStatusModel {
  const LicenseStatusModel({
    required this.companyId,
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
  final int users;
  final int products;
  final int? daysRemaining;
  final LicenseAccountInfo? account;

  factory LicenseStatusModel.fromJson(Map<String, dynamic> json) {
    final limits = (json['limits'] as Map?) ?? const {};
    final usage = (json['usage'] as Map?) ?? const {};
    return LicenseStatusModel(
      companyId: (json['companyId'] ?? '').toString(),
      companyName: (json['companyName'] ?? '').toString(),
      plan: (json['plan'] ?? 'STANDARD').toString(),
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
      users: (usage['users'] as num?)?.toInt() ?? 0,
      products: (usage['products'] as num?)?.toInt() ?? 0,
      daysRemaining: (json['daysRemaining'] as num?)?.toInt(),
      account: LicenseAccountInfo.fromJson(json['account']),
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
    );
  }
}
