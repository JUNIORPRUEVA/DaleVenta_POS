import '../models/company_info.dart';
import '../models/receipt_text_utils.dart';
import '../models/ticket_data.dart';

class ThermalReceiptViewModel {
  const ThermalReceiptViewModel({
    required this.ticketNumber,
    required this.dateTime,
    required this.documentTitle,
    required this.company,
    required this.items,
    required this.subtotal,
    required this.productDiscount,
    required this.generalDiscount,
    required this.taxableBase,
    required this.exemptAmount,
    required this.taxAmount,
    required this.total,
    required this.fiscalTaxEnabled,
    required this.taxIncluded,
    this.client,
    this.cashierName,
    this.paymentMethod,
    this.cashReceived,
    this.changeAmount,
    this.ncf,
    this.fiscalVoucherType,
    this.ncfExpirationDate,
    this.note,
    this.isCopy = false,
  });

  final String ticketNumber;
  final DateTime dateTime;
  final String documentTitle;
  final CompanyInfo company;
  final List<ThermalReceiptItemViewModel> items;
  final double subtotal;
  final double productDiscount;
  final double generalDiscount;
  final double taxableBase;
  final double exemptAmount;
  final double taxAmount;
  final double total;
  final bool fiscalTaxEnabled;
  final bool taxIncluded;
  final ThermalReceiptClientViewModel? client;
  final String? cashierName;
  final String? paymentMethod;
  final double? cashReceived;
  final double? changeAmount;
  final String? ncf;
  final String? fiscalVoucherType;
  final DateTime? ncfExpirationDate;
  final String? note;
  final bool isCopy;

  factory ThermalReceiptViewModel.fromTicketData({
    required TicketData data,
    required CompanyInfo company,
  }) {
    return ThermalReceiptViewModel(
      ticketNumber: data.ticketNumber,
      dateTime: data.dateTime,
      documentTitle: _titleFor(data),
      company: company,
      items: data.items
          .map(
            (item) => ThermalReceiptItemViewModel(
              name: item.name,
              qty: item.qty,
              unitPrice: item.unitPrice,
              total: item.total,
              discount: item.discount,
              taxableBase: item.taxableBase,
              exemptAmount: item.exemptAmount,
              taxAmount: item.taxAmount,
            ),
          )
          .toList(growable: false),
      subtotal: data.resolvedSubtotal,
      productDiscount: data.productDiscount,
      generalDiscount: data.generalDiscount,
      taxableBase: data.taxableBase,
      exemptAmount: data.exemptAmount,
      taxAmount: data.itbis,
      total: data.total,
      fiscalTaxEnabled: data.fiscalTaxEnabled,
      taxIncluded: data.taxIncluded,
      client: ThermalReceiptClientViewModel.fromClientInfo(data.client),
      cashierName: _cleanOrNull(data.cashierName),
      paymentMethod: _cleanOrNull(data.paymentMethod),
      cashReceived: data.cashReceived,
      changeAmount: data.changeAmount,
      ncf: _cleanOrNull(data.ncf),
      fiscalVoucherType: _cleanOrNull(data.fiscalVoucherType),
      ncfExpirationDate: data.ncfExpirationDate,
      note: _cleanOrNull(data.note),
      isCopy: data.isCopy,
    );
  }

  static String _titleFor(TicketData data) {
    return switch (data.type) {
      TicketType.refund => 'DEVOLUCION',
      TicketType.quote => 'COTIZACION',
      TicketType.credit => 'CREDITO',
      TicketType.copy => 'COPIA',
      _ => data.isCopy ? 'COPIA FACTURA' : 'FACTURA',
    };
  }

  static String? _cleanOrNull(String? value) {
    final clean = (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.isEmpty ? null : clean;
  }
}

class ThermalReceiptItemViewModel {
  const ThermalReceiptItemViewModel({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.total,
    required this.discount,
    required this.taxableBase,
    required this.exemptAmount,
    required this.taxAmount,
  });

  final String name;
  final double qty;
  final double unitPrice;
  final double total;
  final double discount;
  final double taxableBase;
  final double exemptAmount;
  final double taxAmount;

  String get qtyText => ReceiptTextUtils.qty(qty);
}

class ThermalReceiptClientViewModel {
  const ThermalReceiptClientViewModel({
    required this.name,
    this.phone,
    this.document,
  });

  final String name;
  final String? phone;
  final String? document;

  factory ThermalReceiptClientViewModel.fromClientInfo(ClientInfo? client) {
    final name = _clean(client?.name);
    return ThermalReceiptClientViewModel(
      name: name.isEmpty ? 'Consumidor Final' : name,
      phone: _cleanOrNull(client?.phone),
      document: _cleanOrNull(client?.document),
    );
  }

  static String _clean(String? value) {
    return (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _cleanOrNull(String? value) {
    final clean = _clean(value);
    return clean.isEmpty || clean == '-' ? null : clean;
  }
}
