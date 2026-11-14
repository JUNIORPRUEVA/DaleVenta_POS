import 'package:intl/intl.dart';
import '../../../features/ecf/ecf_print_document.dart';

import '../../time/business_time.dart';
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
    this.taxableBase = 0,
    this.taxAmount = 0,
    this.exemptAmount = 0,
    this.taxExempt = false,
  });

  final String name;
  final double qty;
  final double unitPrice;
  final double total;
  final String? code;
  final double discount;
  final double taxableBase;
  final double taxAmount;
  final double exemptAmount;
  final bool taxExempt;
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
    this.cashReceived,
    this.changeAmount,
    this.subtotal,
    this.discount = 0,
    this.productDiscount = 0,
    this.generalDiscount = 0,
    this.itbis = 0,
    this.taxableBase = 0,
    this.exemptAmount = 0,
    this.fiscalTaxEnabled = false,
    this.taxIncluded = false,
    this.ncf,
    this.fiscalVoucherType,
    this.ncfExpirationDate,
    this.issuerName,
    this.issuerRnc,
    this.issuerPhone,
    this.issuerAddress,
    this.note,
    this.isCopy = false,
    this.customLines,
    this.ecf,
  });

  final String ticketNumber;
  final EcfPrintDocument? ecf;
  final DateTime dateTime;
  final List<TicketItemData> items;
  final double total;
  final TicketType type;
  final ClientInfo? client;
  final String? cashierName;
  final String? paymentMethod;

  /// Efectivo REAL entregado por el cliente (tender). Nulo = tender
  /// desconocido/no almacenado (ventas legadas). 0 = no hubo efectivo.
  final double? cashReceived;

  /// Devuelta entregada al cliente. Nulo cuando el tender es desconocido.
  final double? changeAmount;

  final double? subtotal;
  final double discount;
  final double productDiscount;
  final double generalDiscount;
  final double itbis;
  final double taxableBase;
  final double exemptAmount;
  final bool fiscalTaxEnabled;
  final bool taxIncluded;
  final String? ncf;
  final String? fiscalVoucherType;
  final DateTime? ncfExpirationDate;
  final String? issuerName;
  final String? issuerRnc;
  final String? issuerPhone;
  final String? issuerAddress;
  final String? note;
  final bool isCopy;
  final List<String>? customLines;

  double get resolvedSubtotal =>
      subtotal ?? items.fold(0.0, (sum, item) => sum + item.total);

  /// Print the frozen fiscal document, including manual E34 notes, through
  /// the same printer path as sales. No sale or inventory record is created.
  factory TicketData.fromEcf(EcfPrintDocument document) {
    if (document.lines.isEmpty ||
        document.currency != 'DOP' ||
        [
          document.subtotal,
          document.taxableBase,
          document.exemptAmount,
          document.itbisAmount,
          document.discountAmount,
        ].any((value) => value == null) ||
        !document.matchesTotal(
          document.lines.fold(0, (sum, line) => sum + line.total),
        )) {
      throw StateError(
        'El detalle fiscal está incompleto o no coincide con el total. Revisa el comprobante.',
      );
    }
    return TicketData(
      ticketNumber: document.encf,
      dateTime: DateTime.parse(document.issueDate),
      ecf: document,
      type: document.documentType == 'E34'
          ? TicketType.credit
          : TicketType.copy,
      isCopy: true,
      fiscalTaxEnabled: true,
      taxIncluded: false,
      ncf: document.encf,
      fiscalVoucherType: document.documentType,
      issuerName: document.issuerName,
      issuerRnc: document.issuerRnc,
      issuerAddress: document.issuerAddress,
      client: ClientInfo(
        name: document.buyerName ?? '',
        document: document.buyerRnc ?? '',
      ),
      total: double.parse(document.total),
      // Fiscal subtotal is net of discounts; the ticket has a separate
      // negative discount row, so present its subtotal before that deduction.
      subtotal:
          double.parse(document.subtotal!) +
          double.parse(document.discountAmount!),
      taxableBase: double.parse(document.taxableBase!),
      exemptAmount: double.parse(document.exemptAmount!),
      itbis: double.parse(document.itbisAmount!),
      discount: double.parse(document.discountAmount!),
      productDiscount: double.parse(document.discountAmount!),
      items: document.lines
          .map(
            (line) => TicketItemData(
              name:
                  '${line.taxExempt ? 'E ' : ''}${line.name}${line.unitOfMeasure == null ? '' : ' (UM ${line.unitOfMeasure})'}',
              qty: line.quantity,
              unitPrice: line.unitPrice,
              total: line.total,
              taxableBase: line.taxableBase,
              exemptAmount: line.exemptAmount,
              taxAmount: line.taxAmount,
              discount: line.discount,
              taxExempt: line.taxExempt,
            ),
          )
          .toList(growable: false),
    );
  }

  factory TicketData.fromSale(
    SaleModel sale, {
    List<SaleItemModel>? items,
    bool isCopy = false,
    String? paymentMethod,
    String? cashierNameOverride,
    EcfPrintDocument? ecf,
  }) {
    final List<SaleItemModel> saleItems = items ?? sale.items;
    if (ecf != null && !ecf.matchesTotal(sale.totalSold)) {
      throw StateError(
        'El importe de la venta no coincide con su comprobante electrónico. Revisa el documento antes de imprimir.',
      );
    }
    final cashierName = resolveCashierDisplayName(
      cashierNameOverride: cashierNameOverride,
      saleCashierName: sale.userName,
    );
    final productDiscount = saleItems.fold<double>(
      0,
      (sum, item) => sum + item.lineDiscountAmount,
    );
    final generalDiscount = (sale.discountAmount - productDiscount)
        .clamp(0, double.infinity)
        .toDouble();
    return TicketData(
      ecf: ecf,
      ticketNumber: _invoiceNumber(sale.id),
      dateTime: toBusinessTime(sale.saleDate ?? DateTime.now()),
      items: saleItems
          .map(
            (item) => TicketItemData(
              code: item.productId,
              name: ecf == null
                  ? item.productNameSnapshot
                  : '${item.taxExempt ? 'E ' : ''}${item.productNameSnapshot} (${item.unitNameSnapshot})',
              qty: item.qty,
              unitPrice: item.priceSoldUnit,
              total: item.subtotalSold,
              taxableBase: item.taxableBase,
              taxAmount: item.taxAmount,
              exemptAmount: item.exemptAmount,
              taxExempt: item.taxExempt,
              discount: item.lineDiscountAmount,
            ),
          )
          .toList(growable: false),
      total: sale.totalSold,
      subtotal: sale.fiscalTaxEnabled
          ? sale.taxableBase + sale.exemptAmount
          : saleItems.fold<double>(0, (sum, item) => sum + item.subtotalSold),
      itbis: sale.taxAmount,
      taxableBase: sale.taxableBase,
      exemptAmount: sale.exemptAmount,
      fiscalTaxEnabled: sale.fiscalTaxEnabled,
      discount: sale.discountAmount,
      productDiscount: productDiscount,
      generalDiscount: generalDiscount,
      taxIncluded: sale.fiscalPriceMode == 'TAX_INCLUDED',
      ncf: ecf?.encf ?? sale.ncf,
      fiscalVoucherType: sale.isExplicitNormal ? null : ecf?.documentType ?? sale.fiscalVoucherType,
      ncfExpirationDate: ecf != null
          ? DateTime.tryParse(ecf.expiresAt ?? '')
          : sale.ncfExpirationDate,
      issuerName: ecf?.issuerName ?? sale.issuerNameSnapshot,
      issuerRnc: ecf?.issuerRnc ?? sale.issuerTaxIdSnapshot,
      issuerPhone: sale.issuerPhoneSnapshot,
      issuerAddress: ecf?.issuerAddress ?? sale.issuerAddressSnapshot,
      client: ClientInfo(
        name:
            ecf?.buyerName ??
            sale.fiscalCustomerName ??
            sale.customerName ??
            'Consumidor Final',
        phone: sale.customerPhoneSnapshot ?? sale.customerPhone ?? '',
        document: ecf?.buyerRnc ?? sale.fiscalCustomerTaxId ?? '',
      ),
      cashierName: cashierName,
      note: sale.note,
      type: sale.isDeleted ? TicketType.refund : TicketType.sale,
      isCopy: isCopy,
      paymentMethod: paymentMethod ?? _paymentDescription(sale),
      cashReceived: sale.cashReceived,
      changeAmount: sale.changeAmount,
    );
  }

  factory TicketData.custom({
    required List<String> lines,
    required String ticketNumber,
  }) {
    return TicketData(
      ticketNumber: ticketNumber,
      dateTime: businessNow(),
      items: const [],
      total: 0,
      type: TicketType.custom,
      customLines: lines,
    );
  }

  factory TicketData.demo() {
    return TicketData(
      ticketNumber: 'TEST-${DateFormat('HHmmss').format(businessNow())}',
      dateTime: businessNow(),
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
      cashReceived: 300,
      changeAmount: 0,
    );
  }

  /// True cuando hay un tender de efectivo conocido y mayor que cero
  /// (permite imprimir EFECTIVO RECIBIDO / DEVUELTA sin fabricar datos en
  /// ventas legadas con tender desconocido).
  bool get hasCashTender => (cashReceived ?? 0) > 0;

  static String _invoiceNumber(String id) {
    final digits = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) return digits.substring(digits.length - 8);
    final compact = id.replaceAll('-', '');
    if (compact.length >= 8) return compact.substring(0, 8).toUpperCase();
    return compact.toUpperCase();
  }

  /// Resolves the cashier label from sale snapshots only.
  ///
  /// Priority:
  /// 1. Explicit override used by callers that already loaded the sale snapshot.
  /// 2. The persisted sale user/cashier name parsed into [SaleModel.userName].
  /// 3. A stable fallback when historical data has no valid cashier snapshot.
  static String resolveCashierDisplayName({
    required String? cashierNameOverride,
    required String? saleCashierName,
  }) {
    final override = (cashierNameOverride ?? '').trim();
    if (_isUsableCashierName(override)) return override;
    final saleName = (saleCashierName ?? '').trim();
    if (_isUsableCashierName(saleName)) return saleName;
    return 'No disponible';
  }

  static bool _isUsableCashierName(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isNotEmpty && normalized != 'pendiente de sincronizar';
  }

  static String _paymentDescription(SaleModel sale) {
    final cash = sale.paymentCashAmount;
    final transfer = sale.paymentTransferAmount;
    final parts = <String>[];
    if (cash > 0) {
      parts.add('Efectivo ${_money(cash)}');
    }
    if (transfer > 0) {
      parts.add('Transferencia ${_money(transfer)}');
    }
    if (parts.isNotEmpty) return parts.join(' + ');

    return switch (sale.paymentMethod.trim()) {
      'cash' => 'Efectivo',
      'transfer' => 'Transferencia',
      'mixed' => 'Mixto',
      'credit' => 'Credito',
      _ => sale.paymentMethod.trim(),
    };
  }

  static String _money(num value) {
    final formatted = NumberFormat('#,##0.00', 'en_US').format(value);
    return 'RD\$ $formatted';
  }
}
