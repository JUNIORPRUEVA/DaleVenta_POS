import 'dart:convert';
import 'dart:io';
import 'package:intl/date_symbol_data_local.dart';

import 'package:flutter_test/flutter_test.dart';
// Reutiliza la dependencia existente del visor para verificar el documento.
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/features/reports/utils/sales_report_pdf_service.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

const _kpis = SalesReportPdfKpis(
  totalSales: 549300.12,
  grossProfit: 267512.14,
  netProfit: 248157.14,
  totalExpenses: 19355,
  totalCost: 276658.15,
  salesCount: 119,
  avgTicket: 4968.95,
  grossMargin: 48.7,
  margin: 45.2,
);

SaleModel _sale(int index) => SaleModel.fromJson({
  'id': 'sale-$index',
  'customer': {
    'nombre': 'Cliente número $index - nombre extenso de comprobación',
  },
  'saleDate': '2026-11-01T12:00:00Z',
  'totalSold': 8000,
  'totalCost': 2000,
  'totalProfit': 6000,
  'returnedAmount': index == 0 ? 4000 : 0,
  'items': [],
});

Future<List<int>> _build({int count = 80, bool empty = false}) =>
    buildProfessionalSalesReportPdf(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 11, 14),
      categoryLabel: 'Todas las categorías',
      kpis: _kpis,
      company: empty
          ? null
          : CompanySettings.empty().copyWith(
              companyName: 'Empresa de prueba & Asociados',
              rnc: 'RNC-DE-PRUEBA',
              phone: '809-000-0000',
              address: 'Dirección de prueba, República Dominicana',
              openAiApiKey: 'SECRET_MUST_NOT_APPEAR',
            ),
      categories: empty
          ? []
          : const [
              SalesReportPdfCategoryRow(
                category: 'Tecnología y accesorios',
                totalSales: 8000,
                totalCost: 2000,
                totalProfit: 6000,
                totalQty: 2,
                totalQtyLabel: '2 u + 1.5 m',
                salesCount: 1,
              ),
              SalesReportPdfCategoryRow(
                category: 'Categoría con pérdida',
                totalSales: 100,
                totalCost: 350,
                totalProfit: -250,
                totalQty: 1,
                totalQtyLabel: '1 u',
                salesCount: 1,
              ),
            ],
      sales: empty ? [] : List.generate(count, _sale),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es_DO'));
  test(
    'incluye empresa, acentos, todos los registros y totales del servidor',
    () async {
      final bytes = await _build();
      final doc = PdfDocument(inputBytes: bytes);
      try {
        final text = PdfTextExtractor(
          doc,
        ).extractText().replaceAll(RegExp(r'\s+'), ' ');
        expect(doc.pages.count, greaterThan(2));
        for (final value in [
          'Empresa de prueba & Asociados',
          'RNC-DE-PRUEBA',
          'República Dominicana',
          'Reporte de ventas y rentabilidad',
          '549,300.12',
          '248,157.14',
          '119 facturas',
          '80 registros',
          'número 79',
          '2 u + 1.5 m',
        ]) {
          expect(text, contains(value), reason: value);
        }
        expect(text, isNot(contains('Reporte profesional')));
        expect(text, isNot(contains('SECRET_MUST_NOT_APPEAR')));
        expect(
          text,
          contains('4,000.00'),
        ); // Monto vigente tras devolución parcial.
        final output = Platform.environment['REPORT_PDF_PREVIEW_DIR'];
        if (output != null) {
          await Directory(output).create(recursive: true);
          await File('$output/reporte-prueba-extenso.pdf').writeAsBytes(bytes);
        }
      } finally {
        doc.dispose();
      }
    },
  );
  test(
    'sin empresa ni detalle genera un documento legible sin datos inventados',
    () async {
      final doc = PdfDocument(inputBytes: await _build(empty: true));
      try {
        final text = PdfTextExtractor(
          doc,
        ).extractText().replaceAll(RegExp(r'\s+'), ' ');
        expect(text, contains('FullPOS Cloud'));
        expect(text, contains('No hay ventas'));
        expect(text, isNot(contains('RNC:')));
      } finally {
        doc.dispose();
      }
    },
  );
  test(
    'genera la vista previa con los datos del PDF adjunto cuando se suministran',
    () async {
      final fixture = Platform.environment['REPORT_PDF_SOURCE_JSON'];
      final output = Platform.environment['REPORT_PDF_PREVIEW_DIR'];
      if (fixture == null || output == null) return;
      final source =
          jsonDecode(await File(fixture).readAsString())
              as Map<String, dynamic>;
      final bytes = await buildProfessionalSalesReportPdf(
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 11, 14),
        categoryLabel: 'Todas las categorías',
        kpis: _kpis,
        company: CompanySettings.empty().copyWith(companyName: 'FULLTECH, SRL'),
        categories: (source['categories'] as List)
            .map(
              (r) => SalesReportPdfCategoryRow(
                category: r['category'],
                totalSales: (r['sales'] as num).toDouble(),
                totalCost: (r['cost'] as num).toDouble(),
                totalProfit: (r['profit'] as num).toDouble(),
                totalQty: 0,
                totalQtyLabel: r['qty'],
                salesCount: r['count'],
              ),
            )
            .toList(),
        sales: (source['sales'] as List)
            .map((r) => SaleModel.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
      );
      await Directory(output).create(recursive: true);
      await File(
        '$output/reporte_ventas_20260101_20261114.pdf',
      ).writeAsBytes(bytes);
    },
  );
}
