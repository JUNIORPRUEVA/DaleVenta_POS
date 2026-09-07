import 'package:daleventa_pos/core/api/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release fallback host is the current DaleVentas backend', () {
    expect(
      Env.apiBaseUrl,
      'https://daleventapos-backend.gcdndd.easypanel.host',
    );
    expect(Env.apiBaseUrl, isNot(contains('ventas-fullpos-backend')));
  });
}
