/// Shared PDF visual language for FullPOS Cloud documents.
///
/// Both Cotizaciones (`cotizacion_pdf_service.dart`) and Orden de Compra
/// (`purchase_order_pdf_service.dart`) render with this exact style so every
/// document belongs to the same system, company and professional standard.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../company/company_settings_model.dart';

/// Color palette shared by all A4 PDF documents.
class PdfKitColors {
  PdfKitColors._();

  static final PdfColor pageBackground = PdfColors.white;
  static final PdfColor borderColor = PdfColor.fromHex('#D9E2EC');
  static final PdfColor panelBorder = PdfColor.fromHex('#CBD5E1');
  static final PdfColor softFill = PdfColor.fromHex('#F8FAFC');
  static final PdfColor softLine = PdfColor.fromHex('#E2E8F0');
  static final PdfColor headingBlack = PdfColor.fromHex('#0F172A');
  static final PdfColor textPrimary = PdfColor.fromHex('#172033');
  static final PdfColor textMuted = PdfColor.fromHex('#64748B');
  static final PdfColor accentBlue = PdfColor.fromHex('#1957E6');
  static final PdfColor danger = PdfColor.fromHex('#B42318');
  static final PdfColor zebraFill = PdfColor.fromHex('#FBFDFF');
}

/// Format helpers shared by PDF documents.
class PdfKitFormats {
  PdfKitFormats._();

  /// Monetary format used across documents: `RD$1,605.00`.
  static NumberFormat money() =>
      NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');

  /// Quantity format (es_DO): `1,5` / `3` / `2,25`.
  static NumberFormat qty() => NumberFormat('#,##0.##', 'es_DO');

  /// Short date used in orders: `22/08/2026`.
  static DateFormat shortDate() => DateFormat('dd/MM/yyyy');
}

String pdfClean(String? value) => (value ?? '').trim();

String pdfFallback(String? value, {required String fallback}) {
  final cleaned = pdfClean(value);
  return cleaned.isEmpty ? fallback : cleaned;
}

double pdfRoundMoney(double value) => (value * 100).round() / 100;

/// Single source of truth for the company logo used on PDF documents.
///
/// Resolution order (same as Cotizaciones):
/// 1. `company.logoBase64` (configured logo) if it decodes as an image.
/// 2. Bundled `assets/image/logo.png` fallback.
/// 3. `null` (the caller shows the initials fallback).
Future<pw.MemoryImage?> pdfResolveCompanyLogo(CompanySettings? company) async {
  final rawLogo = pdfClean(company?.logoBase64);
  if (rawLogo.isNotEmpty) {
    try {
      return pw.MemoryImage(base64Decode(rawLogo));
    } catch (_) {
      // Invalid base64 → continue to asset fallback.
    }
  }

  try {
    final asset = await rootBundle.load('assets/image/logo.png');
    return pw.MemoryImage(asset.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// Logo block: real logo image or the company initials as fallback.
pw.Widget pdfLogoBox({
  required String companyName,
  required pw.MemoryImage? logoImage,
}) {
  final initial = companyName.trim().isEmpty
      ? '?'
      : companyName.trim().substring(0, 1).toUpperCase();
  return pw.Container(
    width: 60,
    height: 60,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: PdfKitColors.softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: PdfKitColors.panelBorder, width: 0.45),
    ),
    child: logoImage != null
        ? pw.Image(logoImage, fit: pw.BoxFit.contain)
        : pw.Center(
            child: pw.Text(
              initial,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfKitColors.textPrimary,
              ),
            ),
          ),
  );
}

/// Shared rounded panel container used across documents.
pw.Widget pdfPanel({
  required pw.Widget child,
  pw.EdgeInsetsGeometry padding = const pw.EdgeInsets.all(12),
  pw.EdgeInsetsGeometry margin = pw.EdgeInsets.zero,
  PdfColor fillColor = PdfColors.white,
  bool showBorder = false,
}) {
  return pw.Container(
    margin: margin,
    padding: padding,
    decoration: pw.BoxDecoration(
      color: fillColor,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: showBorder
          ? pw.Border.all(color: PdfKitColors.panelBorder, width: 0.45)
          : null,
    ),
    child: child,
  );
}

/// Table header cell (dark background).
pw.Widget pdfHeaderCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.center,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    alignment: align == pw.TextAlign.left
        ? pw.Alignment.centerLeft
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.center,
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 7.2,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

/// Table body cell.
pw.Widget pdfBodyCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
  PdfColor? textColor,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
    alignment: align == pw.TextAlign.center
        ? pw.Alignment.center
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.centerLeft,
    child: pw.Text(
      text,
      textAlign: align,
      style: pw.TextStyle(
        fontSize: 7.6,
        color: textColor ?? PdfKitColors.textPrimary,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

/// Bold product/description cell used in the detail table.
pw.Widget pdfDescriptionCell(String description) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    alignment: pw.Alignment.centerLeft,
    child: pw.Text(
      description,
      style: pw.TextStyle(
        fontSize: 8,
        color: PdfKitColors.textPrimary,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

/// Row for the totals section.
pw.Widget pdfTotalLine(
  String label,
  String value, {
  PdfColor? valueColor,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 8.8, color: PdfKitColors.textPrimary),
          ),
        ),
        pw.Text(
          value,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontSize: 8.8,
            color: valueColor ?? PdfKitColors.textPrimary,
            fontWeight: valueColor != null
                ? pw.FontWeight.bold
                : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

/// Footer with brand on the left and `Página X de Y` on the right.
pw.Widget pdfFooter(
  int pageNumber,
  int totalPages, {
  String brand = 'FullPOS Cloud',
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6),
    child: pw.Row(
      children: [
        pw.Text(
          brand,
          style: pw.TextStyle(fontSize: 8, color: PdfKitColors.textMuted),
        ),
        pw.Spacer(),
        pw.Text(
          'Página $pageNumber de $totalPages',
          style: pw.TextStyle(fontSize: 8, color: PdfKitColors.textMuted),
        ),
      ],
    ),
  );
}

/// Compact header used on continuation pages (page > 1).
pw.Widget pdfContinuationHeader({
  required String companyName,
  required String documentKind,
  required String code,
  required int pageNumber,
  required int pagesCount,
}) {
  final pageText = pagesCount > 0
      ? 'Página $pageNumber de $pagesCount'
      : 'Página $pageNumber';
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 10),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfKitColors.softLine, width: 1)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfKitColors.textPrimary,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                '$documentKind · Continuación',
                style: pw.TextStyle(fontSize: 8, color: PdfKitColors.textMuted),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              code,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfKitColors.textPrimary,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              pageText,
              style: pw.TextStyle(fontSize: 8, color: PdfKitColors.textMuted),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Right-side facts panel (document title + code + fact lines).
pw.Widget pdfFactsPanel({
  required String title,
  required String code,
  required List<(String, String)> facts,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: pw.BoxDecoration(
      color: PdfKitColors.softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: PdfKitColors.panelBorder, width: 0.45),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 8.2,
            fontWeight: pw.FontWeight.bold,
            color: PdfKitColors.accentBlue,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          code,
          style: pw.TextStyle(
            fontSize: 12.4,
            fontWeight: pw.FontWeight.bold,
            color: PdfKitColors.textPrimary,
          ),
        ),
        pw.SizedBox(height: 6),
        for (final (label, value) in facts) pdfFactLine(label, value),
      ],
    ),
  );
}

/// Small `label: value` line used inside the facts panel.
pw.Widget pdfFactLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 7.5, color: PdfKitColors.textMuted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: 8.1, color: PdfKitColors.textPrimary),
          ),
        ),
      ],
    ),
  );
}

/// Soft-filled information panel with an accent label title.
pw.Widget pdfInfoPanel({
  required String title,
  required List<pw.Widget> children,
}) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: pw.BoxDecoration(
      color: PdfKitColors.softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: PdfKitColors.panelBorder, width: 0.45),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 7.6,
            fontWeight: pw.FontWeight.bold,
            color: PdfKitColors.accentBlue,
          ),
        ),
        pw.SizedBox(height: 6),
        ...children,
      ],
    ),
  );
}

/// `label: value` line used inside information panels (e.g. supplier).
pw.Widget pdfPersonLine(
  String label,
  String value, {
  bool strong = false,
}) {
  return pw.SizedBox(
    width: 235,
    child: pw.RichText(
      text: pw.TextSpan(
        style: pw.TextStyle(fontSize: 8.2, color: PdfKitColors.textMuted),
        children: [
          pw.TextSpan(text: '$label: '),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(
              color: strong ? PdfKitColors.textPrimary : PdfKitColors.textMuted,
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Muted line used in the company block of the header.
pw.Widget pdfCompanyLine(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 8.4, color: PdfKitColors.textMuted),
    ),
  );
}
