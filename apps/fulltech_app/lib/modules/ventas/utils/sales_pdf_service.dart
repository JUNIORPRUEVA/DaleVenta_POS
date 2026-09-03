import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/uom/uom_formatters.dart';
import '../../../core/utils/money_formatters.dart';
import '../sales_models.dart';

final PdfColor _pageBackground = PdfColors.white;
final PdfColor _borderColor = PdfColor.fromHex('#D9E2EC');
final PdfColor _panelBorder = PdfColor.fromHex('#CBD5E1');
final PdfColor _softFill = PdfColor.fromHex('#F8FAFC');
final PdfColor _softLine = PdfColor.fromHex('#E2E8F0');
final PdfColor _headingBlack = PdfColor.fromHex('#0F172A');
final PdfColor _textPrimary = PdfColor.fromHex('#172033');
final PdfColor _textMuted = PdfColor.fromHex('#64748B');
final PdfColor _accentBlue = PdfColor.fromHex('#1957E6');
final PdfColor _danger = PdfColor.fromHex('#B42318');

String invoicePdfPaymentMethodLabel(String method) {
  return switch (method.trim().toLowerCase()) {
    'cash' => 'Efectivo',
    'card' || 'tarjeta' => 'Tarjeta',
    'transfer' || 'transferencia' => 'Transferencia',
    'mixed' || 'mixto' => 'Mixto',
    'credit' || 'credito' => 'Crédito',
    _ => method.trim().isEmpty ? 'Efectivo' : method.trim(),
  };
}

Future<Uint8List> buildSalesSummaryPdf({
  required String employeeName,
  required DateTime from,
  required DateTime to,
  required SalesSummaryModel summary,
  required List<SaleModel> sales,
}) async {
  final dateFmt = DateFormat('dd/MM/yyyy');

  final doc = pw.Document(title: 'Resumen de ventas', author: 'FullTech');

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          'Resumen de ventas',
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Empleado: $employeeName'),
        pw.Text('Rango: ${dateFmt.format(from)} - ${dateFmt.format(to)}'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          headers: const [
            'Fecha',
            'Cliente',
            'Vendido',
            'Costo',
            'Utilidad',
            'Comisión',
          ],
          data: sales
              .map(
                (sale) => [
                  dateFmt.format(sale.saleDate ?? DateTime.now()),
                  sale.customerName ?? 'Sin cliente',
                  formatRdCurrencyAccounting(sale.totalSold),
                  formatRdCurrencyAccounting(sale.totalCost),
                  formatRdCurrencyAccounting(sale.totalProfit),
                  formatRdCurrencyAccounting(sale.commissionAmount),
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 14),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Container(
            width: 280,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey400),
              color: PdfColors.grey100,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'Totales de quincena',
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                _totalLine('Cantidad', '${summary.totalSales}'),
                _totalLine(
                  'Total vendido',
                  formatRdCurrencyAccounting(summary.totalSold),
                ),
                _totalLine(
                  'Total costo',
                  formatRdCurrencyAccounting(summary.totalCost),
                ),
                _totalLine(
                  'Total puntos',
                  formatRdCurrencyAccounting(summary.totalProfit),
                ),
                pw.Divider(height: 10),
                _totalLine(
                  'Total beneficio (10%)',
                  formatRdCurrencyAccounting(summary.totalCommission),
                  highlight: true,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> downloadSalesSummaryPdf({
  required Uint8List bytes,
  required DateTime from,
  required DateTime to,
}) async {
  final dateFmt = DateFormat('yyyyMMdd');
  final fileName =
      'resumen_ventas_${dateFmt.format(from)}_${dateFmt.format(to)}.pdf';

  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

Future<Uint8List> buildSaleInvoicePdf({
  required SaleModel sale,
  CompanySettings? company,
  String? warrantyPolicy,
}) async {
  final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$');
  final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  final logoImage = await _resolveCompanyLogo(company);
  final companyName = _fallback(
    sale.issuerNameSnapshot,
    fallback: _fallback(company?.companyName, fallback: 'FULLTECH'),
  );
  final invoiceCode = invoicePdfCode(sale.id);
  final warranty = _clean(warrantyPolicy);

  final doc = pw.Document(title: 'Factura $invoiceCode', author: companyName);

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        // Márgenes idénticos a la plantilla de COTIZACIÓN (26/24/26/22):
        // mismo ancho de contenido y misma distribución de secciones.
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 22),
        buildBackground: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _pageBackground),
        ),
      ),
      header: (context) => _invoiceHeader(
        company: company,
        logoImage: logoImage,
        sale: sale,
        invoiceCode: invoiceCode,
        dateFmt: dateFmt,
        pageNumber: context.pageNumber,
        pagesCount: context.pagesCount,
      ),
      footer: (context) => _pageFooter(context.pageNumber, context.pagesCount),
      build: (_) => [
        _invoiceDetailSection(
          sale,
          money,
          qtyFmt,
          showMeasurementUnit: company?.measurementUnitsEnabled == true,
        ),
        pw.SizedBox(height: 14),
        _invoiceBottomSection(sale, money, warrantyPolicy: warranty),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _invoiceHeader({
  required CompanySettings? company,
  required pw.MemoryImage? logoImage,
  required SaleModel sale,
  required String invoiceCode,
  required DateFormat dateFmt,
  required int pageNumber,
  required int pagesCount,
}) {
  final companyName = _fallback(
    sale.issuerNameSnapshot,
    fallback: _fallback(company?.companyName, fallback: 'FULLTECH'),
  );
  if (pageNumber > 1) {
    return _invoiceContinuationHeader(
      companyName: companyName,
      invoiceCode: invoiceCode,
      pageNumber: pageNumber,
      pagesCount: pagesCount,
    );
  }
  final rnc = _fallback(
    sale.issuerTaxIdSnapshot,
    fallback: _clean(company?.rnc),
  );
  final phone = _fallback(
    sale.issuerPhoneSnapshot,
    fallback: _clean(company?.phone),
  );
  final address = _fallback(
    sale.issuerAddressSnapshot,
    fallback: _clean(company?.address),
  );
  final statusText = sale.isDeleted ? 'Factura devuelta' : null;
  final fiscalLabel = invoicePdfDocumentLabel(sale);
  final fiscal = sale.fiscalTaxEnabled;
  final customer = _invoiceCustomerData(sale);

  return _panel(
    margin: const pw.EdgeInsets.only(bottom: 13),
    padding: const pw.EdgeInsets.fromLTRB(0, 2, 0, 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _logoBox(companyName: companyName, logoImage: logoImage),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 17,
                            fontWeight: pw.FontWeight.bold,
                            color: _textPrimary,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        if (rnc.isNotEmpty) _companyLine('RNC: $rnc'),
                        if (phone.isNotEmpty) _companyLine('Tel: $phone'),
                        if (address.isNotEmpty) _companyLine(address),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.SizedBox(
              width: 222,
              child: _documentFactsPanel(
                documentLabel: fiscalLabel,
                code: invoiceCode,
                issuedText: dateFmt.format(sale.saleDate ?? DateTime.now()),
                statusText: statusText,
                ncf: fiscal ? sale.ncf : null,
                ncfExpirationDate: fiscal ? sale.ncfExpirationDate : null,
                cashierName: sale.userName,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(height: 1.1, color: _softLine),
        pw.SizedBox(height: 9),
        _customerPanel(customer),
      ],
    ),
  );
}

/// Cabecera compacta para páginas 2+ (misma estructura que la cotización):
/// evita repetir el encabezado completo y deja espacio para la tabla/totales.
pw.Widget _invoiceContinuationHeader({
  required String companyName,
  required String invoiceCode,
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
      border: pw.Border(bottom: pw.BorderSide(color: _softLine, width: 1)),
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
                  color: _textPrimary,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Factura · Continuación',
                style: pw.TextStyle(fontSize: 8, color: _textMuted),
              ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              invoiceCode,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              pageText,
              style: pw.TextStyle(fontSize: 8, color: _textMuted),
            ),
          ],
        ),
      ],
    ),
  );
}

class _InvoiceCustomerData {
  final String name;
  final String taxId;
  final String phone;
  final String address;

  const _InvoiceCustomerData({
    required this.name,
    required this.taxId,
    required this.phone,
    required this.address,
  });
}

_InvoiceCustomerData _invoiceCustomerData(SaleModel sale) {
  return _InvoiceCustomerData(
    name: _fallback(
      sale.fiscalCustomerName ?? sale.customerName,
      fallback: 'Consumidor final',
    ),
    taxId: _clean(sale.fiscalCustomerTaxId),
    phone: _fallback(
      sale.customerPhoneSnapshot,
      fallback: _clean(sale.customerPhone),
    ),
    address: _clean(sale.customerAddressSnapshot),
  );
}

pw.Widget _customerPanel(_InvoiceCustomerData customer) {
  final cleanName = customer.name.trim();
  final normalized = cleanName.toLowerCase();
  final isFinalConsumer =
      cleanName.isEmpty ||
      normalized == 'consumidor final' ||
      normalized == 'sin cliente' ||
      normalized == 'cliente no especificado';
  final rows = <pw.Widget>[
    if (isFinalConsumer)
      _plainCustomerName('Consumidor final')
    else ...[
      _personLine('Nombre', cleanName, strong: true),
      if (customer.taxId.isNotEmpty) _personLine('RNC/Cédula', customer.taxId),
      if (customer.phone.isNotEmpty) _personLine('Teléfono', customer.phone),
      if (customer.address.isNotEmpty)
        _personLine('Dirección', customer.address),
    ],
  ];

  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: _panelBorder, width: 0.45),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'DATOS DEL CLIENTE',
          style: pw.TextStyle(
            fontSize: 7.6,
            fontWeight: pw.FontWeight.bold,
            color: _accentBlue,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Wrap(spacing: 18, runSpacing: 5, children: rows),
      ],
    ),
  );
}

pw.Widget _plainCustomerName(String value) {
  return pw.Text(
    value,
    style: pw.TextStyle(
      fontSize: 9,
      color: _textPrimary,
      fontWeight: pw.FontWeight.bold,
    ),
  );
}

pw.Widget _invoiceDetailSection(
  SaleModel sale,
  NumberFormat money,
  NumberFormat qtyFmt, {
  required bool showMeasurementUnit,
}) {
  final fiscal = sale.fiscalTaxEnabled;
  final hasProductDiscount = sale.items.any(
    (item) => item.lineDiscountAmount > 0,
  );
  final tableRows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: _headingBlack),
      children: [
        _headerCell('Descripción', align: pw.TextAlign.left),
        _headerCell('Cant.'),
        _headerCell('Precio unidad', align: pw.TextAlign.right),
        if (hasProductDiscount)
          _headerCell('Descuento', align: pw.TextAlign.right),
        if (fiscal) _headerCell('ITBIS', align: pw.TextAlign.right),
        _headerCell('Total', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (sale.items.isEmpty) {
    tableRows.add(
      pw.TableRow(
        children: [
          _emptyCell('No hay productos registrados en esta factura.'),
          _emptyCell(''),
          _emptyCell(''),
          if (hasProductDiscount) _emptyCell(''),
          if (fiscal) _emptyCell(''),
          _emptyCell(''),
        ],
      ),
    );
  } else {
    for (var index = 0; index < sale.items.length; index++) {
      final item = sale.items[index];
      final isExempt = item.taxExempt || item.exemptAmount > 0;
      final description = item.productNameSnapshot.trim().isEmpty
          ? 'Producto sin descripción'
          : item.productNameSnapshot.trim();
      // Precio unitario ORIGINAL (bruto/qty) para que la columna "Precio
      // unidad" + "Descuento" reconcilié con el total de la línea, igual que
      // la cotización. grossAmount = original × qty en documentos nuevos.
      final originalUnitPrice = item.grossAmount > 0
          ? item.grossAmount / item.qty
          : item.priceSoldUnit;
      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isOdd ? PdfColor.fromHex('#FBFDFF') : PdfColors.white,
          ),
          children: [
            _descriptionCell(
              isExempt && fiscal ? '$description  [EXENTO]' : description,
            ),
            _bodyCell(
              formatQuantityForFeature(
                item.qty,
                unit: item.unitSnapshot,
                showMeasurementUnit: showMeasurementUnit,
                includeUnitForUnit: true,
              ),
              align: pw.TextAlign.center,
            ),
            _bodyCell(
              money.format(_roundMoney(originalUnitPrice)),
              align: pw.TextAlign.right,
            ),
            if (hasProductDiscount)
              _bodyCell(
                item.lineDiscountAmount > 0
                    ? '-${money.format(item.lineDiscountAmount)}'
                    : '-',
                align: pw.TextAlign.right,
                textColor: item.lineDiscountAmount > 0 ? _danger : _textMuted,
              ),
            if (fiscal)
              _bodyCell(
                money.format(item.taxAmount),
                align: pw.TextAlign.right,
              ),
            _bodyCell(
              money.format(item.subtotalSold),
              align: pw.TextAlign.right,
              bold: true,
            ),
          ],
        ),
      );
    }
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Detalle de productos',
        style: pw.TextStyle(
          fontSize: 10.8,
          fontWeight: pw.FontWeight.bold,
          color: _textPrimary,
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Table(
        border: pw.TableBorder(
          top: pw.BorderSide(color: _panelBorder, width: 0.45),
          bottom: pw.BorderSide(color: _panelBorder, width: 0.45),
          left: pw.BorderSide(color: _panelBorder, width: 0.45),
          right: pw.BorderSide(color: _panelBorder, width: 0.45),
          horizontalInside: pw.BorderSide(color: _borderColor, width: 0.45),
        ),
        columnWidths: _invoiceDetailColumnWidths(hasProductDiscount, fiscal),
        children: tableRows,
      ),
    ],
  );
}

Map<int, pw.TableColumnWidth> _invoiceDetailColumnWidths(
  bool hasProductDiscount,
  bool fiscal,
) {
  if (fiscal && hasProductDiscount) {
    return const {
      0: pw.FlexColumnWidth(3.45),
      1: pw.FlexColumnWidth(0.62),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(1.02),
      4: pw.FlexColumnWidth(0.92),
      5: pw.FlexColumnWidth(1.12),
    };
  }
  if (fiscal) {
    return const {
      0: pw.FlexColumnWidth(3.9),
      1: pw.FlexColumnWidth(0.62),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(0.92),
      4: pw.FlexColumnWidth(1.12),
    };
  }
  if (hasProductDiscount) {
    return const {
      0: pw.FlexColumnWidth(3.45),
      1: pw.FlexColumnWidth(0.62),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(1.02),
      4: pw.FlexColumnWidth(1.12),
    };
  }
  return const {
    0: pw.FlexColumnWidth(4.1),
    1: pw.FlexColumnWidth(0.7),
    2: pw.FlexColumnWidth(1.2),
    3: pw.FlexColumnWidth(1.2),
  };
}

pw.Widget _descriptionCell(String description) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    alignment: pw.Alignment.centerLeft,
    child: pw.Text(
      description,
      style: pw.TextStyle(
        fontSize: 8,
        color: _textPrimary,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _invoiceBottomSection(
  SaleModel sale,
  NumberFormat money, {
  String? warrantyPolicy,
}) {
  final note = invoicePdfNoteText(sale.note);
  final warranty = _clean(warrantyPolicy);
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _panel(
              padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
              fillColor: _softFill,
              showBorder: true,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FORMA DE PAGO',
                    style: pw.TextStyle(
                      fontSize: 7.8,
                      fontWeight: pw.FontWeight.bold,
                      color: _textMuted,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    invoicePdfPaymentMethodLabel(sale.paymentMethod),
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  if ((sale.cashReceived ?? 0) > 0) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'EFECTIVO RECIBIDO: ${money.format(sale.cashReceived ?? 0)}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'DEVUELTA: ${money.format(sale.changeAmount ?? 0)}',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (warranty.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _panel(
                padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
                fillColor: _softFill,
                showBorder: true,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'TÉRMINOS DE GARANTÍA',
                      style: pw.TextStyle(
                        fontSize: 7.8,
                        fontWeight: pw.FontWeight.bold,
                        color: _textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      warranty,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: _textPrimary,
                        lineSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (note.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              _panel(
                padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
                fillColor: _softFill,
                showBorder: true,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'NOTAS',
                      style: pw.TextStyle(
                        fontSize: 7.8,
                        fontWeight: pw.FontWeight.bold,
                        color: _textMuted,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      note,
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        color: _textPrimary,
                        lineSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      pw.SizedBox(width: 14),
      pw.SizedBox(width: 270, child: _invoiceTotalsPanel(sale, money)),
    ],
  );
}

/// Datos financieros de presentación de una factura. Única fuente de la
/// lógica monetaria del PDF: el PDF solo presenta, nunca reinterpreta los
/// descuentos. Los importes provienen de la venta almacenada.
class SalePdfViewData {
  final double subtotal;
  final double productDiscount;
  final double generalDiscount;
  final double exemptAmount;
  final double taxableBase;
  final double taxAmount;
  final double total;
  final bool fiscalEnabled;

  const SalePdfViewData({
    required this.subtotal,
    required this.productDiscount,
    required this.generalDiscount,
    required this.exemptAmount,
    required this.taxableBase,
    required this.taxAmount,
    required this.total,
    required this.fiscalEnabled,
  });
}

/// Construye los datos de presentación de la factura:
/// - subtotal = suma de `grossAmount` (bruto original de cada línea).
/// - productDiscount = suma de los descuentos REALES de línea.
/// - generalDiscount = descuento general REAL del documento
///   (sale.discountAmount − productDiscount), nunca prorrateado.
SalePdfViewData buildSalePdfViewData(SaleModel sale) {
  final fiscal = sale.fiscalTaxEnabled;
  final subtotal = _roundMoney(
    sale.items.fold<double>(
      0,
      (sum, item) =>
          sum + (item.grossAmount > 0 ? item.grossAmount : item.subtotalSold),
    ),
  );
  final productDiscount = _roundMoney(
    sale.items.fold<double>(
      0,
      (sum, item) =>
          sum + (item.lineDiscountAmount > 0 ? item.lineDiscountAmount : 0),
    ),
  );
  final generalDiscount = _roundMoney(
    (sale.discountAmount - productDiscount).clamp(0.0, double.infinity),
  );
  return SalePdfViewData(
    subtotal: subtotal,
    productDiscount: productDiscount,
    generalDiscount: generalDiscount,
    exemptAmount: _roundMoney(fiscal ? sale.exemptAmount : 0),
    taxableBase: _roundMoney(fiscal ? sale.taxableBase : 0),
    taxAmount: _roundMoney(fiscal ? sale.taxAmount : 0),
    total: _roundMoney(sale.totalSold),
    fiscalEnabled: fiscal,
  );
}

pw.Widget _invoiceTotalsPanel(SaleModel sale, NumberFormat money) {
  final totals = buildSalePdfViewData(sale);
  final fiscal = totals.fiscalEnabled;

  return _panel(
    padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 13),
    fillColor: _softFill,
    showBorder: true,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Resumen',
          style: pw.TextStyle(
            fontSize: 10.8,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 9),
        _pdfTotalLine('Subtotal', money.format(totals.subtotal)),
        if (totals.productDiscount > 0)
          _pdfTotalLine(
            'Descuentos por productos',
            '-${money.format(totals.productDiscount)}',
            amountColor: _danger,
          ),
        if (totals.generalDiscount > 0)
          _pdfTotalLine(
            'Descuento general',
            '-${money.format(totals.generalDiscount)}',
            amountColor: _danger,
          ),
        if (fiscal) ...[
          if (totals.exemptAmount > 0)
            _pdfTotalLine('Monto exento', money.format(totals.exemptAmount)),
          if (totals.taxableBase > 0)
            _pdfTotalLine('Base imponible', money.format(totals.taxableBase)),
          if (totals.taxAmount > 0)
            _pdfTotalLine('ITBIS', money.format(totals.taxAmount)),
        ],
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Container(height: 1, color: _softLine),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'TOTAL',
                  style: pw.TextStyle(
                    fontSize: 10.4,
                    fontWeight: pw.FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
              ),
              pw.Text(
                money.format(totals.total),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _accentBlue,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _totalLine(String label, String value, {bool highlight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: 10,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _pageFooter(int pageNumber, int totalPages) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 6),
    child: pw.Row(
      children: [
        pw.Spacer(),
        pw.Text(
          'Página $pageNumber de $totalPages',
          style: pw.TextStyle(fontSize: 8, color: _textMuted),
        ),
      ],
    ),
  );
}

Future<pw.MemoryImage?> _resolveCompanyLogo(CompanySettings? company) async {
  final rawLogo = _clean(company?.logoBase64);
  if (rawLogo.isNotEmpty) {
    try {
      return pw.MemoryImage(base64Decode(rawLogo));
    } catch (_) {}
  }

  try {
    final asset = await rootBundle.load('assets/image/logo.png');
    return pw.MemoryImage(asset.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

String invoicePdfCode(String id) {
  final token = _buildFileToken(id, length: 8, fallback: 'MANUAL');
  return 'FAC-$token';
}

String _buildFileToken(
  String id, {
  required int length,
  required String fallback,
}) {
  final normalized = id.replaceAll('-', '').trim();
  if (normalized.isEmpty) return fallback;
  return normalized.length > length
      ? normalized.substring(0, length).toUpperCase()
      : normalized.toUpperCase();
}

String _fallback(String? value, {required String fallback}) {
  final cleaned = _clean(value);
  return cleaned.isEmpty ? fallback : cleaned;
}

String _clean(String? value) => (value ?? '').trim();

double _roundMoney(double value) => (value * 100).round() / 100;

/// Nota de la factura sin líneas de pago duplicadas: el checkout añade
/// `Pago: <método>` a la nota, pero el método ya se muestra en el bloque
/// "FORMA DE PAGO".
String invoicePdfNoteText(String? note) {
  final raw = _clean(note);
  if (raw.isEmpty) return '';
  final lines = raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => !line.toLowerCase().startsWith('pago:'))
      .toList();
  return lines.join('\n').trim();
}

String invoicePdfDocumentLabel(SaleModel sale) {
  final voucherType = _clean(sale.fiscalVoucherType).toUpperCase();
  if (voucherType == 'B02') {
    return 'FACTURA / CONSUMIDOR FINAL';
  }
  if (voucherType == 'B01' || _clean(sale.ncf).isNotEmpty) {
    return 'FACTURA / CRÉDITO FISCAL';
  }
  return 'FACTURA';
}

pw.Widget _panel({
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
          ? pw.Border.all(color: _panelBorder, width: 0.45)
          : null,
    ),
    child: child,
  );
}

pw.Widget _logoBox({
  required String companyName,
  required pw.MemoryImage? logoImage,
}) {
  return pw.Container(
    width: 62,
    height: 62,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: _panelBorder, width: 0.45),
    ),
    child: logoImage != null
        ? pw.Image(logoImage, fit: pw.BoxFit.contain)
        : pw.Center(
            child: pw.Text(
              companyName.substring(0, 1).toUpperCase(),
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: _textPrimary,
              ),
            ),
          ),
  );
}

pw.Widget _companyLine(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 2),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8.5, color: _textMuted)),
  );
}

pw.Widget _documentFactsPanel({
  required String documentLabel,
  required String code,
  required String issuedText,
  String? statusText,
  String? subtitle,
  String? ncf,
  DateTime? ncfExpirationDate,
  String? cashierName,
  bool showFiscal = true,
}) {
  final cleanSubtitle = _clean(subtitle);
  final cleanNcf = _clean(ncf);
  final cleanCashier = _clean(cashierName);
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: pw.BoxDecoration(
      color: _softFill,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      border: pw.Border.all(color: _panelBorder, width: 0.45),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          documentLabel,
          style: pw.TextStyle(
            fontSize: 8.4,
            fontWeight: pw.FontWeight.bold,
            color: _accentBlue,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          code,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        pw.SizedBox(height: 6),
        if (cleanSubtitle.isNotEmpty) ...[
          pw.Text(
            cleanSubtitle,
            style: pw.TextStyle(
              fontSize: 8.4,
              fontWeight: pw.FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          pw.SizedBox(height: 4),
        ],
        if (showFiscal && cleanNcf.isNotEmpty) _factLine('NCF', cleanNcf),
        if (showFiscal && ncfExpirationDate != null)
          _factLine(
            'Vencimiento',
            DateFormat('dd/MM/yyyy').format(ncfExpirationDate),
          ),
        if (cleanCashier.isNotEmpty) _factLine('Cajero', cleanCashier),
        _factLine('Expedición', issuedText),
        if (statusText != null && statusText.trim().isNotEmpty) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            statusText,
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColor.fromHex('#B42318'),
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _factLine(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 58,
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 7.6, color: _textMuted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(fontSize: 8.2, color: _textPrimary),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _personLine(String label, String value, {bool strong = false}) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 58,
        child: pw.Text(
          label,
          style: pw.TextStyle(fontSize: 8.1, color: _textMuted),
        ),
      ),
      pw.Expanded(
        child: pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8.8,
            color: strong ? _textPrimary : _textMuted,
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    ],
  );
}

pw.Widget _headerCell(String text, {pw.TextAlign align = pw.TextAlign.center}) {
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
        fontSize: 7.4,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _bodyCell(
  String text, {
  pw.TextAlign align = pw.TextAlign.left,
  bool bold = false,
  PdfColor? textColor,
  bool noWrap = false,
  double horizontalPadding = 6,
  double fontSize = 7.6,
}) {
  return pw.Container(
    padding: pw.EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: 6,
    ),
    alignment: align == pw.TextAlign.center
        ? pw.Alignment.center
        : align == pw.TextAlign.right
        ? pw.Alignment.centerRight
        : pw.Alignment.centerLeft,
    child: pw.Text(
      text,
      textAlign: align,
      // Nunca partir un importe: una sola línea.
      maxLines: noWrap ? 1 : null,
      softWrap: noWrap ? false : null,
      style: pw.TextStyle(
        fontSize: fontSize,
        color: textColor ?? _textPrimary,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _emptyCell(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 7),
    child: pw.Text(text, style: pw.TextStyle(fontSize: 8, color: _textMuted)),
  );
}

pw.Widget _pdfTotalLine(String label, String value, {PdfColor? amountColor}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(fontSize: 9.1, color: _textPrimary),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 9.1,
            color: amountColor ?? _textPrimary,
          ),
        ),
      ],
    ),
  );
}
