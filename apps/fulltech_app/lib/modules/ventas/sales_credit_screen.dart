import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/desktop_sales_style.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/pdf_action_menu.dart';
import '../../core/widgets/sync_status_banner.dart';
import '../cash/cash_dialogs.dart';
import '../cash/cash_turn_menu_button.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';

final salesCreditsProvider = FutureProvider<List<SaleModel>>((ref) {
  return ref.watch(ventasRepositoryProvider).listCredits(includePaid: true);
});

bool _shouldUseCreditDesktopLayout(double width) {
  if (width >= kDesktopShellBreakpoint) return true;

  final isDesktopPlatform = switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  return isDesktopPlatform && width >= 720;
}

double _creditInfoColumnWidth(double width) {
  return (width * 0.33).clamp(420.0, 640.0);
}

class SalesCreditScreen extends ConsumerStatefulWidget {
  const SalesCreditScreen({super.key});

  @override
  ConsumerState<SalesCreditScreen> createState() => _SalesCreditScreenState();
}

class _SalesCreditScreenState extends ConsumerState<SalesCreditScreen> {
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  String? _selectedCreditId;
  bool _searchOpen = false;
  bool _loading = false;
  String? _error;
  List<SaleModel> _credits = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    unawaited(_loadCredits());
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      unawaited(_refreshCredits());
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCredits() async {
    if (mounted) setState(() => _loading = true);
    try {
      final cached = await ref.read(ventasRepositoryProvider).cachedCredits();
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _credits = cached;
          _loading = false;
        });
      }
    } catch (_) {}
    await _refreshCredits();
  }

  Future<void> _refreshCredits() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await ref
          .read(ventasRepositoryProvider)
          .listCredits(includePaid: true);
      if (!mounted) return;
      setState(() {
        _credits = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException ? error.message : '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = _shouldUseCreditDesktopLayout(width);
    final isAdmin = currentUser?.appRole.isAdmin ?? false;
    final selected = _selectedCredit(_credits);

    return Scaffold(
      backgroundColor: isDesktop ? desktopSalesSurface : AppColors.background,
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      floatingActionButton: !isDesktop
          ? FloatingActionButton(
              heroTag: 'credits_summary',
              tooltip: 'Ver resumen',
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              onPressed: _showMobileSummary,
              child: const Icon(Icons.summarize_rounded),
            )
          : null,
      appBar: isDesktop
          ? FullTechPageHeader(
              title: 'Créditos',
              actions: [
                _CreditsHeaderBadge(
                  icon: Icons.credit_score_outlined,
                  label: 'Créditos',
                  value: '${_credits.length}',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: _loading ? 'Actualizando...' : 'Actualizar',
                  onPressed: _loading
                      ? null
                      : () => unawaited(_refreshCredits()),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 8),
                const CashTurnMenuButton(),
                const SizedBox(width: 12),
              ],
            )
          : CustomAppBar(
              title: 'Créditos',
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
                if (!_searchOpen)
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: () {
                      if (!_loading) unawaited(_refreshCredits());
                    },
                    icon: const Icon(Icons.refresh_rounded),
                  ),
              ],
              trailing: const SizedBox.shrink(),
              showLogo: false,
              showDepartmentLabel: false,
            ),
      body: SafeArea(
        bottom: false,
        child: isDesktop
            ? DesktopSalesFrame(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildCreditMainColumn(
                          rows: _credits,
                          isAdmin: isAdmin,
                          desktop: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: _creditInfoColumnWidth(width),
                      child: _CreditFixedInfoColumn(
                        sale: selected,
                        totalCredits: _credits.length,
                        refreshing: _loading,
                        onPayment: selected == null
                            ? null
                            : () => _openPaymentDialog(selected),
                        onSettle:
                            selected == null || selected.creditBalance <= 0.009
                            ? null
                            : () => _openPaymentDialog(selected, settle: true),
                        onPdf: selected == null
                            ? null
                            : () => _openCreditPdfPreview(selected),
                        onPrint: selected == null
                            ? null
                            : () => _printCreditPdf(selected),
                        onWhatsApp: selected == null
                            ? null
                            : () => _sendCreditWhatsApp(selected),
                        onDelete: selected == null
                            ? null
                            : isAdmin
                            ? () => _confirmDeleteCredit(selected)
                            : null,
                      ),
                    ),
                  ],
                ),
              )
            : _buildCreditMainColumn(
                rows: _credits,
                isAdmin: isAdmin,
                desktop: false,
              ),
      ),
    );
  }

  void _showMobileSummary() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _credits
        .where((sale) {
          if (query.isEmpty) return true;
          return (sale.customerName ?? '').toLowerCase().contains(query) ||
              sale.id.toLowerCase().contains(query) ||
              (sale.customerPhone ?? '').toLowerCase().contains(query) ||
              (sale.userName ?? sale.userId).toLowerCase().contains(query);
        })
        .toList(growable: false);
    final open = filtered.where((sale) => sale.creditBalance > 0.009).length;
    final pending = filtered.fold<double>(
      0,
      (sum, sale) => sum + sale.creditBalance,
    );
    final paid = filtered.fold<double>(
      0,
      (sum, sale) => sum + sale.creditPaidAmount,
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Resumen de créditos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _CreditStat(
                label: 'Créditos abiertos',
                value: '$open',
                icon: Icons.credit_score_outlined,
              ),
              const SizedBox(height: 8),
              _CreditStat(
                label: 'Total pendiente',
                value: formatRdCurrencyAccounting(pending),
                icon: Icons.account_balance_wallet_outlined,
              ),
              const SizedBox(height: 8),
              _CreditStat(
                label: 'Total abonado',
                value: formatRdCurrencyAccounting(paid),
                icon: Icons.payments_outlined,
              ),
            ],
          ),
        ),
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
            hintText: 'Buscar créditos',
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

  Widget _buildCreditMainColumn({
    required List<SaleModel> rows,
    required bool isAdmin,
    required bool desktop,
  }) {
    final theme = Theme.of(context);
    final query = _searchController.text.trim().toLowerCase();
    final filtered = rows
        .where((sale) {
          if (query.isEmpty) return true;
          return (sale.customerName ?? '').toLowerCase().contains(query) ||
              sale.id.toLowerCase().contains(query) ||
              (sale.customerPhone ?? '').toLowerCase().contains(query) ||
              (sale.userName ?? sale.userId).toLowerCase().contains(query);
        })
        .toList(growable: false);

    return Column(
      children: [
        if (desktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: _CreditTopPanel(searchController: _searchController),
          ),
        SyncStatusBanner(
          visible: _loading && _credits.isEmpty,
          label: 'Sincronizando créditos...',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Material(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  onRefresh: _refreshCredits,
                  child: filtered.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No hay créditos disponibles.')),
                          ],
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            desktop ? 14 : 14,
                            desktop ? 4 : 8,
                            desktop ? 14 : 14,
                            24,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: desktop ? 0.48 : 0.35,
                            ),
                          ),
                          itemBuilder: (context, index) {
                            final sale = filtered[index];
                            return _CreditCard(
                              sale: sale,
                              compact: desktop,
                              selected: desktop && sale.id == _selectedCreditId,
                              onTap: desktop
                                  ? () => setState(() {
                                      _selectedCreditId = sale.id;
                                    })
                                  : () => _openMobileCreditDetail(sale),
                              onPayment: () => _openPaymentDialog(sale),
                              onPdf: () => _openCreditPdfPreview(sale),
                              onDelete: isAdmin
                                  ? () => _confirmDeleteCredit(sale)
                                  : null,
                            );
                          },
                        ),
                ),
              ),
              if (_loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              if (_error != null && filtered.isEmpty)
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: _CreditMessage(
                      title: 'No se pudieron cargar los créditos',
                      detail: _error!,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openMobileCreditDetail(SaleModel sale) async {
    final isAdmin = ref.read(authStateProvider).user?.appRole.isAdmin ?? false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.88,
              child: _CreditDetailPanel(
                sale: sale,
                onClose: () => Navigator.of(sheetContext).pop(),
                onPayment: () => _openPaymentDialog(sale),
                onSettle: sale.creditBalance <= 0.009
                    ? null
                    : () => _openPaymentDialog(sale, settle: true),
                onPrint: () => _printCreditPdf(sale),
                onSharePdf: () => _openCreditPdfPreview(sale),
                onWhatsApp: () => _sendCreditWhatsApp(sale),
                onDelete: isAdmin
                    ? () => _confirmDeleteCredit(
                        sale,
                        afterDelete: () => Navigator.of(sheetContext).pop(),
                      )
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }

  SaleModel? _selectedCredit(List<SaleModel> rows) {
    final id = _selectedCreditId;
    if (id == null) return null;
    for (final sale in rows) {
      if (sale.id == id) return sale;
    }
    return null;
  }

  Future<void> _openPaymentDialog(SaleModel sale, {bool settle = false}) async {
    final draft = await showDialog<_CreditPaymentDraft>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x990B1720),
      builder: (_) => _CreditPaymentDialog(sale: sale, settle: settle),
    );
    if (draft == null || !mounted) return;

    try {
      await ref
          .read(ventasRepositoryProvider)
          .addCreditPayment(
            saleId: sale.id,
            cashAmount: draft.cashAmount,
            transferAmount: draft.transferAmount,
            note: draft.note,
          );
      unawaited(_refreshCredits());
      if (!mounted) return;
      showCashToast(context, settle ? 'Crédito saldado' : 'Abono registrado');
    } catch (error) {
      if (!mounted) return;
      showCashToast(
        context,
        error is ApiException ? error.message : '$error',
        isError: true,
      );
    }
  }

  Future<void> _confirmDeleteCredit(
    SaleModel sale, {
    VoidCallback? afterDelete,
  }) async {
    final shortId = _shortId(sale);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar crédito'),
        content: Text(
          '¿Seguro que deseas eliminar el crédito/factura $shortId? Esta acción ocultará la venta y el crédito del sistema.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(ventasRepositoryProvider).deleteSale(sale.id);
      unawaited(_refreshCredits());
      if (!mounted) return;
      setState(() {
        if (_selectedCreditId == sale.id) _selectedCreditId = null;
      });
      afterDelete?.call();
      showCashToast(context, 'Crédito eliminado');
    } catch (error) {
      if (!mounted) return;
      showCashToast(
        context,
        error is ApiException ? error.message : '$error',
        isError: true,
      );
    }
  }

  Future<Uint8List> _buildCreditPdf(SaleModel sale) async {
    final company =
        await ref.read(companySettingsRepositoryProvider).getCachedSettings() ??
        CompanySettings.empty();
    final logoImage = await _resolveCreditLogo(company);
    final doc = pw.Document();
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat(
            'dd/MM/yyyy h:mm a',
            'es_DO',
          ).format(sale.saleDate!.toLocal());
    final shortId = _shortId(sale);
    final companyName = _fallback(company.companyName, 'FULLTECH, SRL');
    final customerName = _fallback(sale.customerName, 'Cliente');
    final customerPhone = _fallback(sale.customerPhone, 'No registrado');
    final cashierName = _fallback(sale.userName ?? sale.userId, 'Usuario');
    final status = sale.creditBalance <= 0.009 ? 'Saldado' : 'Pendiente';

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 22),
          buildBackground: (_) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: const PdfColor.fromInt(0xFFF8FAFC)),
          ),
        ),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _creditLogoBox(companyName, logoImage),
                    pw.SizedBox(width: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            companyName,
                            style: pw.TextStyle(
                              fontSize: 17,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF111827),
                            ),
                          ),
                          if (company.rnc.trim().isNotEmpty)
                            _mutedText('RNC: ${company.rnc.trim()}'),
                          if (company.phone.trim().isNotEmpty)
                            _mutedText('Tel: ${company.phone.trim()}'),
                          if (company.address.trim().isNotEmpty)
                            _mutedText(company.address.trim()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(12),
                decoration: _creditPanelDecoration(),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ESTADO DE CREDITO',
                      style: pw.TextStyle(
                        fontSize: 8.5,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF2563EB),
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'CRE-$shortId',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF111827),
                      ),
                    ),
                    pw.SizedBox(height: 9),
                    _factLine('Emision', date),
                    _factLine('Estado', status),
                    _factLine('Cajero', cashierName),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Container(height: 1, color: const PdfColor.fromInt(0xFFD8E1EA)),
          pw.SizedBox(height: 12),
          pw.Container(
            width: 340,
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: _creditPanelDecoration(),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _factLine('Nombre', customerName, strong: true),
                pw.SizedBox(height: 7),
                _factLine('Telefono', customerPhone),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Detalle del credito',
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF111827),
            ),
          ),
          pw.SizedBox(height: 8),
          _creditItemsTable(sale),
          pw.SizedBox(height: 22),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(14),
                  decoration: _creditPanelDecoration(),
                  child: pw.Text(
                    'Gracias por preferirnos. Este documento resume el saldo pendiente del cliente y los abonos aplicados a la factura indicada.',
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: const PdfColor.fromInt(0xFF64748B),
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Container(
                width: 230,
                padding: const pw.EdgeInsets.all(14),
                decoration: _creditPanelDecoration(),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Totales',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF111827),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    _pdfAmountRow('Total factura', sale.totalSold),
                    _pdfAmountRow('Pagado', sale.creditPaidAmount),
                    _pdfAmountRow(
                      'Pendiente',
                      sale.creditBalance,
                      strong: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text(
            'Carta de compromiso',
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF111827),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Por medio de la presente se deja constancia de que el cliente '
            '$customerName mantiene un saldo pendiente de '
            '${formatRdCurrencyAccounting(sale.creditBalance)} correspondiente '
            'a la factura indicada. Los abonos realizados seran aplicados al '
            'saldo hasta completar la deuda.',
            style: const pw.TextStyle(
              fontSize: 9.5,
              lineSpacing: 2,
              color: PdfColor.fromInt(0xFF334155),
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _creditItemsTable(SaleModel sale) {
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF111827)),
        children: [
          _tableCell('Descripcion', header: true, align: pw.TextAlign.left),
          _tableCell('Cant.', header: true),
          _tableCell('Unitario', header: true, align: pw.TextAlign.right),
          _tableCell('Importe', header: true, align: pw.TextAlign.right),
        ],
      ),
      for (final item in sale.items)
        pw.TableRow(
          children: [
            _tableCell(
              item.productNameSnapshot.trim().isEmpty
                  ? 'Producto sin descripcion'
                  : item.productNameSnapshot.trim(),
              align: pw.TextAlign.left,
              strong: true,
            ),
            _tableCell(item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)),
            _tableCell(
              formatRdCurrencyAccounting(item.priceSoldUnit),
              align: pw.TextAlign.right,
            ),
            _tableCell(
              formatRdCurrencyAccounting(item.subtotalSold),
              align: pw.TextAlign.right,
            ),
          ],
        ),
    ];
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFFD8E1EA),
          width: 0.45,
        ),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Table(
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(
            color: PdfColor.fromInt(0xFFE5EAF0),
            width: 0.55,
          ),
        ),
        columnWidths: const {
          0: pw.FlexColumnWidth(5.4),
          1: pw.FlexColumnWidth(0.75),
          2: pw.FlexColumnWidth(1.65),
          3: pw.FlexColumnWidth(1.7),
        },
        children: rows,
      ),
    );
  }

  pw.Widget _tableCell(
    String value, {
    bool header = false,
    bool strong = false,
    pw.TextAlign align = pw.TextAlign.center,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Text(
        value,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: header ? 8 : 8.4,
          fontWeight: header || strong ? pw.FontWeight.bold : null,
          color: header ? PdfColors.white : const PdfColor.fromInt(0xFF334155),
        ),
      ),
    );
  }

  pw.Widget _pdfAmountRow(String label, double amount, {bool strong = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 7),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            formatRdCurrencyAccounting(amount),
            style: pw.TextStyle(
              fontSize: strong ? 11 : 9,
              fontWeight: strong ? pw.FontWeight.bold : null,
              color: strong
                  ? const PdfColor.fromInt(0xFF2563EB)
                  : const PdfColor.fromInt(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _factLine(String label, String value, {bool strong = false}) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 64,
          child: pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 8.4,
              color: PdfColor.fromInt(0xFF64748B),
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8.7,
              fontWeight: strong ? pw.FontWeight.bold : null,
              color: const PdfColor.fromInt(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _mutedText(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 2),
    child: pw.Text(
      value,
      style: const pw.TextStyle(
        fontSize: 8.5,
        color: PdfColor.fromInt(0xFF64748B),
      ),
    ),
  );

  pw.BoxDecoration _creditPanelDecoration() {
    return pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFF8FAFC),
      border: pw.Border.all(
        color: const PdfColor.fromInt(0xFFD8E1EA),
        width: 0.6,
      ),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    );
  }

  pw.Widget _creditLogoBox(String companyName, pw.MemoryImage? logoImage) {
    return pw.Container(
      width: 58,
      height: 58,
      padding: const pw.EdgeInsets.all(6),
      decoration: _creditPanelDecoration(),
      child: logoImage != null
          ? pw.Image(logoImage, fit: pw.BoxFit.contain)
          : pw.Center(
              child: pw.Text(
                companyName.isEmpty ? 'FT' : companyName.characters.first,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF2563EB),
                ),
              ),
            ),
    );
  }

  Future<pw.MemoryImage?> _resolveCreditLogo(CompanySettings company) async {
    final raw = (company.logoBase64 ?? '').trim();
    if (raw.isNotEmpty) {
      try {
        final base64Value = raw.startsWith('data:')
            ? raw.substring(raw.indexOf(',') + 1)
            : raw;
        return pw.MemoryImage(base64Decode(base64Value));
      } catch (_) {}
    }
    try {
      final asset = await rootBundle.load('assets/image/logo.png');
      return pw.MemoryImage(asset.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  String _fallback(String? value, String fallback) {
    final cleaned = (value ?? '').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  Future<void> _printCreditPdf(SaleModel sale) async {
    final bytes = await _buildCreditPdf(sale);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _openCreditPdfPreview(SaleModel sale) async {
    final bytes = await _buildCreditPdf(sale);
    final filename = 'credito_${_shortId(sale)}.pdf';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x990B1720),
      builder: (dialogContext) {
        final size = MediaQuery.sizeOf(dialogContext);
        final compact = size.width < 720;
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
            width: compact ? size.width - 20 : 980,
            height: compact ? size.height - 20 : size.height * 0.88,
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
                          'PDF crédito · ${sale.customerName ?? 'Cliente'}',
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
                            _shareCreditPdfWithClient(
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

  Future<void> _sendCreditWhatsApp(SaleModel sale) async {
    final bytes = await _buildCreditPdf(sale);
    if (!mounted) return;
    await _shareCreditPdfWithClient(
      launchContext: context,
      sale: sale,
      bytes: bytes,
      filename: 'credito_${_shortId(sale)}.pdf',
    );
  }

  Future<void> _shareCreditPdfWithClient({
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
        queryParameters: {'text': _buildCreditWhatsAppMessage(sale, pdfUrl)},
      );
      if (!launchContext.mounted) return;
      await safeOpenWhatsApp(
        launchContext,
        uri,
        copiedMessage: 'No se pudo abrir WhatsApp. Enlace de crédito copiado.',
      );
      if (launchContext.mounted) {
        showCashToast(launchContext, 'WhatsApp abierto con el crédito.');
      }
    } catch (e) {
      if (!launchContext.mounted) return;
      showCashToast(
        launchContext,
        'No se pudo preparar el crédito para WhatsApp: $e',
        isError: true,
      );
    }
  }

  String _buildCreditWhatsAppMessage(SaleModel sale, String pdfUrl) {
    final customerName = (sale.customerName ?? '').trim().isEmpty
        ? 'cliente'
        : sale.customerName!.trim();
    return 'Hola $customerName, te compartimos tu estado de crédito en PDF.\n'
        'Este documento corresponde al saldo pendiente de tu compra en FULLTECH.\n'
        'Puedes abrir el enlace para ver o descargar tu PDF.\n'
        'Crédito: CRE-${_shortId(sale)}\n'
        'Pendiente: ${formatRdCurrencyAccounting(sale.creditBalance)}\n'
        'PDF: $pdfUrl';
  }

  String _shortId(SaleModel sale) =>
      sale.id.length <= 8 ? sale.id : sale.id.substring(0, 8);
}

class _CreditPaymentDraft {
  const _CreditPaymentDraft({
    required this.cashAmount,
    required this.transferAmount,
    required this.note,
  });

  final double cashAmount;
  final double transferAmount;
  final String note;
}

class _CreditPaymentDialog extends StatefulWidget {
  const _CreditPaymentDialog({required this.sale, required this.settle});

  final SaleModel sale;
  final bool settle;

  @override
  State<_CreditPaymentDialog> createState() => _CreditPaymentDialogState();
}

class _CreditPaymentDialogState extends State<_CreditPaymentDialog> {
  late final TextEditingController _cashCtrl;
  late final TextEditingController _transferCtrl;
  late final TextEditingController _noteCtrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cashCtrl = TextEditingController(
      text: widget.settle ? widget.sale.creditBalance.toStringAsFixed(2) : '',
    );
    _transferCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final cash = parseDominicanAmount(_cashCtrl.text) ?? 0;
    final transfer = parseDominicanAmount(_transferCtrl.text) ?? 0;
    final total = cash + transfer;
    if (total <= 0) {
      setState(() => _error = 'Indica un monto en efectivo o transferencia.');
      return;
    }
    if (total > widget.sale.creditBalance + 0.009) {
      setState(() => _error = 'El abono no puede superar el saldo pendiente.');
      return;
    }
    Navigator.of(context).pop(
      _CreditPaymentDraft(
        cashAmount: cash,
        transferAmount: transfer,
        note: _noteCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.settle ? 'Saldar crédito' : 'Registrar abono';
    final mobile = MediaQuery.sizeOf(context).width < 520;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 12 : 24,
        vertical: mobile ? 16 : 24,
      ),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 470),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              mobile ? 16 : 26,
              mobile ? 18 : 22,
              mobile ? 16 : 26,
              mobile ? 18 : 22,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.sale.customerName ?? 'Sin cliente',
                            style: const TextStyle(color: Color(0xFF52657A)),
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
                const SizedBox(height: 18),
                if (mobile)
                  Column(
                    children: [
                      _CreditInput(
                        label: 'Efectivo',
                        controller: _cashCtrl,
                        autofocus: true,
                      ),
                      const SizedBox(height: 10),
                      _CreditInput(
                        label: 'Transferencia',
                        controller: _transferCtrl,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _CreditInput(
                          label: 'Efectivo',
                          controller: _cashCtrl,
                          autofocus: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _CreditInput(
                          label: 'Transferencia',
                          controller: _transferCtrl,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: 'Nota opcional',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Saldo pendiente: ${formatRdCurrencyAccounting(widget.sale.creditBalance)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFE11D48),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                if (mobile)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: _submit,
                        child: Text(widget.settle ? 'Saldar' : 'Guardar'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _submit,
                          child: Text(widget.settle ? 'Saldar' : 'Guardar'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreditInput extends StatelessWidget {
  const _CreditInput({
    required this.label,
    required this.controller,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: r'RD$ ',
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onSubmitted: (_) {},
    );
  }
}

class _CreditsHeaderBadge extends StatelessWidget {
  const _CreditsHeaderBadge({
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
      constraints: const BoxConstraints(minWidth: 116, minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFCFE0FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF1957E6).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: const Color(0xFF1957E6), size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1957E6).withValues(alpha: 0.80),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF111827),
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

class _CreditTopPanel extends StatelessWidget {
  const _CreditTopPanel({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: searchController,
      decoration: desktopSalesInputDecoration(
        hintText: 'Buscar por cliente, teléfono o factura',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
      ),
    );
  }
}

class _CreditStat extends StatelessWidget {
  const _CreditStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mobile = MediaQuery.sizeOf(context).width < 520;
    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: mobile ? 34 : 40,
            height: mobile ? 34 : 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primary.withValues(alpha: 0.14),
                  colorScheme.primary.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.14),
              ),
            ),
            child: Icon(
              icon,
              color: colorScheme.primary,
              size: mobile ? 18 : 21,
            ),
          ),
          SizedBox(width: mobile ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditCard extends StatelessWidget {
  const _CreditCard({
    required this.sale,
    required this.compact,
    required this.selected,
    required this.onTap,
    required this.onPayment,
    required this.onPdf,
    this.onDelete,
  });

  final SaleModel sale;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPayment;
  final VoidCallback onPdf;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy').format(sale.saleDate!.toLocal());
    final paid = sale.creditBalance <= 0.009;
    final shortId = sale.id.length <= 8 ? sale.id : sale.id.substring(0, 8);
    final cashier = (sale.userName ?? sale.userId).trim();
    final phone = (sale.customerPhone ?? '').trim();

    if (compact) {
      return Material(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: colorScheme.primary.withValues(alpha: 0.05),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    sale.customerName ?? 'Cliente sin nombre',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                      letterSpacing: -0.08,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Factura $shortId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: Text(
                    formatRdCurrencyAccounting(sale.creditBalance),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: paid ? const Color(0xFF047857) : colorScheme.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _CreditStatusDot(paid: paid),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sale.customerName ?? 'Cliente sin nombre',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _CreditStatusDot(paid: paid),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                'Factura $shortId · $date',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Tel: $phone · Cajero: ${cashier.isEmpty ? 'Usuario' : cashier}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _AmountChip(
                    label: 'Total',
                    value: formatRdCurrencyAccounting(sale.totalSold),
                  ),
                  _AmountChip(
                    label: 'Pagado',
                    value: formatRdCurrencyAccounting(sale.creditPaidAmount),
                  ),
                  _AmountChip(
                    label: paid ? 'Saldado' : 'Debe',
                    value: formatRdCurrencyAccounting(sale.creditBalance),
                    danger: !paid,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: paid ? null : onPayment,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Abonar'),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Eliminar',
                      onPressed: onDelete,
                      color: colorScheme.error,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditDetailPanel extends StatelessWidget {
  const _CreditDetailPanel({
    required this.sale,
    required this.onClose,
    required this.onPayment,
    required this.onSettle,
    required this.onPrint,
    required this.onSharePdf,
    required this.onWhatsApp,
    this.onDelete,
  });

  final SaleModel sale;
  final VoidCallback onClose;
  final VoidCallback onPayment;
  final VoidCallback? onSettle;
  final VoidCallback onPrint;
  final VoidCallback onSharePdf;
  final VoidCallback onWhatsApp;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy HH:mm').format(sale.saleDate!.toLocal());
    final paid = sale.creditBalance <= 0.009;
    final cashier = (sale.userName ?? sale.userId).trim();
    final mobile = MediaQuery.sizeOf(context).width < 620;
    return Container(
      width: mobile ? double.infinity : 460,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: mobile
            ? null
            : const Border(left: BorderSide(color: Color(0xFFD3E0E7))),
        borderRadius: mobile
            ? const BorderRadius.vertical(top: Radius.circular(16))
            : BorderRadius.zero,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.24),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.credit_score_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detalle del crédito',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Factura ${sale.id.length <= 8 ? sale.id : sale.id.substring(0, 8)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _PanelSection(
                  title: 'Cliente',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailLine(
                        label: 'Nombre',
                        value: sale.customerName ?? 'Sin cliente',
                      ),
                      _DetailLine(
                        label: 'Teléfono',
                        value: (sale.customerPhone ?? '').trim().isEmpty
                            ? 'No registrado'
                            : sale.customerPhone!,
                      ),
                      _DetailLine(label: 'Fecha', value: date),
                      _DetailLine(
                        label: 'Cajero',
                        value: cashier.isEmpty ? 'Usuario' : cashier,
                      ),
                      _StatusPill(paid: paid),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _PanelAmount(
                        label: 'Total',
                        value: sale.totalSold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PanelAmount(
                        label: 'Pagado',
                        value: sale.creditPaidAmount,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _PanelAmount(
                  label: paid ? 'Saldo saldado' : 'Saldo pendiente',
                  value: sale.creditBalance,
                  danger: !paid,
                ),
                const SizedBox(height: 14),
                _PanelSection(
                  title: 'Pagos registrados',
                  child: Column(
                    children: [
                      _DetailLine(
                        label: 'Efectivo',
                        value: formatRdCurrencyAccounting(
                          sale.paymentCashAmount,
                        ),
                      ),
                      _DetailLine(
                        label: 'Transferencia',
                        value: formatRdCurrencyAccounting(
                          sale.paymentTransferAmount,
                        ),
                      ),
                      _DetailLine(
                        label: 'Crédito inicial',
                        value: formatRdCurrencyAccounting(sale.creditAmount),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _PanelSection(
                  title: 'Productos',
                  child: Column(
                    children: sale.items
                        .map((item) => _ItemLine(item: item))
                        .toList(growable: false),
                  ),
                ),
                if ((sale.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _PanelSection(
                    title: 'Nota',
                    child: Text(
                      sale.note!,
                      style: const TextStyle(color: Color(0xFF334155)),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: paid ? null : onPayment,
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('Abonar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSettle,
                        icon: const Icon(Icons.done_all_rounded),
                        label: const Text('Saldar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSharePdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPrint,
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Imprimir'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onWhatsApp,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Enviar pendiente por WhatsApp'),
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Eliminar crédito'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelAmount extends StatelessWidget {
  const _PanelAmount({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final double value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger
            ? colorScheme.errorContainer.withValues(alpha: 0.45)
            : colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: danger
              ? colorScheme.error.withValues(alpha: 0.25)
              : colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatRdCurrencyAccounting(value),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: danger ? colorScheme.error : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({required this.item});

  final SaleItemModel item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final qty = item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productNameSnapshot,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$qty x ${formatRdCurrencyAccounting(item.priceSoldUnit)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatRdCurrencyAccounting(item.subtotalSold),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: danger
            ? colorScheme.errorContainer.withValues(alpha: 0.5)
            : colorScheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: danger
              ? colorScheme.error.withValues(alpha: 0.25)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        '$label $value',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w800,
          color: danger ? colorScheme.error : colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.paid});

  final bool paid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = paid ? const Color(0xFF047857) : colorScheme.error;
    final background = paid
        ? const Color(0xFFE8F8EF)
        : colorScheme.errorContainer.withValues(alpha: 0.55);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              paid ? 'Saldado' : 'Pendiente',
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditFixedInfoColumn extends StatelessWidget {
  const _CreditFixedInfoColumn({
    required this.sale,
    required this.totalCredits,
    required this.refreshing,
    required this.onPayment,
    required this.onSettle,
    required this.onPdf,
    required this.onPrint,
    required this.onWhatsApp,
    this.onDelete,
  });

  final SaleModel? sale;
  final int totalCredits;
  final bool refreshing;
  final VoidCallback? onPayment;
  final VoidCallback? onSettle;
  final VoidCallback? onPdf;
  final VoidCallback? onPrint;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = sale;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.surface,
            colorScheme.surfaceContainerLowest,
            Color.alphaBlend(
              colorScheme.primary.withValues(alpha: 0.025),
              colorScheme.surface,
            ),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          left: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.16),
            width: 1.2,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.075),
            blurRadius: 30,
            offset: const Offset(-10, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.credit_score_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crédito seleccionado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        refreshing
                            ? 'Sincronizando · $totalCredits créditos'
                            : '$totalCredits créditos visibles',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.44),
          ),
          Expanded(
            child: selected == null
                ? const _CreditInfoEmptyState()
                : _CreditDetailBody(
                    sale: selected,
                    onPayment: onPayment,
                    onSettle: onSettle,
                    onPdf: onPdf,
                    onPrint: onPrint,
                    onWhatsApp: onWhatsApp,
                    onDelete: onDelete,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CreditDocHeader extends StatelessWidget {
  const _CreditDocHeader({required this.number, required this.date});

  final String number;
  final String date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.request_quote_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOTA DE CRÉDITO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '#$number',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Fecha',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CreditDetailBody extends StatelessWidget {
  const _CreditDetailBody({
    required this.sale,
    required this.onPayment,
    required this.onSettle,
    required this.onPdf,
    required this.onPrint,
    required this.onWhatsApp,
    this.onDelete,
  });

  final SaleModel sale;
  final VoidCallback? onPayment;
  final VoidCallback? onSettle;
  final VoidCallback? onPdf;
  final VoidCallback? onPrint;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paid = sale.creditBalance <= 0.009;
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy').format(sale.saleDate!.toLocal());
    final cashier = (sale.userName ?? sale.userId).trim();
    final shortId = sale.id.length <= 8 ? sale.id : sale.id.substring(0, 8);
    final phone = (sale.customerPhone ?? '').trim();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _CreditDocHeader(number: 'CRE-$shortId', date: date),
                Text(
                  sale.customerName ?? 'Cliente sin nombre',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _CreditStatusDot(paid: paid),
                    if (phone.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 20),
                _CreditInfoLine(
                  icon: Icons.person_outline_rounded,
                  label: 'Cajero',
                  value: cashier.isEmpty ? 'Usuario' : cashier,
                ),
                const SizedBox(height: 10),
                _CreditInfoAmount(
                  label: 'Total factura',
                  value: sale.totalSold,
                ),
                const SizedBox(height: 6),
                _CreditInfoAmount(
                  label: 'Pagado',
                  value: sale.creditPaidAmount,
                ),
                const SizedBox(height: 6),
                _CreditInfoAmount(
                  label: paid ? 'Saldo saldado' : 'Saldo pendiente',
                  value: sale.creditBalance,
                  danger: !paid,
                ),
                const SizedBox(height: 20),
                _PanelSection(
                  title: 'Pagos registrados',
                  child: Column(
                    children: [
                      _DetailLine(
                        label: 'Efectivo',
                        value: formatRdCurrencyAccounting(
                          sale.paymentCashAmount,
                        ),
                      ),
                      _DetailLine(
                        label: 'Transferencia',
                        value: formatRdCurrencyAccounting(
                          sale.paymentTransferAmount,
                        ),
                      ),
                      _DetailLine(
                        label: 'Crédito inicial',
                        value: formatRdCurrencyAccounting(sale.creditAmount),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _PanelSection(
                  title: 'Productos',
                  child: Column(
                    children: sale.items
                        .map((item) => _ItemLine(item: item))
                        .toList(growable: false),
                  ),
                ),
                if ((sale.note ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _PanelSection(
                    title: 'Nota',
                    child: Text(
                      sale.note!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CreditColumnAction(
                icon: Icons.payments_outlined,
                label: 'Registrar abono',
                onPressed: paid ? null : onPayment,
                prominent: true,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _CreditColumnAction(
                      icon: Icons.done_all_rounded,
                      label: 'Saldar',
                      onPressed: onSettle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CreditColumnAction(
                      icon: Icons.picture_as_pdf_outlined,
                      label: 'PDF',
                      onPressed: onPdf,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _CreditColumnAction(
                      icon: Icons.print_outlined,
                      label: 'Imprimir',
                      onPressed: onPrint,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CreditColumnAction(
                      icon: Icons.chat_outlined,
                      label: 'WhatsApp',
                      onPressed: onWhatsApp,
                    ),
                  ),
                ],
              ),
              if (onDelete != null) ...[
                const SizedBox(height: 8),
                _CreditColumnAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Eliminar crédito',
                  onPressed: onDelete,
                  danger: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CreditInfoEmptyState extends StatelessWidget {
  const _CreditInfoEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.credit_score_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Selecciona un crédito',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'La información aparecerá fija en esta columna.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditInfoLine extends StatelessWidget {
  const _CreditInfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.13),
              ),
            ),
            child: Icon(icon, size: 19, color: colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.18,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.16,
                    letterSpacing: -0.08,
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

class _CreditInfoAmount extends StatelessWidget {
  const _CreditInfoAmount({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final double value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: danger
            ? colorScheme.errorContainer.withValues(alpha: 0.35)
            : colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: danger
              ? colorScheme.error.withValues(alpha: 0.25)
              : colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            formatRdCurrencyAccounting(value),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: danger ? colorScheme.error : colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreditColumnAction extends StatelessWidget {
  const _CreditColumnAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    if (danger) {
      return OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
        icon: Icon(icon, size: 17),
        label: Text(label),
      );
    }
    if (prominent) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

class _CreditStatusDot extends StatelessWidget {
  const _CreditStatusDot({required this.paid});

  final bool paid;

  @override
  Widget build(BuildContext context) {
    final color = paid
        ? const Color(0xFF059669)
        : Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          paid ? 'Saldado' : 'Pendiente',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _CreditMessage extends StatelessWidget {
  const _CreditMessage({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.credit_score_outlined, size: 48),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
