import 'package:intl/intl.dart';

import '../../../modules/ventas/sales_models.dart';

enum TicketType { sale, quote, refund, credit, copy, custom }

class ClientInfo {
  const ClientInfo({this.name = '', this.phone = '', this.document = ''});

  final String name;
  final String phone;
  final String document;
}

class TicketItemData {
  const TicketItemData({
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.total,
    this.code,
    this.discount = 0,
  });

  final String name;
  final double qty;
  final double unitPrice;
  final double total;
  final String? code;
  final double discount;
}

class TicketData {
  const TicketData({
    required this.ticketNumber,
    required this.dateTime,
    required this.items,
    required this.total,
    this.type = TicketType.sale,
    this.client,
    this.cashierName,
    this.paymentMethod,
    this.subtotal,
    this.discount = 0,
    this.itbis = 0,
    this.note,
    this.isCopy = false,
    this.customLines,
  });

  final String ticketNumber;
  final DateTime dateTime;
  final List<TicketItemData> items;
  final double total;
  final TicketType type;
  final ClientInfo? client;
  final String? cashierName;
  final String? paymentMethod;
  final double? subtotal;
  final double discount;
  final double itbis;
  final String? note;
  final bool isCopy;
  final List<String>? customLines;

  double get resolvedSubtotal =>
      subtotal ?? items.fold(0.0, (sum, item) => sum + item.total);

  factory TicketData.fromSale(
    SaleModel sale, {
    List<SaleItemModel>? items,
    bool isCopy = false,
    String? paymentMethod,
    String? cashierNameOverride,
  }) {
    final List<SaleItemModel> saleItems = items ?? sale.items;
    final cashierName = (cashierNameOverride ?? sale.userName ?? '').trim();
    return TicketData(
      ticketNumber: _invoiceNumber(sale.id),
      dateTime: sale.saleDate ?? DateTime.now(),
      items: saleItems
          .map(
            (item) => TicketItemData(
              code: item.productId,
              name: item.productNameSnapshot,
              qty: item.qty,
              unitPrice: item.priceSoldUnit,
              total: item.subtotalSold,
            ),
          )
          .toList(growable: false),
      total: sale.totalSold,
      subtotal: saleItems.fold<double>(
        0,
        (sum, item) => sum + item.subtotalSold,
      ),
      client: ClientInfo(name: sale.customerName ?? 'Consumidor Final'),
      cashierName: cashierName.isEmpty ? 'Cajero' : cashierName,
      note: sale.note,
      type: sale.isDeleted ? TicketType.refund : TicketType.sale,
      isCopy: isCopy,
      paymentMethod: paymentMethod,
    );
  }

  factory TicketData.custom({
    required List<String> lines,
    required String ticketNumber,
  }) {
    return TicketData(
      ticketNumber: ticketNumber,
      dateTime: DateTime.now(),
      items: const [],
      total: 0,
      type: TicketType.custom,
      customLines: lines,
    );
  }

  factory TicketData.demo() {
    return TicketData(
      ticketNumber: 'TEST-${DateFormat('HHmmss').format(DateTime.now())}',
      dateTime: DateTime.now(),
      client: const ClientInfo(name: 'Consumidor Final'),
      cashierName: 'Caja',
      paymentMethod: 'Efectivo',
      items: const [
        TicketItemData(
          name: 'Producto de prueba',
          qty: 1,
          unitPrice: 150,
          total: 150,
        ),
        TicketItemData(
          name: 'Servicio tecnico',
          qty: 2,
          unitPrice: 75,
          total: 150,
        ),
      ],
      subtotal: 300,
      total: 300,
      note: 'Ticket de prueba',
    );
  }

  static String _invoiceNumber(String id) {
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) return digits.substring(digits.length - 8);
    final compact = id.replaceAll('-', '');
    if (compact.length >= 8) return compact.substring(0, 8).toUpperCase();
    return compact.toUpperCase();
  }
}
