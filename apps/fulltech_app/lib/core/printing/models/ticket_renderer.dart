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
    final compact58 = layout.paperWidthMm == 58;
    final width = compact58 ? 30 : layout.printableChars;
    final lines = <String>[];
    final sep = ReceiptTextUtils.separator(
      width,
      compact58 ? 'dotted' : layout.sectionSeparatorStyle,
    );
    final leftPad = compact58 ? '' : ' ' * layout.leftMargin;

    void add(String line) => lines.add('$leftPad$line');
    void blank() => lines.add('');
    void addMoneyLine(String label, double value) {
      add(
        ReceiptTextUtils.leftRight(label, ReceiptTextUtils.money(value), width),
      );
    }

    final companyName = (data.issuerName ?? '').trim().isNotEmpty
        ? data.issuerName!.trim()
        : company.name;
    final companyRnc = (data.issuerRnc ?? '').trim().isNotEmpty
        ? data.issuerRnc!.trim()
        : company.rnc;
    final companyPhone = (data.issuerPhone ?? '').trim().isNotEmpty
        ? data.issuerPhone!.trim()
        : company.phone;
    final companyAddress = (data.issuerAddress ?? '').trim().isNotEmpty
        ? data.issuerAddress!.trim()
        : company.address;

    bool isFiscalTicket() {
      final voucher = (data.fiscalVoucherType ?? '').trim().toUpperCase();
      return (voucher == 'B01' || voucher == 'B02') &&
          (data.ncf ?? '').trim().isNotEmpty;
    }

    bool showFiscalTotals() {
      return layout.showItbis &&
          (data.fiscalTaxEnabled ||
              data.taxableBase > 0 ||
              data.exemptAmount > 0 ||
              data.itbis > 0) &&
          (data.taxableBase > 0 || data.exemptAmount > 0 || data.itbis > 0);
    }

    String fiscalSubtitle() {
      final voucher = (data.fiscalVoucherType ?? '').trim().toUpperCase();
      return switch (voucher) {
        'B01' => 'B01 - CREDITO FISCAL',
        'B02' => 'B02 - CONSUMO',
        _ => '',
      };
    }

    final topBlanks = compact58 ? 0 : layout.topMargin ~/ 4;
    for (var i = 0; i < topBlanks; i++) {
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

    add(
      compact58
          ? ReceiptTextUtils.center(companyName, width)
          : ReceiptTextUtils.align(companyName, width, layout.headerAlignment),
    );
    if (layout.showBusinessData) {
      if (companyRnc.isNotEmpty) {
        add(
          compact58
              ? ReceiptTextUtils.center('RNC: $companyRnc', width)
              : ReceiptTextUtils.align(
                  'RNC: $companyRnc',
                  width,
                  layout.headerAlignment,
                ),
        );
      }
      if (companyPhone.isNotEmpty) {
        add(
          compact58
              ? ReceiptTextUtils.center('Tel: $companyPhone', width)
              : ReceiptTextUtils.align(
                  'Tel: $companyPhone',
                  width,
                  layout.headerAlignment,
                ),
        );
      }
      if (companyAddress.isNotEmpty) {
        for (final line in ReceiptTextUtils.wrap(companyAddress, width)) {
          add(
            compact58
                ? ReceiptTextUtils.center(line, width)
                : ReceiptTextUtils.align(line, width, layout.headerAlignment),
          );
        }
      }
    }
    if (layout.headerExtra.trim().isNotEmpty) {
      for (final line in ReceiptTextUtils.wrap(layout.headerExtra, width)) {
        add(ReceiptTextUtils.align(line, width, layout.headerAlignment));
      }
    }

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
      if (isFiscalTicket() && doc.isNotEmpty) {
        add(ReceiptTextUtils.leftRight('Doc.', doc, width));
      }
      final phone = data.client!.phone.trim();
      if (phone.isNotEmpty) {
        add(ReceiptTextUtils.leftRight('Tel.', phone, width));
      }
    }
    if (isFiscalTicket()) {
      add(sep);
      add(ReceiptTextUtils.truncate(fiscalSubtitle(), width));
      add(ReceiptTextUtils.leftRight('NCF', data.ncf!.trim(), width));
      final fiscalName = (data.client?.name ?? '').trim();
      if (fiscalName.isNotEmpty) {
        add(ReceiptTextUtils.leftRight('CLIENTE', fiscalName, width));
      }
      final fiscalDoc = (data.client?.document ?? '').trim();
      if (fiscalDoc.isNotEmpty) {
        add(ReceiptTextUtils.leftRight('RNC', fiscalDoc, width));
      }
    }
    add(sep);

    add(ReceiptTextUtils.leftRight('PRODUCTO', 'IMPORTE', width));
    if (compact58) blank();
    for (final item in data.items) {
      final total = ReceiptTextUtils.money(item.total);
      final qtyPrice =
          '${ReceiptTextUtils.qty(item.qty)} x ${ReceiptTextUtils.money(item.unitPrice)}';
      if (compact58) {
        final amountWidth = total.length;
        final productWidth = (width - amountWidth - 1).clamp(8, width);
        final nameLines = ReceiptTextUtils.wrap(item.name, productWidth);
        final firstName = nameLines.isEmpty ? '' : nameLines.first;
        add(ReceiptTextUtils.leftRight(firstName, total, width));
        for (final line in nameLines.skip(1).take(1)) {
          add(ReceiptTextUtils.truncate(line, width));
        }
        add(ReceiptTextUtils.truncate(qtyPrice, width));
      } else {
        for (final line in ReceiptTextUtils.wrap(item.name, width)) {
          add(ReceiptTextUtils.truncate(line, width));
        }
        add(ReceiptTextUtils.leftRight(qtyPrice, total, width));
      }
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
      addMoneyLine('Subtotal', data.resolvedSubtotal);
      if (layout.showDiscounts) {
        if (data.productDiscount > 0) {
          add(
            ReceiptTextUtils.leftRight(
              'Desc. productos',
              '-${ReceiptTextUtils.money(data.productDiscount)}',
              width,
            ),
          );
        }
        if (data.generalDiscount > 0) {
          add(
            ReceiptTextUtils.leftRight(
              'Desc. general',
              '-${ReceiptTextUtils.money(data.generalDiscount)}',
              width,
            ),
          );
        }
        if (data.productDiscount <= 0 &&
            data.generalDiscount <= 0 &&
            data.discount > 0) {
          add(
            ReceiptTextUtils.leftRight(
              'Descuento',
              '-${ReceiptTextUtils.money(data.discount)}',
              width,
            ),
          );
        }
      }
      if (showFiscalTotals()) {
        if (data.taxIncluded && data.itbis > 0) {
          add('ITBIS incluido');
        }
        if (data.exemptAmount > 0) {
          addMoneyLine('Monto exento', data.exemptAmount);
        }
        if (data.taxableBase > 0) {
          addMoneyLine('Monto gravado', data.taxableBase);
        }
        if (data.itbis > 0) {
          addMoneyLine('ITBIS', data.itbis);
        }
      }
    }
    addMoneyLine('TOTAL', data.total);
    if (layout.showPaymentMethod &&
        (data.paymentMethod ?? '').trim().isNotEmpty) {
      add(
        ReceiptTextUtils.leftRight('Pago', data.paymentMethod!.trim(), width),
      );
    }
    if ((data.note ?? '').trim().isNotEmpty) {
      if (!compact58) blank();
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
      if (!compact58) blank();
      for (final line in ReceiptTextUtils.wrap(layout.footerMessage, width)) {
        add(ReceiptTextUtils.center(line, width));
      }
    }

    final bottomBlanks = compact58 ? 0 : layout.bottomMargin ~/ 4;
    for (var i = 0; i < bottomBlanks; i++) {
      blank();
    }
    return lines;
  }
}
