import 'package:flutter_test/flutter_test.dart';
import 'package:fulltech_app/core/utils/product_image_url.dart';

void main() {
  group('normalizeProductImageUrl', () {
    test('proxies external absolute upload URLs even outside web', () {
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
        'https://api.example.com/products/image-proxy?url=https%3A%2F%2Flegacy.example.com%2Fuploads%2Fproducts%2Fdemo-image.jpg%3Fv%3D123',
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
