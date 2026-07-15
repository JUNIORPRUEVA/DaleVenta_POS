import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';

enum _InvoiceFilter { active, all, returned }

class TpvSalesHistoryScreen extends ConsumerStatefulWidget {
  const TpvSalesHistoryScreen({super.key});

  @override
  ConsumerState<TpvSalesHistoryScreen> createState() =>
      _TpvSalesHistoryScreenState();
}

class _TpvSalesHistoryScreenState extends ConsumerState<TpvSalesHistoryScreen> {
  final _searchController = TextEditingController();
  final _dateFmt = DateFormat('dd/MM/yy HH:mm', 'es_DO');

  List<SaleModel> _sales = const [];
  SaleModel? _selected;
  _InvoiceFilter _filter = _InvoiceFilter.active;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 90));
    final to = DateTime(now.year, now.month, now.day);

    try {
      final rows = await ref
          .read(ventasRepositoryProvider)
          .listInvoices(from: from, to: to, includeDeleted: true);
      if (!mounted) return;
      setState(() {
        _sales = rows;
        if (_selected == null && rows.isNotEmpty) {
          _selected = rows.firstWhere(
            (sale) => !sale.isDeleted,
            orElse: () => rows.first,
          );
        } else if (_selected != null) {
          _selected = rows.cast<SaleModel?>().firstWhere(
            (sale) => sale?.id == _selected!.id,
            orElse: () => rows.isEmpty ? null : rows.first,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SaleModel> get _visibleSales {
    final query = _searchController.text.trim().toLowerCase();
    return _sales
        .where((sale) {
          final matchesStatus = switch (_filter) {
            _InvoiceFilter.active => !sale.isDeleted,
            _InvoiceFilter.returned => sale.isDeleted,
            _InvoiceFilter.all => true,
          };
          if (!matchesStatus) return false;
          if (query.isEmpty) return true;

          final haystack = [
            _invoiceNumber(sale),
            sale.id,
            sale.customerName ?? '',
            sale.userName ?? '',
            sale.totalSold.toStringAsFixed(2),
            formatRdCurrencyAccounting(sale.totalSold),
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  int get _activeCount => _sales.where((sale) => !sale.isDeleted).length;

  double get _activeTotal => _sales
      .where((sale) => !sale.isDeleted)
      .fold(0.0, (sum, sale) => sum + sale.totalSold);

  String _invoiceNumber(SaleModel sale) {
    final digits = sale.id.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 8) return digits.substring(digits.length - 8);
    final compact = sale.id.replaceAll('-', '');
    if (compact.length >= 8) return compact.substring(0, 8).toUpperCase();
    return compact.toUpperCase();
  }

  String _qty(double value) {
    if (value == value.truncateToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  Future<void> _returnSale(SaleModel sale) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Devolver factura ${_invoiceNumber(sale)}'),
        content: Text(
          'Esta accion marcara la factura como devuelta y restaurara el stock de sus productos.\n\nTotal: ${formatRdCurrencyAccounting(sale.totalSold)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.assignment_return_outlined),
            label: const Text('Devolver'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final returned = await ref
          .read(ventasRepositoryProvider)
          .returnSale(sale.id);
      if (!mounted) return;
      setState(() {
        _sales = [
          for (final current in _sales)
            if (current.id == returned.id) returned else current,
        ];
        _selected = returned;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Factura devuelta')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo devolver: $e')));
    }
  }

  Future<void> _sharePdf(SaleModel sale) async {
    final bytes = await _buildInvoicePdf(sale);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'factura_${_invoiceNumber(sale)}.pdf',
    );
  }

  Future<void> _printInvoice(SaleModel sale) async {
    final bytes = await _buildInvoicePdf(sale);
    await Printing.layoutPdf(
      name: 'Factura ${_invoiceNumber(sale)}',
      onLayout: (_) async => bytes,
    );
  }

  Future<Uint8List> _buildInvoicePdf(SaleModel sale) async {
    final doc = pw.Document(
      title: 'Factura ${_invoiceNumber(sale)}',
      author: 'FullTech',
    );
    final subtotal = sale.items.fold(
      0.0,
      (sum, item) => sum + item.subtotalSold,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'FullTech POS',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Sistema de facturacion'),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Factura ${_invoiceNumber(sale)}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(_dateFmt.format(sale.saleDate ?? DateTime.now())),
                  pw.Text(sale.isDeleted ? 'Devuelta' : 'Activa'),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Cliente: ${sale.customerName ?? 'Consumidor Final'}',
                  ),
                ),
                pw.Text('Cajero: ${sale.userName ?? sale.userId}'),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            headers: const ['Producto', 'Cant.', 'Precio', 'Total'],
            data: sale.items
                .map(
                  (item) => [
                    item.productNameSnapshot,
                    _qty(item.qty),
                    formatRdCurrencyAccounting(item.priceSoldUnit),
                    formatRdCurrencyAccounting(item.subtotalSold),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 18),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 260,
              child: pw.Column(
                children: [
                  _pdfTotalLine('Subtotal', subtotal),
                  pw.Divider(),
                  _pdfTotalLine('Total factura', sale.totalSold, strong: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final visibleSales = _visibleSales;
    final selected =
        _selected != null && visibleSales.any((s) => s.id == _selected!.id)
        ? _selected
        : visibleSales.isEmpty
        ? null
        : visibleSales.first;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
          ),
        ),
        title: const Text('Facturacion'),
        actions: [
          _MetricBadge(
            icon: Icons.receipt_long_outlined,
            label: 'Facturas',
            value: '$_activeCount',
          ),
          const SizedBox(width: 8),
          _MetricBadge(
            icon: Icons.payments_outlined,
            label: 'Total vendido',
            value: formatRdCurrencyAccounting(_activeTotal),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _Toolbar(
            controller: _searchController,
            filter: _filter,
            onBack: () => context.go(Routes.cotizaciones),
            onFilterChanged: (value) => setState(() => _filter = value),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 62,
                    child: _InvoiceListCard(
                      loading: _loading,
                      error: _error,
                      sales: visibleSales,
                      selectedId: selected?.id,
                      statusText: _filterLabel(_filter),
                      dateFmt: _dateFmt,
                      invoiceNumber: _invoiceNumber,
                      onReload: _load,
                      onSelect: (sale) => setState(() => _selected = sale),
                      onPdf: _sharePdf,
                      onPrint: _printInvoice,
                      onReturn: _returnSale,
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 32,
                    child: selected == null
                        ? const _EmptyDetail()
                        : _InvoiceDetailPanel(
                            sale: selected,
                            dateFmt: _dateFmt,
                            invoiceNumber: _invoiceNumber,
                            qty: _qty,
                            onClose: () => setState(() => _selected = null),
                            onReturn: selected.isDeleted
                                ? null
                                : () => _returnSale(selected),
                            onPdf: () => _sharePdf(selected),
                            onPrint: () => _printInvoice(selected),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.onBack,
    required this.onFilterChanged,
  });

  final TextEditingController controller;
  final _InvoiceFilter filter;
  final VoidCallback onBack;
  final ValueChanged<_InvoiceFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 16, 26, 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF6F9FC),
        border: Border(bottom: BorderSide(color: Color(0xFFD6E1EA))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Buscar por codigo, cliente o total...',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          PopupMenuButton<_InvoiceFilter>(
            onSelected: onFilterChanged,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _InvoiceFilter.active,
                child: Text('Facturas activas'),
              ),
              PopupMenuItem(
                value: _InvoiceFilter.returned,
                child: Text('Devueltas'),
              ),
              PopupMenuItem(value: _InvoiceFilter.all, child: Text('Todas')),
            ],
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: const Color(0xFF1957E6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_outlined, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _filterButtonLabel(filter),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _InvoiceListCard extends StatelessWidget {
  const _InvoiceListCard({
    required this.loading,
    required this.error,
    required this.sales,
    required this.selectedId,
    required this.statusText,
    required this.dateFmt,
    required this.invoiceNumber,
    required this.onReload,
    required this.onSelect,
    required this.onPdf,
    required this.onPrint,
    required this.onReturn,
  });

  final bool loading;
  final String? error;
  final List<SaleModel> sales;
  final String? selectedId;
  final String statusText;
  final DateFormat dateFmt;
  final String Function(SaleModel sale) invoiceNumber;
  final VoidCallback onReload;
  final ValueChanged<SaleModel> onSelect;
  final ValueChanged<SaleModel> onPdf;
  final ValueChanged<SaleModel> onPrint;
  final ValueChanged<SaleModel> onReturn;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFD3E0EA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Listado de facturas',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Selecciona una factura para ver el resumen completo a la derecha.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  statusText,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: onReload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Builder(
              builder: (context) {
                if (loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (error != null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 34),
                        const SizedBox(height: 8),
                        Text(error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: onReload,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  );
                }
                if (sales.isEmpty) {
                  return const Center(
                    child: Text('No hay facturas para mostrar'),
                  );
                }

                return ListView.separated(
                  itemCount: sales.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  itemBuilder: (context, index) {
                    final sale = sales[index];
                    return _InvoiceRow(
                      sale: sale,
                      selected: sale.id == selectedId,
                      dateFmt: dateFmt,
                      invoiceNumber: invoiceNumber,
                      onTap: () => onSelect(sale),
                      onPdf: () => onPdf(sale),
                      onPrint: () => onPrint(sale),
                      onReturn: sale.isDeleted ? null : () => onReturn(sale),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.sale,
    required this.selected,
    required this.dateFmt,
    required this.invoiceNumber,
    required this.onTap,
    required this.onPdf,
    required this.onPrint,
    required this.onReturn,
  });

  final SaleModel sale;
  final bool selected;
  final DateFormat dateFmt;
  final String Function(SaleModel sale) invoiceNumber;
  final VoidCallback onTap;
  final VoidCallback onPdf;
  final VoidCallback onPrint;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final active = !sale.isDeleted;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? const Color(0xFFF4F8FF) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Factura ${invoiceNumber(sale)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sale.userName ?? sale.userId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 18,
              child: Text(
                sale.customerName ?? 'Consumidor Final',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 14,
              child: Text(
                dateFmt.format(sale.saleDate ?? DateTime.now()),
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ),
            Expanded(
              flex: 10,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(active: active),
              ),
            ),
            Expanded(
              flex: 12,
              child: Text(
                formatRdCurrencyAccounting(sale.totalSold),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Ver detalle',
              onPressed: onTap,
              icon: const Icon(Icons.visibility_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'Imprimir',
              onPressed: onPrint,
              icon: const Icon(Icons.print_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'PDF',
              onPressed: onPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
              color: const Color(0xFFE11D48),
            ),
            IconButton(
              tooltip: active ? 'Devolver' : 'Factura devuelta',
              onPressed: onReturn,
              icon: const Icon(Icons.assignment_return_outlined, size: 19),
              color: const Color(0xFFEA580C),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceDetailPanel extends StatelessWidget {
  const _InvoiceDetailPanel({
    required this.sale,
    required this.dateFmt,
    required this.invoiceNumber,
    required this.qty,
    required this.onClose,
    required this.onPdf,
    required this.onPrint,
    required this.onReturn,
  });

  final SaleModel sale;
  final DateFormat dateFmt;
  final String Function(SaleModel sale) invoiceNumber;
  final String Function(double value) qty;
  final VoidCallback onClose;
  final VoidCallback onPdf;
  final VoidCallback onPrint;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    final subtotal = sale.items.fold(
      0.0,
      (sum, item) => sum + item.subtotalSold,
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFD3E0EA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    sale.customerName ?? 'Consumidor Final',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusPill(active: !sale.isDeleted),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _DetailLine('Factura', invoiceNumber(sale)),
                _DetailLine(
                  'Fecha',
                  dateFmt.format(sale.saleDate ?? DateTime.now()),
                ),
                _DetailLine('Cajero', sale.userName ?? sale.userId),
                _DetailLine('Pago', 'Efectivo'),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Divider(height: 1),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'DETALLE',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: sale.items.length,
              itemBuilder: (context, index) {
                final item = sale.items[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.productNameSnapshot,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${qty(item.qty)} x ${formatRdCurrencyAccounting(item.priceSoldUnit)}',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 96,
                        child: Text(
                          formatRdCurrencyAccounting(item.subtotalSold),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Column(
              children: [
                _TotalLine('Subtotal', subtotal),
                _TotalLine('Total factura', sale.totalSold, strong: true),
                _TotalLine('Neto vigente', sale.isDeleted ? 0 : sale.totalSold),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onReturn,
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: Text(sale.isDeleted ? 'Devuelta' : 'Devolver'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1957E6),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPrint,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Imprimir'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: onPdf,
                    child: const Icon(Icons.picture_as_pdf_outlined),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4E1F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1957E6), size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF15803D) : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'ACTIVA' : 'DEVUELTA',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine(this.label, this.value, {this.strong = false});

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong
                    ? const Color(0xFF0F172A)
                    : const Color(0xFF64748B),
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            formatRdCurrencyAccounting(value),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFD3E0EA)),
      ),
      child: const Center(
        child: Text(
          'Selecciona una factura para ver el detalle',
          style: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
    );
  }
}

String _filterLabel(_InvoiceFilter filter) {
  return switch (filter) {
    _InvoiceFilter.active => 'Mostrando facturas activas',
    _InvoiceFilter.returned => 'Mostrando devoluciones',
    _InvoiceFilter.all => 'Mostrando todas las facturas',
  };
}

String _filterButtonLabel(_InvoiceFilter filter) {
  return switch (filter) {
    _InvoiceFilter.active => 'Filtro',
    _InvoiceFilter.returned => 'Devueltas',
    _InvoiceFilter.all => 'Todas',
  };
}

pw.Widget _pdfTotalLine(String label, double value, {bool strong = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
        pw.Text(
          formatRdCurrencyAccounting(value),
          style: pw.TextStyle(
            fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}
