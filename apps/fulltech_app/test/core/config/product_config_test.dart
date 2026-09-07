import 'package:daleventa_pos/core/config/product_config.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DaleVentas production backend is accepted', () {
    expect(
      ProductConfig.validateApiBaseUrl(ProductConfig.productionApiBaseUrl),
      isNull,
    );
  });

  test('FullPOS Owner backend is blocked for DaleVentas clients', () {
    final error = ProductConfig.validateApiBaseUrl(
      'https://ventas-fullpos-backend.gcdndd.easypanel.host',
    );

    expect(error, isA<ApiException>());
    expect(error!.displayCode, 'PRODUCT_BACKEND_MISMATCH');
    expect(error.type, ApiErrorType.config);
  });

  test('invalid backend configuration fails closed', () {
    final error = ProductConfig.validateApiBaseUrl('not-a-url');

    expect(error, isA<ApiException>());
    expect(error!.displayCode, 'PRODUCT_API_BASE_URL_INVALID');
  });
}
