import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import '../../features/ecf/ecf_print_document.dart';

/// DGII RI §18.2.3: 22 mm QR + 3 mm quiet zone, starts 20 mm from paper edge.
pw.Widget ecfPrintFooter(
  EcfPrintDocument? ecf, {
  double pageLeftInsetMm = 0,
  bool includeIdentity = false,
}) {
  if (ecf == null) return pw.SizedBox();
  final style = pw.TextStyle(fontSize: 7, font: pw.Font.helvetica());
  return pw.Container(
    width: double.infinity,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (includeIdentity)
          for (final line in ecf.identityLines) pw.Text(line, style: style),
        if (!includeIdentity && ecf.notice.isNotEmpty)
          pw.Text(ecf.notice, style: style),
        if (ecf.hasStamp) ...[
          pw.Padding(
            padding: pw.EdgeInsets.only(
              left: math.max(0, 17 - pageLeftInsetMm) * PdfPageFormat.mm,
              top: 3 * PdfPageFormat.mm,
            ),
            child: pw.Container(
              color: PdfColors.white,
              padding: pw.EdgeInsets.all(3 * PdfPageFormat.mm),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: ecf.qrUrl!,
                width: 22 * PdfPageFormat.mm,
                height: 22 * PdfPageFormat.mm,
                drawText: false,
              ),
            ),
          ),
          pw.Text('Código de seguridad: ${ecf.securityCode}', style: style),
          pw.Text('Fecha de firma: ${ecf.signedAt}', style: style),
        ],
      ],
    ),
  );
}

/// Raster QR uses the same barcode engine as PDF/HTML, at 203 dpi.
img.Image ecfQrRaster(String url) {
  const codeSize = 176.0;
  const quiet = 24;
  final image = img.Image(width: 224, height: 224);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (final element in pw.Barcode.qrCode().make(
    url,
    width: codeSize,
    height: codeSize,
    drawText: false,
  )) {
    if (element is pw.BarcodeBar && element.black) {
      img.fillRect(
        image,
        x1: quiet + element.left.round(),
        y1: quiet + element.top.round(),
        x2: quiet + element.right.round() - 1,
        y2: quiet + element.bottom.round() - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return image;
}
