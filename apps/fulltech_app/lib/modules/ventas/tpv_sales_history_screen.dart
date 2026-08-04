import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/admin_authorization.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/fulltech_page_header.dart';

import '../../core/widgets/pdf_action_menu.dart';
import '../cash/cash_dialogs.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';
import 'utils/sales_pdf_service.dart';

enum _InvoiceFilter { active, all, returned }

enum _PaymentFilter { all, cash, transfer, mixed, credit }

enum _DateQuickFilter { today, yesterday, interval }

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
  _PaymentFilter _paymentFilter = _PaymentFilter.all;
  String? _cashierFilter;
  late DateTime _fromDate;
  late DateTime _toDate;
  bool _loading = true;
  bool _searchOpen = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 90));
    _toDate = DateTime(now.year, now.month, now.day);
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(ventasRepositoryProvider);
    final cached = await repo.cachedInvoices(
      from: _fromDate,
      to: _toDate,
      includeDeleted: true,
    );
    if (!mounted) return;
    setState(() {
      _loading = cached.isEmpty;
      _error = null;
      if (cached.isNotEmpty) {
        _applyRows(cached);
      }
    });

    try {
      final rows = await repo.listInvoices(
        from: _fromDate,
        to: _toDate,
        includeDeleted: true,
      );
      if (!mounted) return;
      setState(() {
        _applyRows(rows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyRows(List<SaleModel> rows) {
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
          if ((_cashierFilter ?? '').trim().isNotEmpty &&
              (sale.userName ?? sale.userId) != _cashierFilter) {
            return false;
          }
          if (_paymentFilter != _PaymentFilter.all &&
              sale.paymentMethod != _paymentFilter.name) {
            return false;
          }
          if (query.isEmpty) return true;

          final haystack = [
            _invoiceNumber(sale),
            sale.id,
            sale.customerName ?? '',
            sale.userName ?? '',
            _paymentLabel(sale.paymentMethod),
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

  List<String> get _cashiers {
    final values =
        _sales
            .map((sale) => (sale.userName ?? sale.userId).trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

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

  Future<void> _openFilterPanel() async {
    final result = await showGeneralDialog<_SalesFilterResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros de ventas',
      barrierColor: Colors.black.withValues(alpha: 0.26),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: _SalesFilterPanel(
            fromDate: _fromDate,
            toDate: _toDate,
            invoiceFilter: _filter,
            paymentFilter: _paymentFilter,
            cashierFilter: _cashierFilter,
            cashiers: _cashiers,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
    if (result == null || !mounted) return;
    final shouldReload =
        !_sameCalendarDay(result.fromDate, _fromDate) ||
        !_sameCalendarDay(result.toDate, _toDate);
    setState(() {
      _fromDate = result.fromDate;
      _toDate = result.toDate;
      _filter = result.invoiceFilter;
      _paymentFilter = result.paymentFilter;
      _cashierFilter = result.cashierFilter;
    });
    if (shouldReload) {
      await _load();
    }
  }

  void _clearFilters() {
    final now = DateTime.now();
    setState(() {
      _fromDate = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 90));
      _toDate = DateTime(now.year, now.month, now.day);
      _filter = _InvoiceFilter.active;
      _paymentFilter = _PaymentFilter.all;
      _cashierFilter = null;
    });
    _load();
  }

  Future<void> _returnSale(SaleModel sale) async {
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.refundSales,
      reason: 'Devolver factura',
    );
    if (!allowed || !mounted) return;

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
      showCashToast(context, 'Factura devuelta correctamente');
    } catch (e) {
      if (!mounted) return;
      showCashToast(context, 'No se pudo devolver: $e', isError: true);
    }
  }

  Future<void> _sharePdf(SaleModel sale) async {
    final bytes = await _buildInvoicePdf(sale);
    if (!mounted) return;
    await _showInvoicePdfPreview(
      sale: sale,
      bytes: bytes,
      filename: 'factura_${_invoiceNumber(sale)}.pdf',
    );
  }

  Future<void> _printInvoice(SaleModel sale) async {
    final result = await ref
        .read(unifiedTicketPrinterProvider)
        .reprintSale(sale: sale, items: sale.items);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<Uint8List> _buildInvoicePdf(SaleModel sale) async {
    final company = await ref
        .read(companySettingsRepositoryProvider)
        .getCachedSettings();
    return buildSaleInvoicePdf(sale: sale, company: company);
  }

  String _buildClientInvoiceWhatsAppMessage(SaleModel sale, String pdfUrl) {
    final customerName = (sale.customerName ?? '').trim().isEmpty
        ? 'cliente'
        : sale.customerName!.trim();
    return 'Hola $customerName, te compartimos tu factura en PDF.\n'
        'Este documento corresponde a tu compra en FULLTECH.\n'
        'Puedes abrir el enlace para ver o descargar tu factura.\n'
        'Factura: ${_invoiceNumber(sale)}\n'
        'Total: ${formatRdCurrencyAccounting(sale.totalSold)}\n'
        'PDF: $pdfUrl';
  }

  Future<void> _shareInvoicePdfWithClient({
    required BuildContext launchContext,
    required SaleModel sale,
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final pdfUrl = await ref
          .read(ventasRepositoryProvider)
          .createInvoicePdfShareLink(
            saleId: sale.id,
            pdfBytes: bytes,
            fileName: filename,
          );

      final uri = Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: {
          'text': _buildClientInvoiceWhatsAppMessage(sale, pdfUrl),
        },
      );
      if (!launchContext.mounted) return;
      await safeOpenWhatsApp(
        launchContext,
        uri,
        copiedMessage: 'No se pudo abrir WhatsApp. Enlace de factura copiado.',
      );
      if (launchContext.mounted) {
        showCashToast(launchContext, 'WhatsApp abierto con la factura.');
      }
    } catch (e) {
      if (!launchContext.mounted) return;
      showCashToast(
        launchContext,
        'No se pudo preparar la factura para WhatsApp: $e',
        isError: true,
      );
    }
  }

  Future<void> _showInvoicePdfPreview({
    required SaleModel sale,
    required Uint8List bytes,
    required String filename,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x990B1720),
      builder: (dialogContext) {
        final media = MediaQuery.sizeOf(dialogContext);
        final compact = media.width < 720;
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 28,
            vertical: compact ? 10 : 24,
          ),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 8 : 12),
          ),
          child: SizedBox(
            width: compact ? media.width - 20 : 980,
            height: compact ? media.height - 20 : media.height * 0.88,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: Color(0xFF0F7C92),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'PDF factura · ${sale.customerName ?? 'Consumidor Final'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      PdfActionMenu(
                        bytes: bytes,
                        fileName: filename,
                        compact: compact,
                        onShareWithClient: (menuContext) =>
                            _shareInvoicePdfWithClient(
                              launchContext: menuContext,
                              sale: sale,
                              bytes: bytes,
                              filename: filename,
                            ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: true,
                    allowSharing: false,
                    maxPageWidth: compact ? 640 : 900,
                    pdfFileName: filename,
                    build: (_) async => bytes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final visibleSales = _visibleSales;
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final selected =
        _selected != null && visibleSales.any((s) => s.id == _selected!.id)
        ? _selected
        : visibleSales.isEmpty
        ? null
        : visibleSales.first;

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: isMobile
          ? FloatingActionButton(
              onPressed: _showSummary,
              tooltip: 'Resumen',
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.summarize_rounded),
            )
          : null,

      appBar: isMobile
          ? CustomAppBar(
              title: 'Facturas',
              titleWidget: _searchOpen ? _buildAppBarSearchField() : null,
              actions: [
                IconButton(
                  tooltip: _searchOpen ? 'Cerrar búsqueda' : 'Buscar',
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _searchController.clear();
                  }),
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                if (!_searchOpen) ...[
                  IconButton(
                    tooltip: 'Filtros',
                    onPressed: _openFilterPanel,
                    icon: const Icon(Icons.filter_alt_outlined),
                  ),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ],

              trailing: const SizedBox.shrink(),
              showLogo: false,
              showDepartmentLabel: false,
            )
          : FullTechPageHeader(
              title: 'Facturacion',
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
            paymentFilter: _paymentFilter,
            cashierFilter: _cashierFilter,
            fromDate: _fromDate,
            toDate: _toDate,
            onBack: () => context.go(Routes.cotizaciones),
            onOpenFilters: _openFilterPanel,
            onClearFilters: _clearFilters,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 0 : 24,
                isMobile ? 0 : 10,
                isMobile ? 0 : 24,
                isMobile ? 10 : 16,
              ),

              child: isMobile
                  ? _InvoiceListCard(
                      loading: _loading,
                      error: _error,
                      sales: visibleSales,
                      selectedId: null,
                      statusText: _filterLabel(_filter),
                      dateFmt: _dateFmt,
                      invoiceNumber: _invoiceNumber,
                      onReload: _load,
                      onSelect: _openMobileDetail,
                      onPdf: _sharePdf,
                      onPrint: _printInvoice,
                      onReturn: _returnSale,
                    )
                  : Row(
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
                            onSelect: (sale) =>
                                setState(() => _selected = sale),
                            onPdf: _sharePdf,
                            onPrint: _printInvoice,
                            onReturn: _returnSale,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 32,
                          child: selected == null
                              ? const _EmptyDetail()
                              : _InvoiceDetailPanel(
                                  sale: selected,
                                  dateFmt: _dateFmt,
                                  invoiceNumber: _invoiceNumber,
                                  qty: _qty,
                                  onClose: () =>
                                      setState(() => _selected = null),
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

  Widget _buildAppBarSearchField() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF111827)),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar factura, cliente o total',
            hintStyle: const TextStyle(color: Color(0xFF8A9AA8)),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF8A9AA8),
            ),
          ),
        ),
      ),
    );
  }

  void _showSummary() {
    final totalInvoices = _sales.length;
    final activeInvoices = _sales.where((s) => !s.isDeleted).length;
    final returnedInvoices = _sales.where((s) => s.isDeleted).length;
    final totalSold = _sales.fold(0.0, (sum, sale) => sum + sale.totalSold);
    final totalItems = _sales.fold<int>(
      0,
      (sum, sale) =>
          sum +
          sale.items.fold<int>(
            0,
            (itemSum, item) => itemSum + item.qty.round(),
          ),
    );
    final uniqueCustomers = _sales
        .map((s) => (s.customerName ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Resumen de ventas',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _SalesSummaryDialog(
          totalInvoices: totalInvoices,
          activeInvoices: activeInvoices,
          returnedInvoices: returnedInvoices,
          totalSold: totalSold,
          totalItems: totalItems,
          uniqueCustomers: uniqueCustomers,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _openMobileDetail(SaleModel sale) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final height = MediaQuery.sizeOf(sheetContext).height * 0.88;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: SizedBox(
              height: height,
              child: _InvoiceDetailPanel(
                sale: sale,
                dateFmt: _dateFmt,
                invoiceNumber: _invoiceNumber,
                qty: _qty,
                onClose: () => Navigator.of(sheetContext).pop(),
                onReturn: sale.isDeleted ? null : () => _returnSale(sale),
                onPdf: () => _sharePdf(sale),
                onPrint: () => _printInvoice(sale),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.filter,
    required this.paymentFilter,
    required this.cashierFilter,
    required this.fromDate,
    required this.toDate,
    required this.onBack,
    required this.onOpenFilters,
    required this.onClearFilters,
  });

  final TextEditingController controller;
  final _InvoiceFilter filter;
  final _PaymentFilter paymentFilter;
  final String? cashierFilter;
  final DateTime fromDate;
  final DateTime toDate;
  final VoidCallback onBack;
  final VoidCallback onOpenFilters;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 760;
    final hasActiveFilters =
        filter != _InvoiceFilter.active ||
        paymentFilter != _PaymentFilter.all ||
        (cashierFilter ?? '').trim().isNotEmpty;
    final searchField = SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: 'Buscar factura, cliente o total',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFC9DAE6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.secondary,
              width: 1.3,
            ),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
    if (mobile && !hasActiveFilters) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 24, 12, mobile ? 12 : 24, 10),
      decoration: const BoxDecoration(
        color: AppColors.surfaceSubtle,
        border: Border(bottom: BorderSide(color: Color(0xFFD8E5EE))),
      ),
      child: mobile
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    '${DateFormat('dd/MM/yyyy').format(fromDate)} - ${DateFormat('dd/MM/yyyy').format(toDate)}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Limpiar'),
                ),
              ],
            )
          : Row(
              children: [
                _ToolbarBackButton(onBack: onBack),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: searchField,
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: onOpenFilters,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF1957E6,
                          ).withValues(alpha: 0.18),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_alt_outlined,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _filterButtonLabel(
                            filter,
                            paymentFilter,
                            cashierFilter,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Limpiar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF334155),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFC9DAE6)),
                    minimumSize: const Size(116, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${DateFormat('dd/MM/yyyy').format(fromDate)} - ${DateFormat('dd/MM/yyyy').format(toDate)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
    );
  }
}

class _ToolbarBackButton extends StatelessWidget {
  const _ToolbarBackButton({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 42,
      child: OutlinedButton(
        onPressed: onBack,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: const Color(0xFF0E5261),
          side: const BorderSide(color: Color(0xFFBFD3E0)),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: const Icon(Icons.arrow_back_rounded),
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
    final mobile = MediaQuery.sizeOf(context).width < 760;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(mobile ? 0 : 8),
        side: const BorderSide(color: Color(0xFFC9D9E4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (!mobile) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 14, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          statusText,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
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
          ],
          Expanded(
            child: Builder(
              builder: (context) {
                if (error != null) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 40,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No se pudieron cargar las facturas',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: onReload,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (sales.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 44,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'No hay facturas para mostrar',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Ajusta los filtros o el rango de fechas.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: onReload,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Actualizar'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => onReload(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(mobile ? 10 : 0),
                    itemCount: sales.length,
                    separatorBuilder: (_, __) =>
                        SizedBox(height: mobile ? 8 : 0),
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesFilterResult {
  const _SalesFilterResult({
    required this.fromDate,
    required this.toDate,
    required this.invoiceFilter,
    required this.paymentFilter,
    required this.cashierFilter,
  });

  final DateTime fromDate;
  final DateTime toDate;
  final _InvoiceFilter invoiceFilter;
  final _PaymentFilter paymentFilter;
  final String? cashierFilter;
}

class _SalesFilterPanel extends StatefulWidget {
  const _SalesFilterPanel({
    required this.fromDate,
    required this.toDate,
    required this.invoiceFilter,
    required this.paymentFilter,
    required this.cashierFilter,
    required this.cashiers,
  });

  final DateTime fromDate;
  final DateTime toDate;
  final _InvoiceFilter invoiceFilter;
  final _PaymentFilter paymentFilter;
  final String? cashierFilter;
  final List<String> cashiers;

  @override
  State<_SalesFilterPanel> createState() => _SalesFilterPanelState();
}

class _SalesFilterPanelState extends State<_SalesFilterPanel> {
  late DateTime _fromDate;
  late DateTime _toDate;
  late _DateQuickFilter _dateQuickFilter;
  late _InvoiceFilter _invoiceFilter;
  late _PaymentFilter _paymentFilter;
  String? _cashierFilter;

  @override
  void initState() {
    super.initState();
    _fromDate = widget.fromDate;
    _toDate = widget.toDate;
    _dateQuickFilter = _initialDateQuickFilter(_fromDate, _toDate);
    _invoiceFilter = widget.invoiceFilter;
    _paymentFilter = widget.paymentFilter;
    _cashierFilter = widget.cashierFilter;
  }

  _DateQuickFilter _initialDateQuickFilter(DateTime from, DateTime to) {
    final today = _calendarDay(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    if (_sameCalendarDay(from, today) && _sameCalendarDay(to, today)) {
      return _DateQuickFilter.today;
    }
    if (_sameCalendarDay(from, yesterday) && _sameCalendarDay(to, yesterday)) {
      return _DateQuickFilter.yesterday;
    }
    return _DateQuickFilter.interval;
  }

  DateTime _calendarDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  void _setQuickFilter(_DateQuickFilter value) {
    final today = _calendarDay(DateTime.now());
    setState(() {
      _dateQuickFilter = value;
      switch (value) {
        case _DateQuickFilter.today:
          _fromDate = today;
          _toDate = today;
          break;
        case _DateQuickFilter.yesterday:
          final yesterday = today.subtract(const Duration(days: 1));
          _fromDate = yesterday;
          _toDate = yesterday;
          break;
        case _DateQuickFilter.interval:
          break;
      }
    });
  }

  Future<void> _pickDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: from ? _fromDate : _toDate,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1),
      locale: const Locale('es', 'DO'),
      helpText: from ? 'Fecha inicial' : 'Fecha final',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _dateQuickFilter = _DateQuickFilter.interval;
      if (from) {
        _fromDate = selected;
        if (_fromDate.isAfter(_toDate)) _toDate = selected;
      } else {
        _toDate = selected;
        if (_toDate.isBefore(_fromDate)) _fromDate = selected;
      }
    });
  }

  ButtonStyle _segmentedButtonStyle() {
    return SegmentedButton.styleFrom(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
    );
  }

  Widget _segLabel(String text) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  void _apply() {
    Navigator.of(context).pop(
      _SalesFilterResult(
        fromDate: _fromDate,
        toDate: _toDate,
        invoiceFilter: _invoiceFilter,
        paymentFilter: _paymentFilter,
        cashierFilter: (_cashierFilter ?? '').trim().isEmpty
            ? null
            : _cashierFilter,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = (media.width * 0.6).clamp(300.0, 430.0);
    final dateFmt = DateFormat('dd/MM/yyyy', 'es_DO');

    return Dismissible(
      key: const ValueKey('sales-filter-panel'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => Navigator.of(context).pop(),
      child: Material(
        color: Colors.white,
        elevation: 18,
        borderRadius: BorderRadius.zero,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: media.height,
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.filter_alt_rounded,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filtros de ventas',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Rango, cajero, estado y metodo de pago',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                    children: [
                      _FilterSectionTitle('Intervalo de fecha'),
                      SegmentedButton<_DateQuickFilter>(
                        segments: [
                          ButtonSegment(
                            value: _DateQuickFilter.today,
                            label: _segLabel('Hoy'),
                          ),
                          ButtonSegment(
                            value: _DateQuickFilter.yesterday,
                            label: _segLabel('Ayer'),
                          ),
                          ButtonSegment(
                            value: _DateQuickFilter.interval,
                            label: _segLabel('Intervalo'),
                          ),
                        ],
                        selected: {_dateQuickFilter},
                        onSelectionChanged: (value) =>
                            _setQuickFilter(value.first),
                        style: _segmentedButtonStyle(),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          Expanded(
                            child: _DateFilterButton(
                              label: 'Desde',
                              value: dateFmt.format(_fromDate),
                              onTap: () => _pickDate(from: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _DateFilterButton(
                              label: 'Hasta',
                              value: dateFmt.format(_toDate),
                              onTap: () => _pickDate(from: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _FilterSectionTitle('Estado'),
                      SegmentedButton<_InvoiceFilter>(
                        segments: [
                          ButtonSegment(
                            value: _InvoiceFilter.active,
                            label: _segLabel('Activas'),
                          ),
                          ButtonSegment(
                            value: _InvoiceFilter.returned,
                            label: _segLabel('Devueltas'),
                          ),
                          ButtonSegment(
                            value: _InvoiceFilter.all,
                            label: _segLabel('Todas'),
                          ),
                        ],
                        selected: {_invoiceFilter},
                        onSelectionChanged: (value) =>
                            setState(() => _invoiceFilter = value.first),
                        style: _segmentedButtonStyle(),
                      ),

                      const SizedBox(height: 12),
                      _FilterSectionTitle('Cajero'),
                      DropdownButtonFormField<String>(
                        initialValue: (_cashierFilter ?? '').isEmpty
                            ? ''
                            : _cashierFilter,
                        isExpanded: true,
                        decoration: _filterInputDecoration('Cajero'),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Todos los cajeros'),
                          ),
                          ...widget.cashiers.map(
                            (cashier) => DropdownMenuItem(
                              value: cashier,
                              child: Text(
                                cashier,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _cashierFilter = (value ?? '').isEmpty
                              ? null
                              : value,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _FilterSectionTitle('Metodo de pago'),
                      DropdownButtonFormField<_PaymentFilter>(
                        initialValue: _paymentFilter,
                        isExpanded: true,
                        decoration: _filterInputDecoration('Metodo'),
                        items: _PaymentFilter.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(_paymentFilterLabel(value)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) => setState(
                          () => _paymentFilter = value ?? _PaymentFilter.all,
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceAlt,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _apply,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Aplicar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSectionTitle extends StatelessWidget {
  const _FilterSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF334155),
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _DateFilterButton extends StatelessWidget {
  const _DateFilterButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const Icon(
                  Icons.calendar_month_rounded,
                  size: 16,
                  color: AppColors.secondary,
                ),
              ],
            ),
          ],
        ),
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
    final mobile = MediaQuery.sizeOf(context).width < 760;
    if (mobile) {
      return _MobileInvoiceCard(
        sale: sale,
        active: active,
        dateFmt: dateFmt,
        invoiceNumber: invoiceNumber,
        onTap: onTap,
        onPdf: onPdf,
        onPrint: onPrint,
        onReturn: onReturn,
      );
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        color: selected ? const Color(0xFFF0F6FF) : Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: mobile ? 12 : 18,
          vertical: mobile ? 12 : 11,
        ),
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
                  const SizedBox(height: 4),
                  Text(
                    sale.userName ?? sale.userId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted),
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
                style: const TextStyle(color: AppColors.textMuted),
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
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.visibility_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'Imprimir',
              onPressed: onPrint,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.print_outlined, size: 19),
            ),
            IconButton(
              tooltip: 'PDF',
              onPressed: onPdf,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
              color: AppColors.error,
            ),
            IconButton(
              tooltip: active ? 'Devolver' : 'Factura devuelta',
              onPressed: onReturn,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.assignment_return_outlined, size: 19),
              color: AppColors.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileInvoiceCard extends StatelessWidget {
  const _MobileInvoiceCard({
    required this.sale,
    required this.active,
    required this.dateFmt,
    required this.invoiceNumber,
    required this.onTap,
    required this.onPdf,
    required this.onPrint,
    required this.onReturn,
  });

  final SaleModel sale;
  final bool active;
  final DateFormat dateFmt;
  final String Function(SaleModel sale) invoiceNumber;
  final VoidCallback onTap;
  final VoidCallback onPdf;
  final VoidCallback onPrint;
  final VoidCallback? onReturn;

  Future<void> _openActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _InvoiceActionsSheet(
          sale: sale,
          active: active,
          invoiceNumber: invoiceNumber(sale),
          onView: () {
            Navigator.of(sheetContext).pop();
            onTap();
          },
          onPdf: () {
            Navigator.of(sheetContext).pop();
            onPdf();
          },
          onPrint: () {
            Navigator.of(sheetContext).pop();
            onPrint();
          },
          onReturn: onReturn == null
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  onReturn!();
                },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2EAF1)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Factura ${invoiceNumber(sale)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              color: Color(0xFF23384A),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              formatRdCurrencyAccounting(sale.totalSold),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: Color(0xFF0E5261),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sale.customerName ?? 'Consumidor Final',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF334155),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(active: active),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${dateFmt.format(sale.saleDate ?? DateTime.now())} · ${sale.userName ?? sale.userId}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Acciones',
                onPressed: () => _openActions(context),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceActionsSheet extends StatelessWidget {
  const _InvoiceActionsSheet({
    required this.sale,
    required this.active,
    required this.invoiceNumber,
    required this.onView,
    required this.onPdf,
    required this.onPrint,
    required this.onReturn,
  });

  final SaleModel sale;
  final bool active;
  final String invoiceNumber;
  final VoidCallback onView;
  final VoidCallback onPdf;
  final VoidCallback onPrint;
  final VoidCallback? onReturn;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD3DEE7),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Factura $invoiceNumber',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Color(0xFF23384A),
                      ),
                    ),
                  ),
                  _StatusPill(active: active),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Divider(height: 1),
            _ActionSheetTile(
              icon: Icons.visibility_outlined,
              label: 'Ver factura',
              color: AppColors.textPrimary,
              onTap: onView,
            ),
            _ActionSheetTile(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Abrir PDF',
              color: AppColors.error,
              onTap: onPdf,
            ),
            _ActionSheetTile(
              icon: Icons.print_outlined,
              label: 'Imprimir',
              color: AppColors.textPrimary,
              onTap: onPrint,
            ),
            if (onReturn != null) ...[
              const Divider(height: 1),
              _ActionSheetTile(
                icon: Icons.assignment_return_outlined,
                label: 'Devolver factura',
                color: AppColors.warning,
                onTap: onReturn!,
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActionSheetTile extends StatelessWidget {
  const _ActionSheetTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      onTap: onTap,
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
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFC9D9E4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
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
                      color: Color(0xFF23384A),
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
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                _DetailLine('Factura', invoiceNumber(sale)),
                _DetailLine(
                  'Fecha',
                  dateFmt.format(sale.saleDate ?? DateTime.now()),
                ),
                _DetailLine('Cajero', sale.userName ?? sale.userId),
                _DetailLine('Pago', _paymentLabel(sale.paymentMethod)),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: Divider(height: 1),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              'DETALLE',
              style: TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 18),
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
                        style: const TextStyle(color: AppColors.textMuted),
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
          Container(
            color: const Color(0xFFF8FBFD),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
            child: Column(
              children: [
                _TotalLine('Subtotal', subtotal),
                _TotalLine('Total factura', sale.totalSold, strong: true),
                _TotalLine('Neto vigente', sale.isDeleted ? 0 : sale.totalSold),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onReturn,
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: Text(sale.isDeleted ? 'Devuelta' : 'Devolver'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.secondary,
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
      constraints: const BoxConstraints(minWidth: 124, minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFCFE8F2),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
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
                color: AppColors.textMuted,
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
                color: strong ? AppColors.textPrimary : AppColors.textMuted,
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
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _SalesSummaryDialog extends StatelessWidget {
  const _SalesSummaryDialog({
    required this.totalInvoices,
    required this.activeInvoices,
    required this.returnedInvoices,
    required this.totalSold,
    required this.totalItems,
    required this.uniqueCustomers,
  });

  final int totalInvoices;
  final int activeInvoices;
  final int returnedInvoices;
  final double totalSold;
  final int totalItems;
  final int uniqueCustomers;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final compact = media.width < 720;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 28,
        vertical: 24,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.summarize_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen de ventas',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Información general de la lista',
                          style: TextStyle(
                            color: Color(0xFFDCEBFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                children: [
                  _SummaryMetric(
                    icon: Icons.receipt_long_outlined,
                    label: 'Total de facturas',
                    value: '$totalInvoices',
                    accent: AppColors.secondary,
                  ),
                  _SummaryMetric(
                    icon: Icons.payments_outlined,
                    label: 'Total vendido',
                    value: formatRdCurrencyAccounting(totalSold),
                    accent: const Color(0xFF059669),
                  ),
                  _SummaryMetric(
                    icon: Icons.shopping_bag_outlined,
                    label: 'Artículos vendidos',
                    value: '$totalItems',
                    accent: const Color(0xFF0E7490),
                  ),
                  _SummaryMetric(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Facturas activas',
                    value: '$activeInvoices',
                    accent: const Color(0xFF15803D),
                  ),
                  _SummaryMetric(
                    icon: Icons.assignment_return_outlined,
                    label: 'Facturas devueltas',
                    value: '$returnedInvoices',
                    accent: const Color(0xFFB45309),
                  ),
                  _SummaryMetric(
                    icon: Icons.people_outline_rounded,
                    label: 'Clientes distintos',
                    value: '$uniqueCustomers',
                    accent: const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Entendido'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
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

String _filterButtonLabel(
  _InvoiceFilter filter,
  _PaymentFilter payment,
  String? cashier,
) {
  final extraFilters =
      payment != _PaymentFilter.all || (cashier ?? '').trim().isNotEmpty;
  if (extraFilters) return 'Filtros activos';
  return switch (filter) {
    _InvoiceFilter.active => 'Filtro',
    _InvoiceFilter.returned => 'Devueltas',
    _InvoiceFilter.all => 'Todas',
  };
}

String _paymentFilterLabel(_PaymentFilter filter) {
  return switch (filter) {
    _PaymentFilter.all => 'Todos los métodos',
    _PaymentFilter.cash => 'Efectivo',
    _PaymentFilter.transfer => 'Transferencia',
    _PaymentFilter.mixed => 'Mixto',
    _PaymentFilter.credit => 'Crédito',
  };
}

String _paymentLabel(String value) {
  return switch (value) {
    'cash' => 'Efectivo',
    'transfer' => 'Transferencia',
    'mixed' => 'Mixto',
    'credit' => 'Crédito',
    _ => value.trim().isEmpty ? 'Sin método' : value,
  };
}

InputDecoration _filterInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: AppColors.surfaceMuted,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: const BorderSide(color: AppColors.borderStrong),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: const BorderSide(color: AppColors.borderStrong),
    ),
  );
}

bool _sameCalendarDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
