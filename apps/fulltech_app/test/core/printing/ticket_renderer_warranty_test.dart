import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final company = const CompanyInfo(name: 'FULLTECH, SRL');

  List<String> buildLines(String warrantyPolicy) {
    final layout = TicketLayoutConfig.fromPrinterSettings(
      PrinterSettingsModel(warrantyPolicy: warrantyPolicy),
    );
    return TicketRenderer(layout: layout, company: company).buildLines(
      TicketData.demo(),
    );
  }

  String normalizeJoined(List<String> lines) {
    return lines.map((line) => line.trim()).join(' ').replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  test('legacy text lines print POLITICA DE GARANTIA label when configured',
      () {
    const policy = 'La garantía cubre únicamente defectos de fabricación.';
    final lines = buildLines(policy);

    expect(lines.any((line) => line.contains('POLITICA DE GARANTIA')), isTrue);
    expect(normalizeJoined(lines).contains(policy), isTrue);
  });

  test('legacy text lines omit warranty when empty', () {
    final lines = buildLines('');

    expect(lines.any((line) => line.contains('POLITICA DE GARANTIA')), isFalse);
  });

  test('legacy text lines omit warranty when whitespace only', () {
    final lines = buildLines('   ');

    expect(lines.any((line) => line.contains('POLITICA DE GARANTIA')), isFalse);
  });

  test('legacy text lines wrap a long warranty instead of truncating it', () {
    final longPolicy =
        'La garantía cubre únicamente defectos de fabricación por un período '
        'de doce (12) meses a partir de la fecha de compra. No incluye daños '
        'por mal uso, caídas, humedad, descargas eléctricas ni alteraciones '
        'realizadas por personal no autorizado. Conserve su factura para '
        'hacer valida la garantía en nuestro establecimiento.';
    final lines = buildLines(longPolicy);

    expect(lines.any((line) => line.contains('POLITICA DE GARANTIA')), isTrue);
    expect(normalizeJoined(lines).contains(longPolicy), isTrue);
    expect(
      normalizeJoined(lines).contains('Conserve su factura para'),
      isTrue,
    );
  });

  test('notes and warranty can coexist without mixing labels', () {
    final layout = TicketLayoutConfig.fromPrinterSettings(
      PrinterSettingsModel(warrantyPolicy: 'Garantía oficial de la empresa.'),
    );
    final lines = TicketRenderer(
      layout: layout,
      company: company,
    ).buildLines(
      TicketData(
        ticketNumber: 'TEST-1',
        dateTime: DateTime(2026, 8, 20),
        client: const ClientInfo(name: 'Consumidor Final'),
        items: const [
          TicketItemData(name: 'PRODUCTO', qty: 1, unitPrice: 100, total: 100),
        ],
        total: 100,
        subtotal: 100,
        note: 'Entregar después de las 3:00 PM.',
      ),
    );

    final noteIndex = lines.indexWhere(
      (line) => line.contains('Entregar después de las 3:00 PM.'),
    );
    final warrantyIndex = lines.indexWhere(
      (line) => line.contains('POLITICA DE GARANTIA'),
    );
    expect(noteIndex, isNot(-1));
    expect(warrantyIndex, isNot(-1));
    // The note text comes before the warranty block.
    expect(noteIndex, lessThan(warrantyIndex));
    expect(
      normalizeJoined(lines).contains('Garantía oficial de la empresa.'),
      isTrue,
    );
  });
}
