import 'package:daleventa_pos/core/api/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uatApiBaseUrl = 'http://31.97.99.70:4001';
  const configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

  test(
    'dart define can explicitly target the UAT backend',
    () {
      expect(Env.apiBaseUrl, 'http://31.97.99.70:4001');
      expect(
        Env.apiBaseUrl,
        isNot('https://daleventapos-backend.gcdndd.easypanel.host'),
      );
    },
    skip: configuredApiBaseUrl == uatApiBaseUrl
        ? false
        : 'UAT-only env test; run with --dart-define=API_BASE_URL=$uatApiBaseUrl.',
  );
}
