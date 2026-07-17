import 'package:intl/intl.dart';

import 'company_info.dart';
import 'receipt_text_utils.dart';
import 'ticket_data.dart';
import 'ticket_layout_config.dart';

class TicketRenderer {
  const TicketRenderer({required this.layout, required this.company});

  final TicketLayoutConfig layout;
  final CompanyInfo company;

  List<String> buildLines(TicketData data) {
    final width = layout.printableChars;
    final lines = <String>[];
    final sep = ReceiptTextUtils.separator(width, layout.sectionSeparatorStyle);
    final leftPad = ' ' * layout.leftMargin;

    void add(String line) => lines.add('$leftPad$line');
    void blank() => lines.add('');

    for (var i = 0; i < layout.topMargin ~/ 4; i++) {
      blank();
    }

    if (data.customLines != null) {
      for (final line in data.customLines!) {
        add(ReceiptTextUtils.truncate(line, width));
      }
      for (var i = 0; i < layout.bottomMargin ~/ 4; i++) {
        blank();
      }
      return lines;
    }

    add(ReceiptTextUtils.align(company.name, width, layout.headerAlignment));
    if (layout.showBusinessData) {
      if (company.rnc.isNotEmpty) {
        add(
          ReceiptTextUtils.align(
            'RNC: ${company.rnc}',
            width,
            layout.headerAlignment,
          ),
        );
      }
      if (company.phone.isNotEmpty) {
        add(
          ReceiptTextUtils.align(
            'Tel: ${company.phone}',
            width,
            layout.headerAlignment,
          ),
        );
      }
      if (company.address.isNotEmpty) {
        for (final line in ReceiptTextUtils.wrap(company.address, width)) {
          add(ReceiptTextUtils.align(line, width, layout.headerAlignment));
        }
      }
    }
    if (layout.headerExtra.trim().isNotEmpty) {
      for (final line in ReceiptTextUtils.wrap(layout.headerExtra, width)) {
        add(ReceiptTextUtils.align(line, width, layout.headerAlignment));
      }
    }

    blank();
    final title = switch (data.type) {
      TicketType.refund => 'DEVOLUCION',
      TicketType.quote => 'COTIZACION',
      TicketType.credit => 'CREDITO',
      TicketType.copy => 'COPIA',
      _ => data.isCopy ? 'COPIA FACTURA' : 'FACTURA',
    };
    add(ReceiptTextUtils.center(title, width));
    add(sep);
    if (layout.showCode) {
      add(ReceiptTextUtils.leftRight('No.', data.ticketNumber, width));
    }
    if (layout.showDatetime) {
      add(
        ReceiptTextUtils.leftRight(
          'Fecha',
          DateFormat('dd/MM/yyyy HH:mm').format(data.dateTime),
          width,
        ),
      );
    }
    if (layout.showCashier && (data.cashierName ?? '').trim().isNotEmpty) {
      add(
        ReceiptTextUtils.leftRight('Cajero', data.cashierName!.trim(), width),
      );
    }
    if (layout.showClient && data.client != null) {
      final name = data.client!.name.trim();
      if (name.isNotEmpty) {
        add(ReceiptTextUtils.leftRight('Cliente', name, width));
      }
      final doc = data.client!.document.trim();
      if (doc.isNotEmpty) {
        add(ReceiptTextUtils.leftRight('Doc.', doc, width));
      }
      final phone = data.client!.phone.trim();
      if (phone.isNotEmpty) {
        add(ReceiptTextUtils.leftRight('Tel.', phone, width));
      }
    }
    add(sep);

    add(ReceiptTextUtils.leftRight('DESCRIPCION', 'TOTAL', width));
    for (final item in data.items) {
      final total = ReceiptTextUtils.money(item.total);
      for (final line in ReceiptTextUtils.wrap(item.name, width)) {
        add(ReceiptTextUtils.truncate(line, width));
      }
      final qtyPrice =
          '${ReceiptTextUtils.qty(item.qty)} x ${ReceiptTextUtils.money(item.unitPrice)}';
      add(ReceiptTextUtils.leftRight(qtyPrice, total, width));
      if (layout.showDiscounts && item.discount > 0) {
        add(
          ReceiptTextUtils.leftRight(
            'Desc.',
            '-${ReceiptTextUtils.money(item.discount)}',
            width,
          ),
        );
      }
    }

    add(sep);
    if (layout.showSubtotalItbisTotal) {
      add(
        ReceiptTextUtils.leftRight(
          'Subtotal',
          ReceiptTextUtils.money(data.resolvedSubtotal),
          width,
        ),
      );
      if (layout.showDiscounts && data.discount > 0) {
        add(
          ReceiptTextUtils.leftRight(
            'Descuento',
            '-${ReceiptTextUtils.money(data.discount)}',
            width,
          ),
        );
      }
      if (layout.showItbis && data.itbis > 0) {
        add(
          ReceiptTextUtils.leftRight(
            'ITBIS',
            ReceiptTextUtils.money(data.itbis),
            width,
          ),
        );
      }
    }
    add(
      ReceiptTextUtils.leftRight(
        'TOTAL',
        ReceiptTextUtils.money(data.total),
        width,
      ),
    );
    if (layout.showPaymentMethod &&
        (data.paymentMethod ?? '').trim().isNotEmpty) {
      add(
        ReceiptTextUtils.leftRight('Pago', data.paymentMethod!.trim(), width),
      );
    }
    if ((data.note ?? '').trim().isNotEmpty) {
      blank();
      for (final line in ReceiptTextUtils.wrap(data.note!, width)) {
        add(line);
      }
    }

    if (layout.warrantyPolicy.trim().isNotEmpty) {
      blank();
      add(sep);
      for (final line in ReceiptTextUtils.wrap(layout.warrantyPolicy, width)) {
        add(line);
      }
    }
    if (layout.footerMessage.trim().isNotEmpty) {
      blank();
      for (final line in ReceiptTextUtils.wrap(layout.footerMessage, width)) {
        add(ReceiptTextUtils.center(line, width));
      }
    }

    for (var i = 0; i < layout.bottomMargin ~/ 4; i++) {
      blank();
    }
    return lines;
  }
}
