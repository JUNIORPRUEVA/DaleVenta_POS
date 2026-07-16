import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/payable_models.dart';

class PayableReceiptPdfData {
  final String companyName;
  final String serviceTitle;
  final String providerName;
  final PayableProviderKind providerKind;
  final DateTime periodFrom;
  final DateTime periodTo;
  final List<PayablePayment> payments;

  const PayableReceiptPdfData({
    required this.companyName,
    required this.serviceTitle,
    required this.providerName,
    required this.providerKind,
    required this.periodFrom,
    required this.periodTo,
    required this.payments,
  });
}

Future<Uint8List> buildPayableReceiptPdf({
  required PayableReceiptPdfData data,
}) async {
  final pdf = pw.Document();
  final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
  final dateFmt = DateFormat('dd/MM/yyyy');
  final nowFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');

  final sorted = [...data.payments]
    ..sort((a, b) => a.paidAt.compareTo(b.paidAt));
  final total = sorted.fold<double>(0, (sum, item) => sum + item.amount);

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          color: PdfColors.blue900,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'COMPROBANTE DE PAGO',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                data.companyName,
                style: const pw.TextStyle(color: PdfColors.white),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            color: PdfColors.grey100,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Servicio: ${data.serviceTitle}'),
              pw.Text(
                'Beneficiario: ${data.providerName} (${data.providerKind.label})',
              ),
              pw.Text(
                'Período: ${dateFmt.format(data.periodFrom)} - ${dateFmt.format(data.periodTo)}',
              ),
              pw.Text('Emitido: ${nowFmt.format(DateTime.now())}'),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headers: const ['Fecha de pago', 'Monto', 'Nota'],
          data: sorted
              .map(
                (item) => [
                  dateFmt.format(item.paidAt),
                  money.format(item.amount),
                  item.note ?? '-',
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL PAGADO EN EL PERÍODO',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                money.format(total),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  return pdf.save();
}

Future<void> sharePayableReceiptPdf({
  required Uint8List bytes,
  required String filename,
}) async {
  await Printing.sharePdf(bytes: bytes, filename: filename);
}
