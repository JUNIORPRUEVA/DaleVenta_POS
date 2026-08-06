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
    this.trialEndsAt,
    this.licenseExpiresAt,
    this.licenseKey,
    this.notes,
    this.daysRemaining,
  });

  final String companyId;
  final String companyName;
  final String plan;
  final String status;
  final bool isUsable;
  final String? blockReason;
  final DateTime? trialEndsAt;
  final DateTime? licenseExpiresAt;
  final String? licenseKey;
  final String? notes;
  final int maxUsers;
  final int maxProducts;
  final int users;
  final int products;
  final int? daysRemaining;

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
      trialEndsAt: _date(json['trialEndsAt']),
      licenseExpiresAt: _date(json['licenseExpiresAt']),
      licenseKey: json['licenseKey']?.toString(),
      notes: json['notes']?.toString(),
      maxUsers: (limits['maxUsers'] as num?)?.toInt() ?? 2,
      maxProducts: (limits['maxProducts'] as num?)?.toInt() ?? 100,
      users: (usage['users'] as num?)?.toInt() ?? 0,
      products: (usage['products'] as num?)?.toInt() ?? 0,
      daysRemaining: (json['daysRemaining'] as num?)?.toInt(),
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse('$value');
  }
}
