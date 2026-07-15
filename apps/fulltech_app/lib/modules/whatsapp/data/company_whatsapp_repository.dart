import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../whatsapp_instance_model.dart';

final companyWhatsappRepositoryProvider = Provider<CompanyWhatsappRepository>((
  ref,
) {
  return CompanyWhatsappRepository(ref.watch(dioProvider));
});

class CompanyWhatsappRepository {
  final Dio _dio;

  CompanyWhatsappRepository(this._dio);

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String) return first.trim();
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return fallback;
  }

  ApiException _mapError(DioException e, String fallback) {
    final msg = _extractMessage(e.response?.data, fallback);
    return ApiException(msg, e.response?.statusCode);
  }

  Future<WhatsappInstanceStatusResponse> getStatus() async {
    try {
      final res = await _dio.get('/whatsapp/company-instance/status');
      return WhatsappInstanceStatusResponse.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo obtener el estado de la instancia');
    }
  }

  Future<void> createInstance({
    String? instanceName,
    String? phoneNumber,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (instanceName != null && instanceName.isNotEmpty) {
        data['instanceName'] = instanceName;
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        data['phoneNumber'] = phoneNumber;
      }
      await _dio.post('/whatsapp/company-instance', data: data);
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo crear la instancia de la empresa');
    }
  }

  Future<WhatsappQrResponse> getQr() async {
    try {
      final res = await _dio.get('/whatsapp/company-instance/qr');
      return WhatsappQrResponse.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo obtener el código QR');
    }
  }

  Future<void> deleteInstance() async {
    try {
      await _dio.delete('/whatsapp/company-instance');
    } on DioException catch (e) {
      throw _mapError(e, 'No se pudo eliminar la instancia de la empresa');
    }
  }
}
