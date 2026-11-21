import 'package:daleventa_pos/core/utils/customer_visible_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'removes opaque IDs from display text without changing commercial references',
    () {
      expect(
        customerVisibleText(
          'Producto 12345678-1234-4234-8234-123456789abc archivado',
        ),
        'Producto archivado',
      );
      expect(
        customerVisibleText(
          'fasdflasdfjasdklfhjsdlfjslfjasdl',
          fallback: 'Producto',
        ),
        'Producto',
      );
      expect(
        customerVisibleText('AUD-001 · 8095550100 · 7501234567890'),
        'AUD-001 · 8095550100 · 7501234567890',
      );
      expect(
        customerVisibleText('Auriculares profesionales'),
        'Auriculares profesionales',
      );
      expect(
        customerVisibleText('507f1f77bcf86cd799439011', fallback: 'Sin código'),
        'Sin código',
      );
    },
  );
}
