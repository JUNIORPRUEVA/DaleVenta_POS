import '../errors/api_exception.dart';

class ProductConfig {
  ProductConfig._();

  static const productCode = 'DALEVENTAS';
  static const productName = 'DaleVentas / FullPOS Cloud';
  static const productionApiBaseUrl =
      'https://daleventapos-backend.gcdndd.easypanel.host';
  static const productionApiHost = 'daleventapos-backend.gcdndd.easypanel.host';
  static const productionAppBaseUrl =
      'https://daleventapos-pwa.gcdndd.easypanel.host';
  static final forbiddenApiHosts = <String>{
    ['ventas-fullpos-backend', 'gcdndd', 'easypanel', 'host'].join('.'),
  };

  static const isOfficialProductionBuild = bool.fromEnvironment(
    'FULLPOS_PRODUCTION_BUILD',
    defaultValue: false,
  );

  static ApiException? validateApiBaseUrl(String rawBaseUrl) {
    final value = rawBaseUrl.trim();
    final uri = Uri.tryParse(value);
    final host = uri?.host.trim().toLowerCase() ?? '';

    if (value.isEmpty || uri == null || uri.scheme.isEmpty || host.isEmpty) {
      return _configError(
        'La API de DaleVentas no esta configurada correctamente.',
        'PRODUCT_API_BASE_URL_INVALID',
        'Invalid API_BASE_URL for $productCode: "$value".',
      );
    }

    if (forbiddenApiHosts.contains(host)) {
      return _configError(
        'Esta instalacion apunta a otro producto. Instala la version correcta de FullPOS Cloud.',
        'PRODUCT_BACKEND_MISMATCH',
        'Blocked forbidden backend host for $productCode: $host.',
      );
    }

    if (isOfficialProductionBuild && host != productionApiHost) {
      return _configError(
        'Esta version de produccion no reconoce el servidor configurado.',
        'PRODUCT_BACKEND_NOT_ALLOWED',
        'Official $productCode build requires $productionApiHost; received $host.',
      );
    }

    return null;
  }

  static ApiException _configError(
    String message,
    String displayCode,
    String technicalDetails,
  ) {
    return ApiException.detailed(
      message: message,
      type: ApiErrorType.config,
      displayCode: displayCode,
      technicalDetails: technicalDetails,
      retryable: false,
    );
  }
}
