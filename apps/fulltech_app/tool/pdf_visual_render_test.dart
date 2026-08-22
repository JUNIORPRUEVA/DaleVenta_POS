// Visual verification harness for the unified PDF design.
//
// Generates real Purchase Order and Cotización PDFs and saves them under
// `tool/pdf_renders/` for manual inspection (open the PDFs in a viewer).
//
// Run with: flutter test tool/pdf_visual_render_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/modules/compras/purchase_models.dart';
import 'package:daleventa_pos/modules/compras/utils/purchase_order_pdf_service.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/utils/cotizacion_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  test('generate purchase order and cotización PDFs for inspection', () async {
    final outDir = Directory('tool/pdf_renders');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    // Real bundled logo (no base64) → asset fallback path used by Cotización.
    final company = _company(logo: null);

    // Sample purchase order (approved, supplier, tax, totals).
    final purchaseBytes = await buildPurchaseOrderPdf(
      order: _purchaseOrder(
        itemCount: 4,
        status: 'APPROVED',
        orderNumber: 'OC-000001',
        withSupplier: true,
      ),
      company: company,
    );
    _write(outDir, 'purchase_approved_4.pdf', purchaseBytes);

    // Draft purchase order without supplier → 'BORRADOR' + 'Sin suplidor'.
    final draftBytes = await buildPurchaseOrderPdf(
      order: _purchaseOrder(
        itemCount: 4,
        status: 'DRAFT',
        orderNumber: 'BORRADOR',
        withSupplier: false,
      ),
      company: company,
    );
    _write(outDir, 'purchase_draft_nosupplier.pdf', draftBytes);

    // Multipage purchase order (continuation header).
    final multiBytes = await buildPurchaseOrderPdf(
      order: _purchaseOrder(
        itemCount: 60,
        status: 'SENT',
        orderNumber: 'OC-000002',
        withSupplier: true,
      ),
      company: company,
    );
    _write(outDir, 'purchase_multipage.pdf', multiBytes);

    // Cotización for side-by-side comparison.
    final quoteBytes = await buildCotizacionPdf(
      cotizacion: _quote(4),
      company: company,
    );
    _write(outDir, 'cotizacion_4.pdf', quoteBytes);

    // Base64 configured logo path (solid blue square proves real-logo path).
    final logoCompany = _company(logo: _generatedLogoBase64());
    final purchaseWithLogoBytes = await buildPurchaseOrderPdf(
      order: _purchaseOrder(
        itemCount: 4,
        status: 'APPROVED',
        orderNumber: 'OC-000003',
        withSupplier: true,
      ),
      company: logoCompany,
    );
    _write(outDir, 'purchase_base64_logo.pdf', purchaseWithLogoBytes);

    // Report generated files.
    final files = outDir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .toList()
      ..sort();
    // ignore: avoid_print
    print('RENDERED ${files.length} files:');
    for (final f in files) {
      // ignore: avoid_print
      print('  $f');
    }
  });
}

void _write(Directory outDir, String name, Uint8List bytes) {
  File('${outDir.path}/$name').writeAsBytesSync(bytes);
}

CompanySettings _company({String? logo}) {
  return CompanySettings.empty().copyWith(
    companyName: 'FULLTECH, SRL',
    rnc: '133080206',
    address: 'Av. 27 de Febrero #123, Santo Domingo, República Dominicana',
    phone: '809-555-1234',
    websiteUrl: 'www.fulltech.do',
    logoBase64: logo,
  );
}

PurchaseOrderModel _purchaseOrder({
  required int itemCount,
  required String status,
  required String orderNumber,
  required bool withSupplier,
}) {
  return PurchaseOrderModel(
    id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    orderNumber: orderNumber,
    supplier: withSupplier
        ? SupplierModel(
            id: 'supplier-1',
            commercialName: 'CANATECH SRL',
            taxId: '130123456',
            contactName: 'Ana Pérez',
            phone: '809-111-2222',
            whatsapp: '809-111-2222',
            email: 'ventas@canatech.do',
            address: 'Av. Churchill, Santo Domingo',
            paymentTerms: 'Contado 30 días',
          )
        : null,
    status: status,
    orderDate: DateTime(2026, 8, 22),
    expectedDeliveryDate: DateTime(2026, 8, 29),
    subtotal: 6420,
    discount: 120,
    shippingCost: 300,
    additionalCost: 150,
    tax: 1080,
    total: 7830,
    notes: 'Entregar en horario laboral. Confirmar disponibilidad antes de despachar.',
    supplierInstructions: 'Verificar stock al recibir y adjuntar factura de compra.',
    createdByName: 'Juan Díaz',
    items: [
      for (var index = 0; index < itemCount; index++)
        PurchaseOrderItemModel(
          id: 'item-$index',
          productName: 'Producto de prueba largo ${index + 1} para validar el ancho de la columna descripción',
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

CotizacionModel _quote(int count) {
  final items = [
    for (var index = 0; index < count; index++)
      CotizacionItem(
        productId: '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
        nombre: 'Producto de prueba largo ${index + 1} para validar el ancho de la columna descripción',
        imageUrl: null,
        originalUnitPrice: 1000,
        unitPrice: 1000,
        qty: 1,
        taxTreatment: 'TAXABLE',
        taxRate: 0.18,
        taxPriceMode: 'TAX_ADDED',
        grossAmount: 1000,
        taxableBase: 1000,
        taxAmount: 180,
        lineTotalSnapshot: 1180,
      ),
  ];
  return CotizacionModel(
    id: '22222222-2222-4222-8222-222222222222',
    createdAt: DateTime(2026, 8, 20, 18, 47),
    customerId: null,
    customerName: 'CANATECH SRL',
    customerPhone: '809-222-2222',
    note: 'Gracias por preferirnos.',
    includeItbis: true,
    itbisRate: 0.18,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_ADDED',
    taxableBase: 4000,
    taxAmount: 720,
    exemptAmount: 0,
    fiscalDiscountAmount: 0,
    totalSnapshot: 4720,
    items: items,
  );
}

String _generatedLogoBase64() {
  final image = img.Image(width: 120, height: 120);
  img.fill(image, color: img.ColorRgb8(25, 87, 230));
  img.fillRect(
    image,
    x1: 20,
    y1: 20,
    x2: 100,
    y2: 100,
    color: img.ColorRgb8(255, 255, 255),
  );
  return base64Encode(Uint8List.fromList(img.encodePng(image)));
}
