import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/company/company_settings_model.dart';
import '../../modules/ventas/sales_models.dart';

class InvoiceLetterPdf {
  static Future<Uint8List> generate({
    required SaleModel sale,
    required List<SaleItemModel> items,
    required CompanySettings business,
    required int brandColorArgb,
    String? cashierName,
    String? warrantyPolicy,
    String? footerMessage,
  }) async {
    final doc = pw.Document(title: 'Factura ${_number(sale.id)}');
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
    final date = DateFormat('dd/MM/yyyy HH:mm');
    final color = PdfColor.fromInt(brandColorArgb);
    final subtotal = items.fold(0.0, (sum, item) => sum + item.subtotalSold);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      business.companyName.trim().isEmpty
                          ? 'FULLTECH POS'
                          : business.companyName.trim(),
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (business.rnc.trim().isNotEmpty)
                      pw.Text('RNC: ${business.rnc}'),
                    if (business.phone.trim().isNotEmpty)
                      pw.Text('Tel: ${business.phone}'),
                    if (business.address.trim().isNotEmpty)
                      pw.Text(business.address),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'FACTURA',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text('No. ${_number(sale.id)}'),
                  pw.Text(date.format(sale.saleDate ?? DateTime.now())),
                  if ((cashierName ?? sale.userName ?? '').trim().isNotEmpty)
                    pw.Text('Cajero: ${(cashierName ?? sale.userName)!}'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Text(
              'Cliente: ${sale.customerName ?? 'Consumidor Final'}',
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerDecoration: pw.BoxDecoration(color: color),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            cellAlignment: pw.Alignment.centerLeft,
            headers: const ['Producto', 'Cant.', 'Precio', 'Total'],
            data: items
                .map(
                  (item) => [
                    item.productNameSnapshot,
                    _qty(item.qty),
                    money.format(item.priceSoldUnit),
                    money.format(item.subtotalSold),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 18),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 260,
              child: pw.Column(
                children: [
                  _total('Subtotal', money.format(subtotal)),
                  pw.Divider(),
                  _total(
                    'Total factura',
                    money.format(sale.totalSold),
                    strong: true,
                  ),
                ],
              ),
            ),
          ),
          if ((warrantyPolicy ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Text(
              'Garantia',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(warrantyPolicy!.trim()),
          ],
          if ((footerMessage ?? '').trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            pw.Center(child: pw.Text(footerMessage!.trim())),
          ],
        ],
      ),
    );
    return doc.save();
  }

  static pw.Widget _total(String label, String value, {bool strong = false}) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    );
  }

  static String _qty(double value) {
    if (value == value.truncateToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static String _number(String id) {
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) return digits.substring(digits.length - 8);
    final compact = id.replaceAll('-', '');
    if (compact.length >= 8) return compact.substring(0, 8).toUpperCase();
    return compact.toUpperCase();
  }
}
