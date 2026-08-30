import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/company/company_settings_model.dart';
import '../../../core/pdf/pdf_kit.dart';
import '../../../core/uom/uom_formatters.dart';
import '../purchase_models.dart';

/// Builds the Purchase Order PDF using the same visual language as
/// Cotizaciones (shared `pdf_kit.dart`): same header, logo resolution,
/// typography, blocks, table and footer.
Future<Uint8List> buildPurchaseOrderPdf({
  required PurchaseOrderModel order,
  CompanySettings? company,
}) async {
  final logoImage = await pdfResolveCompanyLogo(company);
  final money = PdfKitFormats.money();
  final qtyFmt = PdfKitFormats.qty();
  final dateFmt = PdfKitFormats.shortDate();
  final companyName = pdfFallback(company?.companyName, fallback: 'FULLTECH');
  final isDraft = order.status == 'DRAFT';
  final orderCode = isDraft || order.orderNumber.trim().isEmpty
      ? 'BORRADOR'
      : order.orderNumber;

  final doc = pw.Document(
    title: 'ORDEN DE COMPRA $orderCode',
    author: companyName,
  );

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 22),
        buildBackground: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: PdfKitColors.pageBackground),
        ),
      ),
      header: (context) => _pageHeader(
        companyName: companyName,
        company: company,
        logoImage: logoImage,
        order: order,
        orderCode: orderCode,
        isDraft: isDraft,
        dateFmt: dateFmt,
        pageNumber: context.pageNumber,
        pagesCount: context.pagesCount,
      ),
      footer: (context) => pdfFooter(context.pageNumber, context.pagesCount),
      build: (_) => [
        ..._detailSection(order, money, qtyFmt),
        pw.SizedBox(height: 14),
        _bottomSection(order, money),
        pw.SizedBox(height: 16),
        _signatureRow(order),
      ],
    ),
  );

  return doc.save();
}

pw.Widget _pageHeader({
  required String companyName,
  required CompanySettings? company,
  required pw.MemoryImage? logoImage,
  required PurchaseOrderModel order,
  required String orderCode,
  required bool isDraft,
  required DateFormat dateFmt,
  required int pageNumber,
  required int pagesCount,
}) {
  if (pageNumber > 1) {
    return pdfContinuationHeader(
      companyName: companyName,
      documentKind: 'Orden de compra',
      code: orderCode,
      pageNumber: pageNumber,
      pagesCount: pagesCount,
    );
  }

  return pdfPanel(
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
                  pdfLogoBox(companyName: companyName, logoImage: logoImage),
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
                            color: PdfKitColors.textPrimary,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        if (pdfClean(company?.rnc).isNotEmpty)
                          pdfCompanyLine('RNC: ${company!.rnc}'),
                        if (pdfClean(company?.phone).isNotEmpty)
                          pdfCompanyLine('Tel: ${company!.phone}'),
                        if (pdfClean(company?.address).isNotEmpty)
                          pdfCompanyLine(company!.address),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.SizedBox(
              width: 222,
              child: pdfFactsPanel(
                title: 'ORDEN DE COMPRA',
                code: orderCode,
                facts: [
                  (
                    'Fecha',
                    order.orderDate == null
                        ? '-'
                        : dateFmt.format(order.orderDate!),
                  ),
                  if (!isDraft)
                    ('Estado', purchaseOrderStatusLabel(order.status)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(height: 1.1, color: PdfKitColors.softLine),
        pw.SizedBox(height: 9),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _supplierPanel(order)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _deliveryPanel(order, dateFmt)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _supplierPanel(PurchaseOrderModel order) {
  final supplier = order.supplier;
  final name = pdfClean(supplier?.commercialName);
  final rows = <pw.Widget>[
    if (name.isEmpty)
      pw.Text(
        'Sin suplidor',
        style: pw.TextStyle(
          fontSize: 9,
          color: PdfKitColors.textPrimary,
          fontWeight: pw.FontWeight.bold,
        ),
      )
    else ...[
      pdfPersonLine('Nombre', name, strong: true),
      if (pdfClean(supplier?.taxId).isNotEmpty)
        pdfPersonLine('RNC/Cédula', supplier!.taxId!),
      if (pdfClean(supplier?.contactName).isNotEmpty)
        pdfPersonLine('Contacto', supplier!.contactName!),
      if (pdfClean(supplier?.phone).isNotEmpty)
        pdfPersonLine('Teléfono', supplier!.phone!),
      if (pdfClean(supplier?.whatsapp).isNotEmpty)
        pdfPersonLine('WhatsApp', supplier!.whatsapp!),
      if (pdfClean(supplier?.email).isNotEmpty)
        pdfPersonLine('Correo', supplier!.email!),
      if (pdfClean(supplier?.address).isNotEmpty)
        pdfPersonLine('Dirección', supplier!.address!),
    ],
  ];
  return pdfInfoPanel(title: 'DATOS DEL SUPLIDOR', children: rows);
}

pw.Widget _deliveryPanel(PurchaseOrderModel order, DateFormat dateFmt) {
  final rows = <pw.Widget>[
    pdfPersonLine(
      'Entrega estimada',
      order.expectedDeliveryDate == null
          ? '-'
          : dateFmt.format(order.expectedDeliveryDate!),
    ),
    if (pdfClean(order.supplier?.paymentTerms).isNotEmpty)
      pdfPersonLine('Condiciones', order.supplier!.paymentTerms!),
    if (pdfClean(order.supplierInstructions).isNotEmpty)
      pdfPersonLine('Instrucciones', order.supplierInstructions!),
  ];
  return pdfInfoPanel(title: 'ENTREGA E INSTRUCCIONES', children: rows);
}

List<pw.Widget> _detailSection(
  PurchaseOrderModel order,
  NumberFormat money,
  NumberFormat qtyFmt,
) {
  final rows = <pw.TableRow>[
    pw.TableRow(
      repeat: true,
      decoration: pw.BoxDecoration(color: PdfKitColors.headingBlack),
      children: [
        pdfHeaderCell('Código', align: pw.TextAlign.left),
        pdfHeaderCell('Descripción', align: pw.TextAlign.left),
        pdfHeaderCell('Cant.'),
        pdfHeaderCell('Costo', align: pw.TextAlign.right),
        pdfHeaderCell('Subtotal', align: pw.TextAlign.right),
      ],
    ),
  ];

  if (order.items.isEmpty) {
    rows.add(
      pw.TableRow(
        children: [
          pdfBodyCell('-'),
          pdfBodyCell('No hay productos en esta orden de compra.'),
          pdfBodyCell(''),
          pdfBodyCell(''),
          pdfBodyCell(''),
        ],
      ),
    );
  } else {
    for (var index = 0; index < order.items.length; index++) {
      final item = order.items[index];
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: index.isOdd ? PdfKitColors.zebraFill : PdfColors.white,
          ),
          children: [
            pdfBodyCell(
              purchaseOrderDisplayProductCode(item.productCode),
              align: pw.TextAlign.left,
              textColor: PdfKitColors.textMuted,
            ),
            pdfDescriptionCell(item.productName),
            pdfBodyCell(
              formatQuantityWithUnit(item.quantity, unit: item.unitSnapshot),
              align: pw.TextAlign.center,
            ),
            pdfBodyCell(money.format(item.unitCost), align: pw.TextAlign.right),
            pdfBodyCell(
              money.format(item.subtotal),
              align: pw.TextAlign.right,
              bold: true,
            ),
          ],
        ),
      );
    }
  }

  return [
    pw.Text(
      'Detalle de productos',
      style: pw.TextStyle(
        fontSize: 10.8,
        fontWeight: pw.FontWeight.bold,
        color: PdfKitColors.textPrimary,
      ),
    ),
    pw.SizedBox(height: 8),
    pw.Table(
      border: pw.TableBorder(
        top: pw.BorderSide(color: PdfKitColors.panelBorder, width: 0.45),
        bottom: pw.BorderSide(color: PdfKitColors.panelBorder, width: 0.45),
        left: pw.BorderSide(color: PdfKitColors.panelBorder, width: 0.45),
        right: pw.BorderSide(color: PdfKitColors.panelBorder, width: 0.45),
        horizontalInside: pw.BorderSide(
          color: PdfKitColors.borderColor,
          width: 0.45,
        ),
      ),
      columnWidths: {
        0: pw.FlexColumnWidth(0.95), // Código (compact)
        1: pw.FlexColumnWidth(3.4), // Descripción (primary)
        2: pw.FlexColumnWidth(0.55), // Cant.
        3: pw.FlexColumnWidth(1.0), // Costo
        4: pw.FlexColumnWidth(1.05), // Subtotal
      },
      children: rows,
    ),
  ];
}

pw.Widget _bottomSection(PurchaseOrderModel order, NumberFormat money) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pdfPanel(
          padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 13),
          fillColor: PdfKitColors.softFill,
          showBorder: true,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Observaciones',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfKitColors.textPrimary,
                ),
              ),
              pw.SizedBox(height: 7),
              pw.Text(
                pdfClean(order.notes).isEmpty
                    ? 'Sin observaciones.'
                    : order.notes!,
                style: pw.TextStyle(
                  fontSize: 9,
                  color: pdfClean(order.notes).isEmpty
                      ? PdfKitColors.textMuted
                      : PdfKitColors.textPrimary,
                  fontStyle: pdfClean(order.notes).isEmpty
                      ? pw.FontStyle.italic
                      : pw.FontStyle.normal,
                  lineSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
      pw.SizedBox(width: 14),
      pw.SizedBox(width: 238, child: _totalsPanel(order, money)),
    ],
  );
}

pw.Widget _totalsPanel(PurchaseOrderModel order, NumberFormat money) {
  return pdfPanel(
    padding: const pw.EdgeInsets.fromLTRB(14, 13, 14, 13),
    fillColor: PdfKitColors.softFill,
    showBorder: true,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Resumen',
          style: pw.TextStyle(
            fontSize: 10.8,
            fontWeight: pw.FontWeight.bold,
            color: PdfKitColors.textPrimary,
          ),
        ),
        pw.SizedBox(height: 9),
        pdfTotalLine('Subtotal', money.format(order.subtotal)),
        if (order.discount != 0)
          pdfTotalLine(
            'Descuento',
            '-${money.format(order.discount.abs())}',
            valueColor: PdfKitColors.danger,
          ),
        if (order.shippingCost != 0)
          pdfTotalLine('Transporte', money.format(order.shippingCost)),
        if (order.additionalCost != 0)
          pdfTotalLine(
            'Costos adicionales',
            money.format(order.additionalCost),
          ),
        if (order.tax != 0) pdfTotalLine('Impuestos', money.format(order.tax)),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Container(height: 1, color: PdfKitColors.softLine),
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
                  'TOTAL DE INVERSIÓN',
                  style: pw.TextStyle(
                    fontSize: 10.4,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfKitColors.textPrimary,
                  ),
                ),
              ),
              pw.Text(
                money.format(order.total),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfKitColors.accentBlue,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _signatureRow(PurchaseOrderModel order) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Responsable: ${pdfClean(order.createdByName)}',
        style: pw.TextStyle(fontSize: 8.4, color: PdfKitColors.textMuted),
      ),
      pw.Container(
        width: 180,
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey)),
        ),
        child: pw.Center(
          child: pw.Text(
            'Firma',
            style: pw.TextStyle(fontSize: 8.4, color: PdfKitColors.textMuted),
          ),
        ),
      ),
    ],
  );
}

/// Maps a real purchase order status to its professional Spanish label.
/// Never exposes technical statuses (DRAFT, PENDING_APPROVAL, ...).
String purchaseOrderStatusLabel(String status) {
  switch (status) {
    case 'DRAFT':
      return 'Borrador';
    case 'PENDING_APPROVAL':
      return 'Pendiente de aprobación';
    case 'APPROVED':
      return 'Aprobada';
    case 'SENT':
      return 'Enviada';
    case 'PARTIALLY_RECEIVED':
      return 'Recibida parcial';
    case 'RECEIVED':
      return 'Recibida';
    case 'CANCELLED':
      return 'Cancelada';
    default:
      return status;
  }
}

/// Displays a compact, professional product code in the PDF table.
///
/// Internal UUIDs are truncated to 8 chars (`b3e5350c`) so they never break
/// the table layout. Real SKUs/codes are shown as configured.
String purchaseOrderDisplayProductCode(String? code) {
  final value = pdfClean(code);
  if (value.isEmpty) return '-';
  final isUuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
  if (!isUuid) return value;
  final token = value.replaceAll('-', '');
  return token.length > 8
      ? token.substring(0, 8).toUpperCase()
      : token.toUpperCase();
}
