import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/utils/geo_utils.dart';

void main() {
  group('parseLatLngFromText', () {
    test('parses Google Maps search query links', () {
      final point = parseLatLngFromText(
        'https://www.google.com/maps/search/?api=1&query=18.486058%2C-69.931212',
      );

      expect(point, isNotNull);
      expect(point!.latitude, closeTo(18.486058, 0.000001));
      expect(point.longitude, closeTo(-69.931212, 0.000001));
    });

    test('parses loc-prefixed WhatsApp and Maps links', () {
      final point = parseLatLngFromText(
        'https://maps.google.com/?q=loc:18.500123,-69.900456',
      );

      expect(point, isNotNull);
      expect(point!.latitude, closeTo(18.500123, 0.000001));
      expect(point.longitude, closeTo(-69.900456, 0.000001));
    });

    test('parses path segments that contain coordinates', () {
      final point = parseLatLngFromText(
        'https://www.google.com/maps/search/18.472001,-69.892001?entry=ttu',
      );

      expect(point, isNotNull);
      expect(point!.latitude, closeTo(18.472001, 0.000001));
      expect(point.longitude, closeTo(-69.892001, 0.000001));
    });
  });
}
