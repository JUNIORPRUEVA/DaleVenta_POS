import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../ecf_certificate_models.dart';

/// Envío del certificado para su validación.
///
/// El archivo y la contraseña viajan juntos en una sola petición multipart: no
/// se guardan en el dispositivo, no se cachean y no se registran. El servidor
/// responde con un informe y descarta el material.
class EcfCertificateRepository {
  EcfCertificateRepository(this._dio);

  final Dio _dio;

  Future<EcfCertificateReport> validate({
    required List<int> bytes,
    required String fileName,
    required String password,
  }) async {
    final form = FormData.fromMap({
      'password': password,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType('application', 'x-pkcs12'),
      ),
    });
    final res = await _dio.post(
      ApiRoutes.ecfDgiiCertificateValidate,
      data: form,
    );
    final data = res.data;
    if (data is Map) {
      return EcfCertificateReport.fromJson(data.cast<String, dynamic>());
    }
    throw const FormatException('ECF_CERTIFICATE_REPORT_INVALID');
  }
}

final ecfCertificateRepositoryProvider = Provider<EcfCertificateRepository>(
  (ref) => EcfCertificateRepository(ref.watch(dioProvider)),
);
