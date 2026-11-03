import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../ecf_certificate_models.dart';

/// Envío del certificado para su validación.
///
/// Tratamiento REAL de los datos, sin adornos: el archivo y la contraseña viajan
/// juntos en una sola petición multipart **por HTTPS** hasta FullPOS Cloud. El
/// servidor los valida en memoria y no los persiste: no se escriben en disco, no
/// se guardan en la base de datos, no se registran en logs ni en auditoría y no
/// se reenvían a la DGII ni a DOSA. En el dispositivo tampoco se guardan.
///
/// Se envía al backend a propósito: es el único sitio donde el certificado se
/// puede comparar con la identidad canónica del expediente, que el cliente no
/// conoce ni puede declarar.
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
