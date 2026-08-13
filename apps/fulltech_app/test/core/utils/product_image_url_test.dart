import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/utils/product_image_url.dart';

void main() {
  group('normalizeProductImageUrl', () {
    test('keeps external upload URLs on their original host', () {
      const imageUrl =
          'https://legacy.example.com/uploads/products/demo-image.jpg?v=123';
      const baseUrl = 'https://api.example.com';

      final result = normalizeProductImageUrl(
        imageUrl: imageUrl,
        baseUrl: baseUrl,
        proxyUploadsOnWeb: false,
      );

      expect(result, imageUrl);
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

    test('converts R2 object keys to media object URLs', () {
      final result = normalizeProductImageUrl(
        imageUrl: 'uploads/companies/company-1/products/images/demo.jpg',
        baseUrl: 'https://api.example.com/',
      );

      expect(
        result,
        'https://api.example.com/media/object?key=uploads%2Fcompanies%2Fcompany-1%2Fproducts%2Fimages%2Fdemo.jpg',
      );
    });

    test('keeps relative media object URLs on the API host', () {
      final result = normalizeProductImageUrl(
        imageUrl:
            '/media/object?key=uploads%2Fcompanies%2Fcompany-1%2Fproducts%2Fimages%2Fdemo.jpg',
        baseUrl: 'https://api.example.com/',
      );

      expect(
        result,
        'https://api.example.com/media/object?key=uploads%2Fcompanies%2Fcompany-1%2Fproducts%2Fimages%2Fdemo.jpg',
      );
    });
  });
}
