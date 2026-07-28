import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/utils/product_image_url.dart';

void main() {
  group('normalizeProductImageUrl', () {
    test('rewrites legacy external upload URLs to the API host', () {
      const imageUrl =
          'https://legacy.example.com/uploads/products/demo-image.jpg?v=123';
      const baseUrl = 'https://api.example.com';

      final result = normalizeProductImageUrl(
        imageUrl: imageUrl,
        baseUrl: baseUrl,
        proxyUploadsOnWeb: false,
      );

      expect(
        result,
        'https://api.example.com/uploads/products/demo-image.jpg?v=123',
      );
    });

    test('keeps same-host absolute upload URLs direct', () {
      const imageUrl =
          'https://api.example.com/uploads/products/demo-image.jpg?v=123';
      const baseUrl = 'https://api.example.com';

      final result = normalizeProductImageUrl(
        imageUrl: imageUrl,
        baseUrl: baseUrl,
        proxyUploadsOnWeb: false,
      );

      expect(result, imageUrl);
    });

    test('joins relative upload paths with the API base URL', () {
      final result = normalizeProductImageUrl(
        imageUrl: 'uploads/products/demo-image.jpg',
        baseUrl: 'https://api.example.com/',
      );

      expect(result, 'https://api.example.com/uploads/products/demo-image.jpg');
    });
  });
}
