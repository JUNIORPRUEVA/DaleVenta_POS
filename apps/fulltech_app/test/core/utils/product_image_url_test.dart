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

    test('keeps R2 object keys as upload URLs when web proxy is requested', () {
      final result = normalizeProductImageUrl(
        imageUrl: 'uploads/companies/company-1/products/images/demo.jpg',
        baseUrl: 'https://api.example.com/',
        proxyUploadsOnWeb: true,
      );

      expect(
        result,
        'https://api.example.com/uploads/companies/company-1/products/images/demo.jpg',
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

  group('buildProductThumbnailUrl', () {
    test('adds bounded thumbnail dimensions to media object URLs', () {
      final result = buildProductThumbnailUrl(
        imageUrl:
            'https://api.example.com/media/object?key=uploads%2Fcompanies%2Fcompany-1%2Fproducts%2Fimages%2Fdemo.jpg&v=123',
        width: 320,
        height: 280,
      );

      final uri = Uri.parse(result);

      expect(uri.path, '/media/object');
      expect(uri.queryParameters['key'],
          'uploads/companies/company-1/products/images/demo.jpg');
      expect(uri.queryParameters['v'], '123');
      expect(uri.queryParameters['w'], '320');
      expect(uri.queryParameters['h'], '280');
    });

    test('clamps oversized thumbnail dimensions for product media URLs', () {
      final result = buildProductThumbnailUrl(
        imageUrl: 'https://api.example.com/media/products/product-1?v=123',
        width: 2000,
        height: 4,
      );

      final uri = Uri.parse(result);

      expect(uri.path, '/media/products/product-1');
      expect(uri.queryParameters['v'], '123');
      expect(uri.queryParameters['w'], '512');
      expect(uri.queryParameters['h'], '48');
    });

    test('adds thumbnail dimensions to proxied PWA product media URLs', () {
      final result = buildProductThumbnailUrl(
        imageUrl: 'https://pwa.example.com/api/media/products/product-1?v=123',
        width: 320,
        height: 320,
      );

      final uri = Uri.parse(result);

      expect(uri.path, '/api/media/products/product-1');
      expect(uri.queryParameters['v'], '123');
      expect(uri.queryParameters['w'], '320');
      expect(uri.queryParameters['h'], '320');
    });

    test('does not rewrite external product image URLs', () {
      const imageUrl =
          'https://legacy.example.com/uploads/products/demo-image.jpg?v=123';

      final result = buildProductThumbnailUrl(
        imageUrl: imageUrl,
        width: 320,
        height: 320,
      );

      expect(result, imageUrl);
    });
  });

  group('buildPublicProductMediaUrl', () {
    test('builds public product media URLs from product id', () {
      final result = buildPublicProductMediaUrl(
        productId: 'product 1',
        baseUrl: 'https://api.example.com/',
      );

      expect(result, 'https://api.example.com/media/products/product%201');
    });

    test('returns empty URL when product id is missing', () {
      final result = buildPublicProductMediaUrl(
        productId: ' ',
        baseUrl: 'https://api.example.com/',
      );

      expect(result, isEmpty);
    });
  });
}
