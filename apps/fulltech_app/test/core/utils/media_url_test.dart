import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/utils/media_url.dart';

void main() {
  group('rewriteProfileMediaUrl', () {
    test('normalizes legacy media photo keys without uploads prefix', () {
      final url = rewriteProfileMediaUrl(
        'https://api.example.com/media/photo?key=companies/acme/users/profile/user-1/2026/08/avatar.jpg',
      );

      expect(
        url,
        'https://api.example.com/media/photo?key=uploads%2Fcompanies%2Facme%2Fusers%2Fprofile%2Fuser-1%2F2026%2F08%2Favatar.jpg',
      );
    });

    test('rewrites local uploads profile urls to public profile endpoint', () {
      final url = rewriteProfileMediaUrl(
        'https://api.example.com/uploads/companies/acme/users/profile/user-1/2026/08/avatar.jpg',
      );

      expect(
        url,
        'https://api.example.com/media/photo?key=uploads%2Fcompanies%2Facme%2Fusers%2Fprofile%2Fuser-1%2F2026%2F08%2Favatar.jpg',
      );
    });

    test('keeps non profile urls unchanged', () {
      const url =
          'https://api.example.com/uploads/companies/acme/users/license/user-1/file.jpg';

      expect(rewriteProfileMediaUrl(url), url);
    });
  });
}
