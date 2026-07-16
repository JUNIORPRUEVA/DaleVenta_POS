import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _companyName = 'FULLTECH, SRL';
const _companyRnc = '133080209';

class DepositOrderPdfData {
  final DateTime generatedAt;
  final DateTime windowFrom;
  final DateTime windowTo;
  final String bankName;
  final String? createdByName;
  final String? collaboratorName;
  final String? note;
  final double reserveInCash;
  final double totalAvailableCash;
  final double depositTotal;
  final Map<String, int> closesCountByType;
  final Map<String, double> depositByType;
  final Map<String, String> accountByType;

  const DepositOrderPdfData({
    required this.generatedAt,
    required this.windowFrom,
    required this.windowTo,
    required this.bankName,
    this.createdByName,
    this.collaboratorName,
    this.note,
    required this.reserveInCash,
    required this.totalAvailableCash,
    required this.depositTotal,
    required this.closesCountByType,
    required this.depositByType,
    required this.accountByType,
  });
}

Future<Uint8List> buildDepositOrderPdf({
  required DepositOrderPdfData data,
}) async {
  final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
  final dateTimeFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final detailRows = _buildRows(data);

  final doc = pw.Document(title: 'Deposíto al banco', author: 'FULLTECH, SRL');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(18),
          decoration: const pw.BoxDecoration(
            color: PdfColors.blue900,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      _companyName,
                      style: pw.TextStyle(
                        fontSize: 21,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'RNC: $_companyRnc',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'DEPOSITO AL BANCO',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Container(
                width: 180,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(10),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _metaLine(
                      'Fecha',
                      dateTimeFmt.format(data.generatedAt),
                      compact: true,
                    ),
                    _metaLine('Banco', data.bankName, compact: true),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(top: 14),
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
            border: pw.Border.all(color: PdfColors.blue100),
            color: PdfColors.blue50,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Resumen del depósito',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                  color: PdfColors.blue900,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Depósito al banco ${data.bankName} por un monto total de ${money.format(data.depositTotal)}.',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 12),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _metaLine('Banco', data.bankName),
                        _metaLine(
                          'Monto a depositar',
                          money.format(data.depositTotal),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 18),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if ((data.createdByName ?? '').trim().isNotEmpty)
                          _metaLine('Ordenado por', data.createdByName!.trim()),
                        if ((data.collaboratorName ?? '').trim().isNotEmpty)
                          _metaLine(
                            'Ejecutado por',
                            data.collaboratorName!.trim(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((data.note ?? '').trim().isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(8),
                    ),
                    border: pw.Border.all(color: PdfColors.blue100),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Observación',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 10,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        data.note!.trim(),
                        style: const pw.TextStyle(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Cuentas de depósito',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.blue100, width: 0.8),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.2),
            1: const pw.FlexColumnWidth(3.3),
            2: const pw.FlexColumnWidth(1.5),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blue900),
              children: [
                _tableHeader('Banco'),
                _tableHeader('Cuenta destino'),
                _tableHeader('Monto RD\$'),
              ],
            ),
            ...detailRows.map(
              (row) => pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.white),
                children: [
                  _tableCell(data.bankName),
                  _tableCell(row.account),
                  _tableCell(
                    money.format(row.amount),
                    align: pw.TextAlign.right,
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(10),
                  ),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Responsables',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10.5,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Bullet(
                      text:
                          'Orden de depósito: ${_safeValue(data.createdByName, fallback: 'No indicado')}',
                    ),
                    pw.Bullet(
                      text:
                          'Ejecutado por: ${_safeValue(data.collaboratorName, fallback: 'No indicado')}',
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 14),
            pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
                border: pw.Border.all(color: PdfColors.blue200),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'Monto total a depositar',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10.5,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    money.format(data.depositTotal),
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 22),
        if ((data.note ?? '').trim().isNotEmpty) ...[
          pw.Text(
            'Comentario',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Text(
              data.note!.trim(),
              style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 2),
            ),
          ),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _metaLine(String label, String value, {bool compact = false}) {
  return pw.Padding(
    padding: pw.EdgeInsets.only(bottom: compact ? 4 : 6),
    child: pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          color: PdfColors.black,
        ),
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(text: value),
        ],
      ),
    ),
  );
}

pw.Widget _tableHeader(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(8),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontWeight: pw.FontWeight.bold,
        fontSize: 10,
      ),
      textAlign: pw.TextAlign.center,
    ),
  );
}

pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(8),
    child: pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 10),
      textAlign: align,
    ),
  );
}

List<_DepositRow> _buildRows(DepositOrderPdfData data) {
  return data.closesCountByType.keys
      .map(
        (type) => _DepositRow(
          type: _typeLabel(type),
          closes: data.closesCountByType[type] ?? 0,
          account: data.accountByType[type] ?? '-',
          amount: data.depositByType[type] ?? 0,
        ),
      )
      .toList();
}

String _safeValue(String? value, {required String fallback}) {
  final cleaned = (value ?? '').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

class _DepositRow {
  final String type;
  final int closes;
  final String account;
  final double amount;

  const _DepositRow({
    required this.type,
    required this.closes,
    required this.account,
    required this.amount,
  });
}

String _typeLabel(String raw) {
  switch (raw.trim().toUpperCase()) {
    case 'CAPSULAS':
      return 'Pastilla';
    case 'POS':
      return 'Software';
    case 'TIENDA':
      return 'Tienda';
    case 'GENERAL':
      return 'General';
    default:
      return raw;
  }
}
