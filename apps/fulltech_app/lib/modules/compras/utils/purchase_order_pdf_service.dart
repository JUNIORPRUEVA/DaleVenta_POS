import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/company/company_settings_model.dart';
import '../../../core/utils/money_formatters.dart';
import '../purchase_models.dart';

Future<Uint8List> buildPurchaseOrderPdf({
  required PurchaseOrderModel order,
  CompanySettings? company,
}) async {
  final doc = pw.Document(
    title: 'ORDEN DE COMPRA ${order.orderNumber}',
    author: 'FullTech',
  );
  final dateFmt = DateFormat('dd/MM/yyyy');
  String money(double value) => formatRdCurrencyAccounting(value);
  final companyName = company?.companyName.trim().isNotEmpty == true
      ? company!.companyName
      : 'FULLTECH SRL';

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 54,
                height: 54,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#1A56DB'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  'FT',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      companyName,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if ((company?.rnc ?? '').trim().isNotEmpty)
                      pw.Text('RNC: ${company!.rnc}'),
                    if ((company?.address ?? '').trim().isNotEmpty)
                      pw.Text(company!.address),
                    pw.Text(
                      [
                        company?.phone,
                        company?.websiteUrl,
                      ].where((e) => (e ?? '').trim().isNotEmpty).join(' · '),
                    ),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'ORDEN DE COMPRA',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 18,
                      color: PdfColor.fromHex('#1A56DB'),
                    ),
                  ),
                  pw.Text(
                    order.orderNumber,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'Fecha: ${order.orderDate == null ? '-' : dateFmt.format(order.orderDate!)}',
                  ),
                  pw.Text('Estado: ${order.status}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(color: PdfColor.fromHex('#CBD5E1')),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Página ${context.pageNumber} de ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _infoBox('Suplidor', [
                order.supplier?.commercialName ?? 'Sin suplidor',
                if ((order.supplier?.taxId ?? '').isNotEmpty)
                  'RNC: ${order.supplier!.taxId}',
                if ((order.supplier?.contactName ?? '').isNotEmpty)
                  'Contacto: ${order.supplier!.contactName}',
                if ((order.supplier?.phone ?? '').isNotEmpty)
                  'Tel: ${order.supplier!.phone}',
                if ((order.supplier?.whatsapp ?? '').isNotEmpty)
                  'WhatsApp: ${order.supplier!.whatsapp}',
                if ((order.supplier?.address ?? '').isNotEmpty)
                  order.supplier!.address!,
              ]),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: _infoBox('Entrega e instrucciones', [
                'Entrega estimada: ${order.expectedDeliveryDate == null ? '-' : dateFmt.format(order.expectedDeliveryDate!)}',
                if ((order.supplier?.paymentTerms ?? '').isNotEmpty)
                  'Condiciones: ${order.supplier!.paymentTerms}',
                if ((order.supplierInstructions ?? '').isNotEmpty)
                  order.supplierInstructions!,
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(
            color: PdfColor.fromHex('#E2E8F0'),
            width: .6,
          ),
          headerDecoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#EFF6FF'),
          ),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 9,
          ),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellPadding: const pw.EdgeInsets.all(6),
          columnWidths: {
            0: const pw.FixedColumnWidth(58),
            1: const pw.FlexColumnWidth(2.6),
            2: const pw.FixedColumnWidth(54),
            3: const pw.FixedColumnWidth(72),
            4: const pw.FixedColumnWidth(78),
          },
          headers: const [
            'Código',
            'Descripción',
            'Cant.',
            'Costo',
            'Subtotal',
          ],
          data: [
            for (final item in order.items)
              [
                item.productCode ?? '',
                item.productName,
                item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2),
                money(item.unitCost),
                money(item.subtotal),
              ],
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 230,
            child: pw.Column(
              children: [
                _totalLine('Subtotal', money(order.subtotal)),
                _totalLine('Descuento', money(order.discount)),
                _totalLine('Transporte', money(order.shippingCost)),
                _totalLine('Costos adicionales', money(order.additionalCost)),
                _totalLine('Impuestos', money(order.tax)),
                pw.Divider(),
                _totalLine(
                  'Total de inversión',
                  money(order.total),
                  strong: true,
                ),
              ],
            ),
          ),
        ),
        if ((order.notes ?? '').isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _infoBox('Observaciones', [order.notes!]),
        ],
        pw.SizedBox(height: 28),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Responsable: ${order.createdByName ?? ''}'),
            pw.Container(
              width: 180,
              decoration: const pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey)),
              ),
              child: pw.Center(child: pw.Text('Firma')),
            ),
          ],
        ),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _infoBox(String title, List<String> lines) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1')),
    borderRadius: pw.BorderRadius.circular(6),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#1A56DB'),
        ),
      ),
      pw.SizedBox(height: 5),
      for (final line in lines.where((line) => line.trim().isNotEmpty))
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Text(line),
        ),
    ],
  ),
);

pw.Widget _totalLine(String label, String value, {bool strong = false}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: strong ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
          ),
          pw.Text(
            value,
            style: strong ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
          ),
        ],
      ),
    );
