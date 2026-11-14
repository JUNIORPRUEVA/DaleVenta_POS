import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/printing/ecf_document_pdf.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_print_document.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_document_print_action.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdfread;

// Synthetic representation only. No request to DGII/DOSA and no real emission.
Map<String, dynamic> noteJson({int count = 1, String state = 'SIGNED'}) => {
  'documentId': 'synthetic-e34',
  'documentType': 'E34',
  'label': 'Nota de Crédito Electrónica',
  'encf': 'E340000000001',
  'environment': 'SANDBOX',
  'state': state,
  'issueDate': '2026-11-13',
  'issuerName': 'EMPRESA DEMOSTRACION SRL',
  'issuerRnc': '133080206',
  'issuerAddress': 'Santo Domingo',
  'buyerName': 'RECEPTOR DE PRUEBA',
  'buyerRnc': '133306001',
  'originalEncf': 'E310000000002',
  'originalIssueDate': '2026-11-12',
  'modificationReason': 'Devolución parcial de mercancía',
  'modificationText': 'Corrige montos del NCF modificado',
  'currency': 'DOP',
  'total': (118 * count).toString(),
  'subtotal': (100 * count).toString(),
  'taxableBase': (100 * count).toString(),
  'exemptAmount': '0',
  'itbisAmount': (18 * count).toString(),
  'discountAmount': '0',
  'lines': List.generate(
    count,
    (index) => {
      'name': 'Artículo de demostración ${index + 1}',
      'quantity': '1',
      'unitPrice': '100',
      'total': '118',
      'taxableBase': '100',
      'taxAmount': '18',
      'exemptAmount': '0',
      'discount': '0',
      'taxExempt': false,
      'unitOfMeasure': 'Unidad',
    },
  ),
  if (state == 'SIGNED') ...{
    'qrUrl':
        'https://ecf.dgii.gov.do/testecf/ConsultaTimbre?RNCEmisor=133080206&RncComprador=133306001&ENCF=E340000000001&FechaEmision=13-11-2026&MontoTotal=${118 * count}.00&FechaFirma=13-11-2026%2012:00:00&CodigoSeguridad=ABC123',
    'securityCode': 'ABC123',
    'signedAt': '13-11-2026 12:00:00',
  },
};

class _Repository extends EcfRepository {
  _Repository(this.answer) : super(Dio());
  final Future<EcfPrintDocument> Function() answer;
  @override
  Future<EcfPrintDocument> printDocument(String documentId) => answer();
}

class _Printer extends UnifiedTicketPrinter {
  _Printer(super.ref);
  TicketData? received;
  @override
  Future<PrintTicketResult> printTicket(
    TicketData data, {
    int? overrideCopies,
    bool showSystemDialogIfNoPrinter = true,
  }) async {
    received = data;
    return const PrintTicketResult(success: true, message: 'Prueba sintética');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es_DO'));
  test(
    'E34 uses its own credited items and never recreates the original sale',
    () {
      final doc = EcfPrintDocument.fromJson(noteJson());
      final ticket = TicketData.fromEcf(doc);
      expect(ticket.type, TicketType.credit);
      expect(ticket.total, 118);
      expect(ticket.cashReceived, isNull);
      expect(ticket.items.single.qty, 1);
      expect(ticket.ecf!.originalEncf, 'E310000000002');
      expect(ticket.ncfExpirationDate, isNull);
      expect(
        () => TicketData.fromEcf(
          EcfPrintDocument.fromJson({...noteJson(), 'total': '119'}),
        ),
        throwsStateError,
      );
      expect(
        () => TicketData.fromEcf(
          EcfPrintDocument.fromJson({...noteJson(), 'lines': []}),
        ),
        throwsStateError,
      );
    },
  );
  test('standalone fiscal ticket shows a discount only once', () {
    final json = noteJson();
    final line = Map<String, dynamic>.from(
      (json['lines'] as List).single as Map,
    );
    json.addAll({
      'total': '106.20',
      'subtotal': '90',
      'taxableBase': '90',
      'itbisAmount': '16.20',
      'discountAmount': '10',
      'lines': [
        {
          ...line,
          'discount': '10',
          'taxableBase': '90',
          'taxAmount': '16.20',
          'total': '106.20',
        },
      ],
    });
    final ticket = TicketData.fromEcf(EcfPrintDocument.fromJson(json));
    expect(ticket.subtotal, 100);
    expect(ticket.productDiscount, 10);
    expect(ticket.subtotal! - ticket.discount + ticket.itbis, ticket.total);
  });
  test(
    'E34 A4 repeats fiscal identity, reference, stamp and page amounts',
    () async {
      final doc = EcfPrintDocument.fromJson(noteJson(count: 60));
      final bytes = await buildEcfDocumentPdf(doc);
      final pdf = pdfread.PdfDocument(inputBytes: bytes);
      expect(pdf.pages.count, greaterThan(1));
      for (var index = 0; index < pdf.pages.count; index++) {
        final text = pdfread.PdfTextExtractor(pdf)
            .extractText(startPageIndex: index, endPageIndex: index)
            .replaceAll(RegExp(r'\s+'), ' ');
        expect(text, contains('E340000000001'));
        expect(text, contains('E310000000002'));
        expect(text, contains('ABC123'));
        expect(text, contains('SIN VALIDEZ FISCAL'));
        expect(text, isNot(contains('Vence:')));
        if (index < pdf.pages.count - 1) {
          expect(text, contains('Monto total página:'));
        }
      }
      pdf.dispose();
    },
  );
  test(
    'E34 thermal and A4 preserve QR reference, pending never invents one',
    () async {
      final doc = EcfPrintDocument.fromJson(noteJson());
      final target = Platform.environment['FULLPOS_E34_PRINT_QA'];
      final pdfs = <String, List<int>>{
        'nota-credito-a4.pdf': await buildEcfDocumentPdf(doc),
      };
      final receipt = ThermalReceiptViewModel.fromTicketData(
        data: TicketData.fromEcf(doc),
        company: const CompanyInfo(name: 'Ignored current name'),
      );
      for (final width in [58.0, 80.0]) {
        pdfs['nota-credito-${width.toInt()}.pdf'] =
            await HtmlThermalReceiptPdfRenderer(
              paperWidthMm: width,
            ).render(receipt);
      }
      for (final entry in pdfs.entries) {
        final pdf = pdfread.PdfDocument(inputBytes: entry.value);
        final text = pdfread.PdfTextExtractor(
          pdf,
        ).extractText().replaceAll(RegExp(r'\s+'), ' ');
        expect(text, contains('E340000000001'));
        expect(text, contains('E310000000002'));
        expect(text, contains('ABC123'));
        pdf.dispose();
        if (target != null) {
          await Directory(target).create(recursive: true);
          await File('$target/${entry.key}').writeAsBytes(entry.value);
        }
      }
      final pending = EcfPrintDocument.fromJson(noteJson(state: 'PENDING'));
      expect(pending.hasStamp, isFalse);
      final pdf = pdfread.PdfDocument(
        inputBytes: await buildEcfDocumentPdf(pending),
      );
      expect(
        pdfread.PdfTextExtractor(pdf).extractText(),
        isNot(contains('ABC123')),
      );
      pdf.dispose();
    },
  );
  testWidgets(
    'ticket action queries fresh fiscal data and uses the existing printer',
    (tester) async {
      final pending = Completer<EcfPrintDocument>();
      late _Printer printer;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ecfRepositoryProvider.overrideWithValue(
              _Repository(() => pending.future),
            ),
            unifiedTicketPrinterProvider.overrideWith(
              (ref) => printer = _Printer(ref),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: EcfDocumentPrintAction(documentId: 'synthetic-e34'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Imprimir ticket'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Ver PDF fiscal'),
            )
            .onPressed,
        isNull,
      );
      pending.complete(EcfPrintDocument.fromJson(noteJson()));
      await tester.pumpAndSettle();
      expect(printer.received!.ecf!.documentType, 'E34');
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );
  testWidgets('connection failure remains visible and allows retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfRepositoryProvider.overrideWithValue(
            _Repository(() async => throw StateError('Sin conexión')),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: EcfDocumentPrintAction(documentId: 'synthetic-e34'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Imprimir ticket'));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Imprimir ticket'),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.textContaining('Revisa la conexión'), findsOneWidget);
  });
  testWidgets('fiscal actions remain reachable on a narrow screen', (
    tester,
  ) async {
    final fonts = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-SemiBold.ttf'));
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    tester.view.physicalSize = const Size(280, 160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: boundary,
            child: const Scaffold(
              body: EcfDocumentPrintAction(documentId: 'synthetic-e34'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Imprimir ticket').hitTestable(), findsOneWidget);
    expect(find.text('Ver PDF fiscal').hitTestable(), findsOneWidget);
    final target = Platform.environment['FULLPOS_E34_PRINT_QA'];
    if (target != null) {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(target).create(recursive: true);
        await File(
          '$target/acciones-fiscales-mobile.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
