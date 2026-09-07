import 'package:daleventa_pos/core/api/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dart define can explicitly target the UAT backend', () {
    expect(Env.apiBaseUrl, 'http://31.97.99.70:4001');
    expect(
      Env.apiBaseUrl,
      isNot('https://daleventapos-backend.gcdndd.easypanel.host'),
    );
  });
}
