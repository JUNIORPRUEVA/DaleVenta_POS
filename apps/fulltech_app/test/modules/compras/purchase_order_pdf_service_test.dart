import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/modules/compras/purchase_models.dart';
import 'package:daleventa_pos/modules/compras/utils/purchase_order_pdf_service.dart';

void main() {
  group('PurchaseOrder status label', () {
    test('maps every real status to a professional Spanish label', () {
      expect(purchaseOrderStatusLabel('DRAFT'), 'Borrador');
      expect(purchaseOrderStatusLabel('PENDING_APPROVAL'), 'Pendiente de aprobación');
      expect(purchaseOrderStatusLabel('APPROVED'), 'Aprobada');
      expect(purchaseOrderStatusLabel('SENT'), 'Enviada');
      expect(purchaseOrderStatusLabel('PARTIALLY_RECEIVED'), 'Recibida parcial');
      expect(purchaseOrderStatusLabel('RECEIVED'), 'Recibida');
      expect(purchaseOrderStatusLabel('CANCELLED'), 'Cancelada');
    });

    test('never leaks a technical status like DRAFT or APPROVED', () {
      for (final status in const [
        'DRAFT',
        'PENDING_APPROVAL',
        'APPROVED',
        'SENT',
        'PARTIALLY_RECEIVED',
        'RECEIVED',
        'CANCELLED',
      ]) {
        final label = purchaseOrderStatusLabel(status);
        expect(label, isNot(contains('DRAFT')));
        expect(label, isNot(contains('APPROVED')));
        expect(label, isNot(contains('PENDING')));
        expect(label, isNot(contains('_RECEIVED')));
        expect(label, isNot(contains('_')), reason: status);
      }
    });
  });

  group('PurchaseOrder product code display', () {
    test('keeps a real SKU as configured', () {
      expect(purchaseOrderDisplayProductCode('SKU-100'), 'SKU-100');
      expect(purchaseOrderDisplayProductCode(''), '-');
      expect(purchaseOrderDisplayProductCode(null), '-');
    });

    test('truncates a long UUID to 8 chars without breaking the layout', () {
      const uuid = 'b3e5350c-b3f6-4591-a507-afaa800fc07b';
      final token = purchaseOrderDisplayProductCode(uuid);
      expect(token, 'B3E5350C');
      expect(token.length, lessThanOrEqualTo(8));
      expect(token, isNot(contains('-')));
    });
  });

  group('PurchaseOrder PDF generation', () {
    test('template keeps the unified professional language in source', () {
      final source = File(
        'lib/modules/compras/utils/purchase_order_pdf_service.dart',
      ).readAsStringSync();

      expect(source, contains('ORDEN DE COMPRA'));
      expect(source, contains('DATOS DEL SUPLIDOR'));
      expect(source, contains('Sin suplidor'));
      expect(source, contains('pdfResolveCompanyLogo'));
      expect(source, contains('pdfContinuationHeader'));
      expect(source, contains('if (pageNumber > 1)'));
      expect(source, contains('purchaseOrderDisplayProductCode'));
      expect(source, contains('PdfKitFormats.money()'));
    });

    test('draft with 4 products generates a valid single-page PDF', () async {
      final bytes = await buildPurchaseOrderPdf(
        order: _order(4, status: 'DRAFT', orderNumber: 'BORRADOR'),
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(_countPdfPages(bytes), 1);
    });

    test('approved order with supplier generates a valid PDF', () async {
      final bytes = await buildPurchaseOrderPdf(
        order: _order(4, status: 'APPROVED', orderNumber: 'OC-000001'),
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(_countPdfPages(bytes), 1);
    });

    test('many products generate continuation pages without failure', () async {
      final bytes = await buildPurchaseOrderPdf(
        order: _order(80, status: 'APPROVED', orderNumber: 'OC-000002'),
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(_countPdfPages(bytes), greaterThanOrEqualTo(2));
    });

    test('generates without company/logo (fallback initials path)', () async {
      final bytes = await buildPurchaseOrderPdf(
        order: _order(2, status: 'DRAFT', orderNumber: 'BORRADOR'),
        company: null,
      );

      expect(bytes.length, greaterThan(1000));
    });

    test('generates with a configured base64 logo (real logo path)', () async {
      final bytes = await buildPurchaseOrderPdf(
        order: _order(2, status: 'APPROVED', orderNumber: 'OC-000003'),
        company: _company(logo: _tinyPngBase64),
      );

      expect(bytes.length, greaterThan(1000));
    });
  });
}

CompanySettings _company({String? logo}) {
  return CompanySettings.empty().copyWith(
    companyName: 'FULLTECH, SRL',
    rnc: '133080206',
    address: 'Santo Domingo, República Dominicana',
    phone: '809-000-0000',
    logoBase64: logo,
  );
}

PurchaseOrderModel _order(
  int itemCount, {
  required String status,
  required String orderNumber,
}) {
  return PurchaseOrderModel(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    orderNumber: orderNumber,
    supplier: SupplierModel(
      id: 'supplier-1',
      commercialName: 'CANATECH SRL',
      taxId: '130123456',
      contactName: 'Ana Pérez',
      phone: '809-111-2222',
      whatsapp: '809-111-2222',
      email: 'ventas@canatech.do',
      address: 'Av. Churchill, Santo Domingo',
      paymentTerms: 'Contado',
    ),
    status: status,
    orderDate: DateTime(2026, 8, 22),
    expectedDeliveryDate: DateTime(2026, 8, 29),
    subtotal: 6420,
    discount: 120,
    shippingCost: 300,
    additionalCost: 0,
    tax: 1080,
    total: 7680,
    notes: 'Entregar en horario laboral.',
    supplierInstructions: 'Verificar stock al recibir.',
    createdByName: 'Juan Díaz',
    items: [
      for (var index = 0; index < itemCount; index++)
        PurchaseOrderItemModel(
          id: 'item-$index',
          productName: 'Producto de prueba ${index + 1}',
          productCode: 'b3e5350c-b3f6-4591-a507-afaa800fc${index.toString().padLeft(3, '0')}',
          quantity: 2,
          receivedQuantity: 0,
          pendingQuantity: 2,
          unitCost: 1000,
          subtotal: 2000,
        ),
    ],
  );
}

int _countPdfPages(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page\b').allMatches(text).length;
}

const String _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
