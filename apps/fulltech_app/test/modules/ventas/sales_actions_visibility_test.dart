import 'dart:io';

import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato de acciones de la UI de facturación tras simplificar la UX:
/// la única acción de reversión visible es **Devolver**. La cancelación dejó de
/// exponerse al usuario aunque el backend y el endpoint sigan existiendo.
///
/// La visibilidad de "Devolver" en las pantallas se decide con `sale.canReturn`
/// (filas del historial, detalle de factura, tabla y tarjetas de Mis Ventas).
bool showsReturnAction(SaleModel sale) => sale.canReturn;

SaleModel saleFrom(Map<String, dynamic> overrides) {
  return SaleModel.fromJson({
    'id': 'sale-1',
    'userId': 'user-1',
    'userName': 'Cajero',
    'saleDate': '2026-09-10T12:00:00.000Z',
    'totalSold': 200,
    'totalCost': 0,
    'totalProfit': 200,
    'commissionAmount': 0,
    'paymentMethod': 'cash',
    'paymentCashAmount': 200,
    'paymentTransferAmount': 0,
    'creditAmount': 0,
    'creditPaidAmount': 0,
    'creditBalance': 0,
    'creditStatus': 'none',
    'isDeleted': false,
    'kind': 'invoice',
    ...overrides,
  });
}

void main() {
  group('acciones visibles por estado de la venta', () {
    test('ACTIVA permite devolver y ya no expone cancelar', () {
      final sale = saleFrom({
        'returnStatus': 'ACTIVE',
        'returnedAmount': 0,
        'returnableAmount': 200,
        'canReturn': true,
      });

      expect(showsReturnAction(sale), isTrue);
      expect(sale.isPartiallyReturned, isFalse);
      expect(sale.isReturned, isFalse);
      expect(sale.isCancelled, isFalse);
    });

    test('DEVUELTA PARCIALMENTE permite devolver el remanente', () {
      final sale = saleFrom({
        'returnStatus': 'PARTIALLY_RETURNED',
        'returnedAmount': 200,
        'returnableAmount': 400,
        'canReturn': true,
        'totalSold': 600,
      });

      expect(showsReturnAction(sale), isTrue);
      expect(sale.isPartiallyReturned, isTrue);
      expect(sale.netActiveAmount, 400);
    });

    test('DEVUELTA no ofrece una segunda devolución', () {
      final sale = saleFrom({
        'returnStatus': 'RETURNED',
        'returnedAmount': 200,
        'returnableAmount': 0,
        'canReturn': false,
      });

      expect(showsReturnAction(sale), isFalse);
      expect(sale.isReturned, isTrue);
    });

    test('CANCELADA histórica no ofrece ninguna acción', () {
      final sale = saleFrom({
        'returnStatus': 'CANCELLED',
        'isDeleted': true,
        'canReturn': false,
        'returnableAmount': 0,
      });

      expect(showsReturnAction(sale), isFalse);
      expect(sale.isCancelled, isTrue);
      expect(sale.netActiveAmount, 0);
    });

    test('documento de devolución (refund) no ofrece acciones de venta', () {
      final refund = saleFrom({
        'kind': 'refund',
        'returnStatus': 'RETURNED',
        'canReturn': false,
        'totalSold': -200,
        'returnableAmount': 0,
      });

      expect(showsReturnAction(refund), isFalse);
      expect(refund.isRefundDocument, isTrue);
      expect(refund.isCommerciallyActive, isFalse);
    });

    test('una venta borrada sin returnStatus se trata como CANCELADA', () {
      final sale = saleFrom({'isDeleted': true});

      expect(sale.returnStatus, 'CANCELLED');
      expect(showsReturnAction(sale), isFalse);
    });
  });

  group('guardas de origen: la acción Cancelar ya no existe en la UI', () {
    final screens = <String, String>{
      'tpv_sales_history_screen.dart':
          'lib/modules/ventas/tpv_sales_history_screen.dart',
      'mis_ventas_screen.dart': 'lib/modules/ventas/mis_ventas_screen.dart',
    };

    final forbidden = <String>[
      'Cancelar venta',
      '_cancelSale',
      'onCancel',
      'canCancel',
      'deleteSale',
      'AppPermission.cancelSales',
    ];

    screens.forEach((label, path) {
      test('$label no contiene superficies de cancelación', () {
        final source = File(path).readAsStringSync();
        for (final token in forbidden) {
          expect(
            source.contains(token),
            isFalse,
            reason: '$label todavía contiene "$token"',
          );
        }
      });

      test('$label conserva la acción Devolver', () {
        final source = File(path).readAsStringSync();
        expect(source.contains('Devolver'), isTrue);
        expect(source.contains('assignment_return_outlined'), isTrue);
        expect(
          source.contains('canReturn'),
          isTrue,
          reason: '$label debe seguir decidiendo Devolver con canReturn',
        );
      });
    });

    test('mensaje de devolución es genérico y no promete stock', () {
      final tpv = File(
        'lib/modules/ventas/tpv_sales_history_screen.dart',
      ).readAsStringSync();
      final misVentas = File(
        'lib/modules/ventas/mis_ventas_screen.dart',
      ).readAsStringSync();

      for (final source in [tpv, misVentas]) {
        expect(
          source.contains(
            'revertirá automáticamente los movimientos correspondientes',
          ),
          isTrue,
        );
        expect(source.contains('restaurará el stock'), isFalse);
      }
      expect(tpv.contains('Devolver venta'), isTrue);
    });

    test('el backend mantiene el endpoint y el permiso de cancelación', () {
      final controller = File(
        '../api/src/sales/sales.controller.ts',
      ).readAsStringSync();
      final service = File('../api/src/sales/sales.service.ts').readAsStringSync();

      expect(controller.contains('@Permissions("cancelSales")'), isTrue);
      expect(controller.contains('@Delete(":id")'), isTrue);
      expect(service.contains('cancelSaleInventory'), isTrue);
    });
  });
}
