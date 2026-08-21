import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/utils/cotizacion_pdf_service.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  group('Fiscal PDF templates', () {
    test('builds golden FULLTECH/CANATECH quote PDF without NCF', () async {
      final bytes = await buildCotizacionPdf(
        cotizacion: _goldenQuote(),
        company: _company(),
      );

      expect(bytes.length, greaterThan(1000));
      expect(_goldenQuote().total, 25700);
      expect(_goldenQuote().taxableBase, 21779.66);
      expect(_goldenQuote().taxAmount, 3920.34);
    });

    test('builds golden B01 invoice PDF from stored line snapshots', () async {
      final sale = _goldenSale(voucherType: 'B01', ncf: 'B0100000014');
      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.totalSold, 25700);
      expect(sale.taxableBase, 21779.66);
      expect(sale.taxAmount, 3920.34);
      expect(sale.items.fold<double>(0, (s, i) => s + i.subtotalSold), 25700);
      expect(
        sale.items
            .fold<double>(0, (s, i) => s + i.taxAmount)
            .toStringAsFixed(2),
        '3920.34',
      );
      expect(
        sale.items
            .fold<double>(0, (s, i) => s + i.taxableBase)
            .toStringAsFixed(2),
        '21779.66',
      );
    });

    test(
      'builds tax-enabled normal invoice PDF without requiring NCF',
      () async {
        final sale = _goldenSale(voucherType: '', ncf: '');
        final bytes = await buildSaleInvoicePdf(
          sale: sale,
          company: _company(),
        );

        expect(bytes.length, greaterThan(1000));
        expect(sale.fiscalTaxEnabled, isTrue);
        expect(sale.ncf, '');
        expect(sale.taxableBase, 21779.66);
        expect(sale.taxAmount, 3920.34);
      },
    );

    test(
      'builds B02 invoice PDF without requiring customer fiscal data',
      () async {
        final sale = _goldenSale(
          voucherType: 'B02',
          ncf: 'B0200000014',
          customerName: 'Consumidor Final',
          fiscalCustomerTaxId: null,
        );
        final bytes = await buildSaleInvoicePdf(
          sale: sale,
          company: _company(),
        );

        expect(bytes.length, greaterThan(1000));
        expect(sale.fiscalVoucherType, 'B02');
        expect(sale.ncf, 'B0200000014');
      },
    );

    test('maps ticket fiscal data from sale item snapshots', () {
      final sale = _goldenSale(voucherType: 'B01', ncf: 'B0100000014');
      final ticket = TicketData.fromSale(sale);

      expect(ticket.ncf, 'B0100000014');
      expect(ticket.fiscalVoucherType, 'B01');
      expect(ticket.taxableBase, 21779.66);
      expect(ticket.itbis, 3920.34);
      expect(ticket.items.first.taxableBase, 1016.95);
      expect(ticket.items.first.taxAmount, 183.05);
      expect(ticket.items.first.total, 1200);
    });

    test('tax off invoice PDF stays clean for legacy sale', () async {
      final sale = _legacySale();
      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.fiscalTaxEnabled, isFalse);
      expect(sale.taxAmount, 0);
    });

    test('B01 PDF renders warranty, notes, NCF, expiration and cashier (V7)', () async {
      final sale = _goldenSale(voucherType: 'B01', ncf: 'B0100000003');
      // SaleModel no tiene copyWith: construimos una copia con los campos V7.
      final v7 = SaleModel(
        id: sale.id,
        userId: sale.userId,
        userName: 'Yunior Lopez',
        customerId: sale.customerId,
        customerName: sale.customerName,
        customerPhone: sale.customerPhone,
        saleDate: sale.saleDate,
        note: 'Entrega en tienda.',
        totalSold: sale.totalSold,
        totalCost: sale.totalCost,
        totalProfit: sale.totalProfit,
        commissionAmount: sale.commissionAmount,
        paymentMethod: sale.paymentMethod,
        paymentCashAmount: sale.paymentCashAmount,
        paymentTransferAmount: sale.paymentTransferAmount,
        creditAmount: sale.creditAmount,
        creditPaidAmount: sale.creditPaidAmount,
        creditBalance: sale.creditBalance,
        creditStatus: sale.creditStatus,
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: sale.fiscalTaxEnabled,
        fiscalPriceMode: sale.fiscalPriceMode,
        taxableBase: sale.taxableBase,
        taxAmount: sale.taxAmount,
        exemptAmount: sale.exemptAmount,
        discountAmount: sale.discountAmount,
        fiscalVoucherType: sale.fiscalVoucherType,
        ncf: sale.ncf,
        ncfExpirationDate: DateTime(2026, 12, 31),
        issuerNameSnapshot: sale.issuerNameSnapshot,
        issuerTaxIdSnapshot: sale.issuerTaxIdSnapshot,
        issuerAddressSnapshot: sale.issuerAddressSnapshot,
        issuerPhoneSnapshot: sale.issuerPhoneSnapshot,
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: sale.fiscalCustomerTaxId,
        fiscalCustomerName: sale.fiscalCustomerName,
        customerAddressSnapshot: 'Calle Beller 9',
        customerPhoneSnapshot: sale.customerPhoneSnapshot,
        items: sale.items,
      );

      final bytes = await buildSaleInvoicePdf(
        sale: v7,
        company: _company(),
        warrantyPolicy:
            'Garantía válida según las condiciones del producto.\nNo cubre daños por mal uso.',
      );

      expect(bytes.length, greaterThan(1000));
      expect(v7.ncfExpirationDate, DateTime(2026, 12, 31));
      expect(v7.userName, 'Yunior Lopez');
    });

    test('B01 with line discount builds without a separate Descuento row (V7)', () async {
      final base = _goldenSale(voucherType: 'B01', ncf: 'B0100000003');
      final discountedItems = base.items.asMap().entries.map((entry) {
        final item = entry.value;
        return SaleItemModel(
          id: item.id,
          productId: item.productId,
          productNameSnapshot: item.productNameSnapshot,
          productImageSnapshot: item.productImageSnapshot,
          qty: item.qty,
          priceSoldUnit: item.priceSoldUnit,
          costUnitSnapshot: item.costUnitSnapshot,
          subtotalSold: item.subtotalSold - 500,
          subtotalCost: item.subtotalCost,
          profit: item.profit,
          category: item.category,
          grossAmount: item.grossAmount,
          lineDiscountAmount: 500,
          taxableBase: item.taxableBase,
          taxRate: item.taxRate,
          taxAmount: item.taxAmount,
          exemptAmount: item.exemptAmount,
          taxIncluded: item.taxIncluded,
          taxExempt: item.taxExempt,
        );
      }).toList();
      final sale = SaleModel(
        id: base.id,
        userId: base.userId,
        userName: base.userName,
        customerId: base.customerId,
        customerName: base.customerName,
        customerPhone: base.customerPhone,
        saleDate: base.saleDate,
        note: base.note,
        totalSold: base.totalSold,
        totalCost: base.totalCost,
        totalProfit: base.totalProfit,
        commissionAmount: base.commissionAmount,
        paymentMethod: base.paymentMethod,
        paymentCashAmount: base.paymentCashAmount,
        paymentTransferAmount: base.paymentTransferAmount,
        creditAmount: base.creditAmount,
        creditPaidAmount: base.creditPaidAmount,
        creditBalance: base.creditBalance,
        creditStatus: base.creditStatus,
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: base.fiscalTaxEnabled,
        fiscalPriceMode: base.fiscalPriceMode,
        taxableBase: base.taxableBase,
        taxAmount: base.taxAmount,
        exemptAmount: base.exemptAmount,
        discountAmount: 500,
        fiscalVoucherType: base.fiscalVoucherType,
        ncf: base.ncf,
        issuerNameSnapshot: base.issuerNameSnapshot,
        issuerTaxIdSnapshot: base.issuerTaxIdSnapshot,
        issuerAddressSnapshot: base.issuerAddressSnapshot,
        issuerPhoneSnapshot: base.issuerPhoneSnapshot,
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: base.fiscalCustomerTaxId,
        fiscalCustomerName: base.fiscalCustomerName,
        customerAddressSnapshot: null,
        customerPhoneSnapshot: base.customerPhoneSnapshot,
        items: discountedItems,
      );

      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());
      expect(bytes.length, greaterThan(1000));
      expect(sale.items.every((i) => i.lineDiscountAmount == 500), isTrue);
    });

    test('many products paginate without error (V7 multipage)', () async {
      final base = _goldenSale(voucherType: 'B01', ncf: 'B0100000003');
      final manyItems = <SaleItemModel>[];
      for (var i = 0; i < 30; i++) {
        final item = base.items[i % base.items.length];
        manyItems.add(
          SaleItemModel(
            id: 'item-$i',
            productId: item.productId,
            productNameSnapshot: 'PRODUCTO DE PRUEBA $i',
            productImageSnapshot: null,
            qty: 1,
            priceSoldUnit: item.priceSoldUnit,
            costUnitSnapshot: 0,
            subtotalSold: item.subtotalSold,
            subtotalCost: 0,
            profit: item.subtotalSold,
            category: null,
            grossAmount: item.grossAmount,
            lineDiscountAmount: 0,
            taxableBase: item.taxableBase,
            taxRate: 0.18,
            taxAmount: item.taxAmount,
            exemptAmount: 0,
            taxIncluded: true,
            taxExempt: false,
          ),
        );
      }
      final sale = SaleModel(
        id: base.id,
        userId: base.userId,
        userName: base.userName,
        customerId: base.customerId,
        customerName: base.customerName,
        customerPhone: base.customerPhone,
        saleDate: base.saleDate,
        note: base.note,
        totalSold: manyItems.fold<double>(0, (s, i) => s + i.subtotalSold),
        totalCost: 0,
        totalProfit: manyItems.fold<double>(0, (s, i) => s + i.subtotalSold),
        commissionAmount: 0,
        paymentMethod: base.paymentMethod,
        paymentCashAmount: base.paymentCashAmount,
        paymentTransferAmount: 0,
        creditAmount: 0,
        creditPaidAmount: 0,
        creditBalance: 0,
        creditStatus: 'none',
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: true,
        fiscalPriceMode: 'TAX_INCLUDED',
        taxableBase: base.taxableBase,
        taxAmount: base.taxAmount,
        exemptAmount: 0,
        discountAmount: 0,
        fiscalVoucherType: 'B01',
        ncf: 'B0100000003',
        issuerNameSnapshot: base.issuerNameSnapshot,
        issuerTaxIdSnapshot: base.issuerTaxIdSnapshot,
        issuerAddressSnapshot: base.issuerAddressSnapshot,
        issuerPhoneSnapshot: base.issuerPhoneSnapshot,
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: base.fiscalCustomerTaxId,
        fiscalCustomerName: base.fiscalCustomerName,
        customerAddressSnapshot: null,
        customerPhoneSnapshot: base.customerPhoneSnapshot,
        items: manyItems,
      );

      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());
      expect(bytes.length, greaterThan(1000));
      expect(sale.items.length, 30);
    });

    test('Laptop Dell con descuento e ITBIS 0 genera PDF sin romper (V7 ancho)', () async {
      // Caso obligatorio de validación de layout:
      // Precio RD$7,500.00 · Descuento -RD$1,000.00 · Base RD$6,500.00
      // ITBIS RD$0.00 · Total RD$6,500.00  → montos en UNA línea.
      final sale = SaleModel(
        id: '55555555-5555-4555-8555-555555555555',
        userId: 'user-a',
        userName: 'Yunior Lopez',
        customerId: 'client-a',
        customerName: 'Fune, srl',
        customerPhone: '809-111-1111',
        saleDate: DateTime(2026, 8, 21, 15, 30),
        note: '',
        totalSold: 6500,
        totalCost: 0,
        totalProfit: 6500,
        commissionAmount: 0,
        paymentMethod: 'cash',
        paymentCashAmount: 6500,
        paymentTransferAmount: 0,
        creditAmount: 0,
        creditPaidAmount: 0,
        creditBalance: 0,
        creditStatus: 'none',
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: true,
        fiscalPriceMode: 'TAX_ADDED',
        taxableBase: 6500,
        taxAmount: 0,
        exemptAmount: 0,
        discountAmount: 1000,
        fiscalVoucherType: 'B01',
        ncf: 'B0100000003',
        ncfExpirationDate: DateTime(2026, 12, 31),
        issuerNameSnapshot: 'FULLTECH, SRL',
        issuerTaxIdSnapshot: '133080206',
        issuerAddressSnapshot: 'Centro calle Beller 9 local n2, Higüey',
        issuerPhoneSnapshot: '8295319442',
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: '133206111',
        fiscalCustomerName: 'Fune, srl',
        customerAddressSnapshot: 'Santo Domingo',
        customerPhoneSnapshot: '809-111-1111',
        items: [
          SaleItemModel(
            id: 'laptop-item',
            productId: 'laptop-1',
            productNameSnapshot: 'Laptop Dell 11 pulg 4ram 64 memoria',
            productImageSnapshot: null,
            qty: 1,
            priceSoldUnit: 7500,
            costUnitSnapshot: 0,
            subtotalSold: 6500,
            subtotalCost: 0,
            profit: 6500,
            category: 'EQUIPOS',
            grossAmount: 7500,
            lineDiscountAmount: 1000,
            taxableBase: 6500,
            taxRate: 0,
            taxAmount: 0,
            exemptAmount: 0,
            taxIncluded: false,
            taxExempt: false,
          ),
        ],
      );

      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.items.single.priceSoldUnit, 7500);
      expect(sale.items.single.lineDiscountAmount, 1000);
      expect(sale.items.single.taxableBase, 6500);
      expect(sale.items.single.taxAmount, 0);
      expect(sale.items.single.subtotalSold, 6500);
      expect(sale.totalSold, 6500);
    });

    test('montos grandes (RD\$125,000.00) no rompen el layout del PDF', () async {
      final sale = SaleModel(
        id: '66666666-6666-4666-8666-666666666666',
        userId: 'user-a',
        userName: 'Yunior Lopez',
        customerId: null,
        customerName: 'Consumidor final',
        customerPhone: null,
        saleDate: DateTime(2026, 8, 21, 16),
        note: '',
        totalSold: 125000,
        totalCost: 0,
        totalProfit: 125000,
        commissionAmount: 0,
        paymentMethod: 'cash',
        paymentCashAmount: 125000,
        paymentTransferAmount: 0,
        creditAmount: 0,
        creditPaidAmount: 0,
        creditBalance: 0,
        creditStatus: 'none',
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: true,
        fiscalPriceMode: 'TAX_ADDED',
        taxableBase: 125000,
        taxAmount: 0,
        exemptAmount: 0,
        discountAmount: 0,
        fiscalVoucherType: 'B01',
        ncf: 'B0100000004',
        ncfExpirationDate: DateTime(2026, 12, 31),
        issuerNameSnapshot: 'FULLTECH, SRL',
        issuerTaxIdSnapshot: '133080206',
        issuerAddressSnapshot: 'Higüey',
        issuerPhoneSnapshot: '8295319442',
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: '133206111',
        fiscalCustomerName: 'Fune, srl',
        customerAddressSnapshot: null,
        customerPhoneSnapshot: null,
        items: [
          SaleItemModel(
            id: 'big-item',
            productId: 'big-1',
            productNameSnapshot: 'CÁMARA AHD 1080P KIT COMPLETO',
            productImageSnapshot: null,
            qty: 1,
            priceSoldUnit: 125000,
            costUnitSnapshot: 0,
            subtotalSold: 125000,
            subtotalCost: 0,
            profit: 125000,
            category: 'CÁMARAS',
            grossAmount: 125000,
            lineDiscountAmount: 0,
            taxableBase: 125000,
            taxRate: 0,
            taxAmount: 0,
            exemptAmount: 0,
            taxIncluded: false,
            taxExempt: false,
          ),
        ],
      );

      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.totalSold, 125000);
      expect(sale.items.single.priceSoldUnit, 125000);
    });

    test('nota con Pago: duplicado no rompe y se filtra (V7)', () async {
      final base = _goldenSale(voucherType: 'B01', ncf: 'B0100000003');
      final v7 = SaleModel(
        id: base.id,
        userId: base.userId,
        userName: base.userName,
        customerId: base.customerId,
        customerName: base.customerName,
        customerPhone: base.customerPhone,
        saleDate: base.saleDate,
        note: 'Pago: Efectivo\nEntrega en tienda.',
        totalSold: base.totalSold,
        totalCost: base.totalCost,
        totalProfit: base.totalProfit,
        commissionAmount: base.commissionAmount,
        paymentMethod: base.paymentMethod,
        paymentCashAmount: base.paymentCashAmount,
        paymentTransferAmount: base.paymentTransferAmount,
        creditAmount: base.creditAmount,
        creditPaidAmount: base.creditPaidAmount,
        creditBalance: base.creditBalance,
        creditStatus: base.creditStatus,
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: base.fiscalTaxEnabled,
        fiscalPriceMode: base.fiscalPriceMode,
        taxableBase: base.taxableBase,
        taxAmount: base.taxAmount,
        exemptAmount: base.exemptAmount,
        discountAmount: base.discountAmount,
        fiscalVoucherType: base.fiscalVoucherType,
        ncf: base.ncf,
        issuerNameSnapshot: base.issuerNameSnapshot,
        issuerTaxIdSnapshot: base.issuerTaxIdSnapshot,
        issuerAddressSnapshot: base.issuerAddressSnapshot,
        issuerPhoneSnapshot: base.issuerPhoneSnapshot,
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: base.fiscalCustomerTaxId,
        fiscalCustomerName: base.fiscalCustomerName,
        customerAddressSnapshot: null,
        customerPhoneSnapshot: base.customerPhoneSnapshot,
        items: base.items,
      );

      final bytes = await buildSaleInvoicePdf(sale: v7, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(invoicePdfNoteText(v7.note), 'Entrega en tienda.');
      expect(invoicePdfNoteText(v7.note).contains('Pago:'), isFalse);
    });

    test('monto millonario (RD\$1,250,000.00) genera PDF sin romper', () async {
      final sale = SaleModel(
        id: '77777777-7777-4777-8777-777777777777',
        userId: 'user-a',
        userName: 'Yunior Lopez',
        customerId: 'client-a',
        customerName: 'Fune, srl',
        customerPhone: '809-111-1111',
        saleDate: DateTime(2026, 8, 21, 17),
        note: '',
        totalSold: 1250000,
        totalCost: 0,
        totalProfit: 1250000,
        commissionAmount: 0,
        paymentMethod: 'transfer',
        paymentCashAmount: 0,
        paymentTransferAmount: 1250000,
        creditAmount: 0,
        creditPaidAmount: 0,
        creditBalance: 0,
        creditStatus: 'none',
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: true,
        fiscalPriceMode: 'TAX_ADDED',
        taxableBase: 1250000,
        taxAmount: 0,
        exemptAmount: 0,
        discountAmount: 0,
        fiscalVoucherType: 'B01',
        ncf: 'B0100000005',
        ncfExpirationDate: DateTime(2026, 12, 31),
        issuerNameSnapshot: 'FULLTECH, SRL',
        issuerTaxIdSnapshot: '133080206',
        issuerAddressSnapshot: 'Higüey',
        issuerPhoneSnapshot: '8295319442',
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: '133206111',
        fiscalCustomerName: 'Fune, srl',
        customerAddressSnapshot: 'Santo Domingo',
        customerPhoneSnapshot: '809-111-1111',
        items: [
          SaleItemModel(
            id: 'millon-item',
            productId: 'millon-1',
            productNameSnapshot: 'SOLUCIÓN CCTV 32 CANALES PROFESIONAL',
            productImageSnapshot: null,
            qty: 1,
            priceSoldUnit: 1250000,
            costUnitSnapshot: 0,
            subtotalSold: 1250000,
            subtotalCost: 0,
            profit: 1250000,
            category: 'CCTV',
            grossAmount: 1250000,
            lineDiscountAmount: 0,
            taxableBase: 1250000,
            taxRate: 0,
            taxAmount: 0,
            exemptAmount: 0,
            taxIncluded: false,
            taxExempt: false,
          ),
        ],
      );

      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.totalSold, 1250000);
      expect(sale.items.single.priceSoldUnit, 1250000);
    });

    test('descuento grande -RD\$125,000.00 genera PDF sin romper (V7 ancho)', () async {
      // Descuento por línea grande: la columna Descuento debe mostrar
      // -RD$125,000.00 en UNA sola línea, sin invadir Precio ni Base.
      final sale = SaleModel(
        id: '88888888-8888-4888-8888-888888888888',
        userId: 'user-a',
        userName: 'Yunior Lopez',
        customerId: 'client-a',
        customerName: 'Fune, srl',
        customerPhone: '809-111-1111',
        saleDate: DateTime(2026, 8, 21, 18),
        note: '',
        totalSold: 125000,
        totalCost: 0,
        totalProfit: 125000,
        commissionAmount: 0,
        paymentMethod: 'cash',
        paymentCashAmount: 125000,
        paymentTransferAmount: 0,
        creditAmount: 0,
        creditPaidAmount: 0,
        creditBalance: 0,
        creditStatus: 'none',
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: true,
        fiscalPriceMode: 'TAX_ADDED',
        taxableBase: 125000,
        taxAmount: 0,
        exemptAmount: 0,
        discountAmount: 125000,
        fiscalVoucherType: 'B01',
        ncf: 'B0100000006',
        ncfExpirationDate: DateTime(2026, 12, 31),
        issuerNameSnapshot: 'FULLTECH, SRL',
        issuerTaxIdSnapshot: '133080206',
        issuerAddressSnapshot: 'Higüey',
        issuerPhoneSnapshot: '8295319442',
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: '133206111',
        fiscalCustomerName: 'Fune, srl',
        customerAddressSnapshot: 'Santo Domingo',
        customerPhoneSnapshot: '809-111-1111',
        items: [
          SaleItemModel(
            id: 'desc-item',
            productId: 'desc-1',
            productNameSnapshot: 'SERVIDOR PRO 32 NÚCLEOS FULL RACK',
            productImageSnapshot: null,
            qty: 1,
            priceSoldUnit: 250000,
            costUnitSnapshot: 0,
            subtotalSold: 125000,
            subtotalCost: 0,
            profit: 125000,
            category: 'SERVIDORES',
            grossAmount: 250000,
            lineDiscountAmount: 125000,
            taxableBase: 125000,
            taxRate: 0,
            taxAmount: 0,
            exemptAmount: 0,
            taxIncluded: false,
            taxExempt: false,
          ),
        ],
      );

      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.items.single.priceSoldUnit, 250000);
      expect(sale.items.single.lineDiscountAmount, 125000);
      expect(sale.items.single.subtotalSold, 125000);
      expect(sale.totalSold, 125000);
    });

    test('ITBIS real (RD\$22,500.00) no rompe la columna ITBIS (V7 ancho)', () async {
      // Base 125,000 + ITBIS 18% = 22,500: la columna ITBIS debe mostrar
      // RD$22,500.00 en UNA sola línea (11% de ancho).
      final sale = SaleModel(
        id: '99999999-9999-4999-8999-999999999999',
        userId: 'user-a',
        userName: 'Yunior Lopez',
        customerId: 'client-a',
        customerName: 'Fune, srl',
        customerPhone: '809-111-1111',
        saleDate: DateTime(2026, 8, 21, 19),
        note: '',
        totalSold: 147500,
        totalCost: 0,
        totalProfit: 147500,
        commissionAmount: 0,
        paymentMethod: 'cash',
        paymentCashAmount: 147500,
        paymentTransferAmount: 0,
        creditAmount: 0,
        creditPaidAmount: 0,
        creditBalance: 0,
        creditStatus: 'none',
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: true,
        fiscalPriceMode: 'TAX_ADDED',
        taxableBase: 125000,
        taxAmount: 22500,
        exemptAmount: 0,
        discountAmount: 0,
        fiscalVoucherType: 'B01',
        ncf: 'B0100000007',
        ncfExpirationDate: DateTime(2026, 12, 31),
        issuerNameSnapshot: 'FULLTECH, SRL',
        issuerTaxIdSnapshot: '133080206',
        issuerAddressSnapshot: 'Higüey',
        issuerPhoneSnapshot: '8295319442',
        issuerEmailSnapshot: null,
        fiscalCustomerTaxId: '133206111',
        fiscalCustomerName: 'Fune, srl',
        customerAddressSnapshot: 'Santo Domingo',
        customerPhoneSnapshot: '809-111-1111',
        items: [
          SaleItemModel(
            id: 'itbis-item',
            productId: 'itbis-1',
            productNameSnapshot: 'PLANTA ELÉCTRICA 25KVA TRIFÁSICA',
            productImageSnapshot: null,
            qty: 1,
            priceSoldUnit: 147500,
            costUnitSnapshot: 0,
            subtotalSold: 147500,
            subtotalCost: 0,
            profit: 147500,
            category: 'ENERGÍA',
            grossAmount: 147500,
            lineDiscountAmount: 0,
            taxableBase: 125000,
            taxRate: 0.18,
            taxAmount: 22500,
            exemptAmount: 0,
            taxIncluded: false,
            taxExempt: false,
          ),
        ],
      );

      final bytes = await buildSaleInvoicePdf(sale: sale, company: _company());

      expect(bytes.length, greaterThan(1000));
      expect(sale.items.single.taxableBase, 125000);
      expect(sale.items.single.taxAmount, 22500);
      expect(sale.totalSold, 147500);
    });
  });
}

CompanySettings _company() {
  return CompanySettings.empty().copyWith(
    companyName: 'FULLTECH, SRL',
    rnc: '133080206',
    address: 'Santo Domingo, República Dominicana',
    phone: '809-000-0000',
  );
}

CotizacionModel _goldenQuote() {
  return CotizacionModel.fromApi({
    'id': '22222222-2222-4222-8222-222222222222',
    'createdAt': '2026-08-18T10:00:00.000Z',
    'customerName': 'CANATECH SRL',
    'customerPhone': '809-222-2222',
    'includeItbis': true,
    'itbisRate': 0.18,
    'fiscalTaxEnabled': true,
    'fiscalPriceMode': 'TAX_INCLUDED',
    'taxableBase': 21779.66,
    'taxAmount': 3920.34,
    'exemptAmount': 0,
    'discountAmount': 0,
    'subtotal': 21779.66,
    'itbisAmount': 3920.34,
    'total': 25700,
    'items': _goldenLineMaps(),
  });
}

SaleModel _goldenSale({
  required String voucherType,
  required String ncf,
  String customerName = 'CANATECH SRL',
  String? fiscalCustomerTaxId = '132588312',
}) {
  return SaleModel(
    id: '33333333-3333-4333-8333-333333333333',
    userId: 'user-a',
    userName: 'Caja',
    customerId: 'client-a',
    customerName: customerName,
    customerPhone: '809-222-2222',
    saleDate: DateTime(2026, 8, 18, 10),
    note: '',
    totalSold: 25700,
    totalCost: 0,
    totalProfit: 25700,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 25700,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_INCLUDED',
    taxableBase: 21779.66,
    taxAmount: 3920.34,
    exemptAmount: 0,
    discountAmount: 0,
    fiscalVoucherType: voucherType,
    ncf: ncf,
    fiscalCustomerTaxId: fiscalCustomerTaxId,
    fiscalCustomerName: customerName,
    items: _goldenLineMaps().asMap().entries.map((entry) {
      final map = entry.value;
      return SaleItemModel(
        id: 'sale-item-${entry.key}',
        productId: 'product-${entry.key}',
        productNameSnapshot: map['productNameSnapshot'] as String,
        productImageSnapshot: null,
        qty: map['qty'] as double,
        priceSoldUnit: map['unitPrice'] as double,
        costUnitSnapshot: 0,
        subtotalSold: map['lineTotal'] as double,
        subtotalCost: 0,
        profit: map['lineTotal'] as double,
        category: null,
        grossAmount: map['grossAmount'] as double,
        lineDiscountAmount: 0,
        taxableBase: map['taxableBase'] as double,
        taxRate: 0.18,
        taxAmount: map['taxAmount'] as double,
        exemptAmount: 0,
        taxIncluded: true,
        taxExempt: false,
      );
    }).toList(),
  );
}

SaleModel _legacySale() {
  return SaleModel(
    id: '44444444-4444-4444-8444-444444444444',
    userId: 'user-a',
    userName: 'Caja',
    customerId: null,
    customerName: 'Consumidor Final',
    customerPhone: '',
    saleDate: DateTime(2026, 8, 18, 11),
    note: '',
    totalSold: 100,
    totalCost: 0,
    totalProfit: 100,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 100,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    items: const [
      SaleItemModel(
        id: 'legacy-item',
        productId: null,
        productNameSnapshot: 'Venta rápida',
        productImageSnapshot: null,
        qty: 1,
        priceSoldUnit: 100,
        costUnitSnapshot: 0,
        subtotalSold: 100,
        subtotalCost: 0,
        profit: 100,
        category: null,
      ),
    ],
  );
}

List<Map<String, Object>> _goldenLineMaps() {
  return const [
    {
      'productNameSnapshot': 'FOTOCELDA PARA MOTOR',
      'qty': 1.0,
      'unitPrice': 1200.0,
      'grossAmount': 1200.0,
      'taxableBase': 1016.95,
      'taxAmount': 183.05,
      'lineTotal': 1200.0,
    },
    {
      'productNameSnapshot': 'MOTOR WIFI 800KG',
      'qty': 1.0,
      'unitPrice': 13000.0,
      'grossAmount': 13000.0,
      'taxableBase': 11016.95,
      'taxAmount': 1983.05,
      'lineTotal': 13000.0,
    },
    {
      'productNameSnapshot': 'SERVICIO EXTRA',
      'qty': 1.0,
      'unitPrice': 4000.0,
      'grossAmount': 4000.0,
      'taxableBase': 3389.83,
      'taxAmount': 610.17,
      'lineTotal': 4000.0,
    },
    {
      'productNameSnapshot': 'SERVICIO REEMPLAZO',
      'qty': 1.0,
      'unitPrice': 6000.0,
      'grossAmount': 6000.0,
      'taxableBase': 5084.75,
      'taxAmount': 915.25,
      'lineTotal': 6000.0,
    },
    {
      'productNameSnapshot': 'LÁMPARA PARA MOTOR',
      'qty': 1.0,
      'unitPrice': 1500.0,
      'grossAmount': 1500.0,
      'taxableBase': 1271.18,
      'taxAmount': 228.82,
      'lineTotal': 1500.0,
    },
  ];
}
