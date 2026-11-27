import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/theme/app_colors.dart';
import '../../core/time/business_time.dart';
import '../../core/uom/uom_formatters.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/pdf_document_file_name.dart';
import '../../core/utils/pdf_file_actions.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/desktop_sales_style.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/history_presentation.dart';
import '../../core/widgets/pdf_action_menu.dart';
import '../../core/widgets/pdf_preview_panel.dart';
import '../../core/widgets/sync_status_banner.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../core/printing/models/ticket_data.dart';
import '../cash/cash_dialogs.dart';
import '../cash/cash_turn_menu_button.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';
import 'credit_history_filters.dart';
import 'utils/sales_pdf_service.dart' show invoicePdfCode;

final salesCreditsProvider = FutureProvider<List<SaleModel>>((ref) {
  return ref.watch(ventasRepositoryProvider).listCredits(includePaid: true);
});

bool _shouldUseCreditDesktopLayout(double width) {
  return width >= 860;
}

double _creditInfoColumnWidth(double width) {
  return (width * 0.30 + 150).clamp(420.0, 640.0);
}

String _creditDisplayNote(SaleModel sale) {
  final note = (sale.note ?? '').trim();
  return RegExp(r'^Pago:\s*cr[eé]dito\.?$', caseSensitive: false).hasMatch(note)
      ? ''
      : note;
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
  CreditHistoryFilters _filters = const CreditHistoryFilters();
  String? _error;
  List<SaleModel> _credits = const [];
  bool _savingPayment = false;

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
          _selectedCreditId = _resolveCreditSelection(cached);
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
        _selectedCreditId = _resolveCreditSelection(rows);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = userSafeErrorMessage(
          error,
          fallback: 'No se pudieron cargar los créditos.',
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = _shouldUseCreditDesktopLayout(width);
    final compactDesktop = width < 1360;
    final gutter = compactDesktop ? 12.0 : 24.0;
    final columnGap = compactDesktop ? 10.0 : 16.0;
    final isAdmin = currentUser?.appRole.isAdmin ?? false;
    final visible = _visibleCredits(_credits);
    final selected =
        _selectedCredit(visible) ?? (visible.isEmpty ? null : visible.first);

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
              title: 'Historial de créditos',
              actions: [
                const CashTurnMenuButton(refined: true),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: _loading ? 'Actualizando...' : 'Actualizar',
                  onPressed: _loading
                      ? null
                      : () => unawaited(_refreshCredits()),
                  icon: const MobileActionIcon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 12),
              ],
            )
          : CustomAppBar(
              title: 'Historial de créditos',
              titleWidget: _searchOpen ? _buildAppBarSearchField() : null,
              actions: [
                IconButton(
                  tooltip: 'Filtros',
                  onPressed: _openCreditFilters,
                  icon: const MobileActionIcon(Icons.filter_alt_outlined),
                ),
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
                    icon: const MobileActionIcon(Icons.refresh_rounded),
                  ),
              ],
              trailing: const SizedBox.shrink(),
              showLogo: false,
              showDepartmentLabel: false,
            ),
      body: SafeArea(
        bottom: false,
        child: isDesktop
            ? Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: gutter,
                      vertical: compactDesktop ? 5 : 8,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 560,
                                  ),
                                  child: SizedBox(
                                    height: 36,
                                    child: _CreditTopPanel(
                                      searchController: _searchController,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 36,
                                child: FilledButton.icon(
                                  onPressed: _openCreditFilters,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 36),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.standard,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                  icon: const MobileActionIcon(
                                    Icons.filter_alt_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Filtro'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: columnGap),
                        SizedBox(
                          width: _creditInfoColumnWidth(width),
                          child: _CreditSelectionSummary(
                            count: visible.length,
                            refreshing: _loading,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: DesktopSalesFrame(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        compactDesktop ? 6 : 10,
                        gutter,
                        compactDesktop ? 8 : 16,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: HistoryPanel(
                              child: _buildCreditMainColumn(
                                rows: _credits,
                                desktop: true,
                              ),
                            ),
                          ),
                          SizedBox(width: columnGap),
                          SizedBox(
                            width: _creditInfoColumnWidth(width),
                            child: HistoryPanel(
                              child: HistoryDetailStyle(
                                child: _CreditFixedInfoColumn(
                                  sale: selected,
                                  onPayment: selected == null
                                      ? null
                                      : () => _openPaymentDialog(selected),
                                  onSettle:
                                      selected == null ||
                                          selected.creditBalance <= 0.009
                                      ? null
                                      : () => _openPaymentDialog(
                                          selected,
                                          settle: true,
                                        ),
                                  onDelete: selected == null
                                      ? null
                                      : isAdmin
                                      ? () => _confirmDeleteCredit(selected)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _buildCreditMainColumn(rows: _credits, desktop: false),
      ),
    );
  }

  Future<void> _openCreditFilters() async {
    final cashiers =
        _credits.map((sale) => sale.userName ?? sale.userId).toSet().toList()
          ..sort();
    if (_filters.cashier != null && !cashiers.contains(_filters.cashier)) {
      cashiers.add(_filters.cashier!);
    }
    final result = await showGeneralDialog<CreditHistoryFilters>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros de créditos',
      barrierColor: Colors.black26,
      pageBuilder: (context, _, __) => Align(
        alignment: Alignment.centerRight,
        child: CreditHistoryFilterPanel(initial: _filters, cashiers: cashiers),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _filters = result;
        _selectedCreditId = null;
      });
    }
  }

  void _showMobileSummary() {
    final filtered = _visibleCredits(_credits);
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
            prefixIcon: const MobileActionIcon(
              Icons.search_rounded,
              color: Color(0xFF8A9AA8),
            ),
          ),
        ),
      ),
    );
  }

  List<SaleModel> _visibleCredits(List<SaleModel> rows) {
    final query = _searchController.text.trim().toLowerCase();
    return rows
        .where((sale) {
          if (!_filters.matches(sale)) return false;
          return query.isEmpty ||
              (sale.customerName ?? '').toLowerCase().contains(query) ||
              TicketData.fromSale(
                sale,
              ).ticketNumber.toLowerCase().contains(query) ||
              sale.id.toLowerCase().contains(query) ||
              (sale.customerPhone ?? '').toLowerCase().contains(query) ||
              (sale.userName ?? '').toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Widget _buildCreditMainColumn({
    required List<SaleModel> rows,
    required bool desktop,
  }) {
    final theme = Theme.of(context);
    final filtered = _visibleCredits(rows);
    final selectedId =
        _selectedCredit(filtered)?.id ??
        (filtered.isEmpty ? null : filtered.first.id);

    return Column(
      children: [
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
                      ? CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: HistoryEmptyState(
                                title: 'No hay créditos con estos filtros',
                                message:
                                    'Ajusta los filtros. Los créditos se crean desde Facturación.',
                                buttonLabel: '',
                                onPressed: null,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: desktop
                              ? EdgeInsets.zero
                              : const EdgeInsets.fromLTRB(14, 8, 14, 24),
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
                              selected: desktop && sale.id == selectedId,
                              onTap: desktop
                                  ? () => setState(() {
                                      _selectedCreditId = sale.id;
                                    })
                                  : () => _openMobileCreditDetail(sale),
                              onPdf: () => _openCreditPdfPreview(sale),
                              onPrint: () => _printCreditPdf(sale),
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

  String? _resolveCreditSelection(List<SaleModel> rows) {
    if (rows.isEmpty) return null;
    final current = _selectedCreditId;
    if (current != null && rows.any((sale) => sale.id == current)) {
      return current;
    }
    return rows.first.id;
  }

  Future<void> _openPaymentDialog(SaleModel sale, {bool settle = false}) async {
    if (_savingPayment) return;
    _savingPayment = true;
    try {
      final draft = await showDialog<_CreditPaymentDraft>(
        context: context,
        barrierDismissible: true,
        barrierColor: const Color(0x990B1720),
        builder: (_) => _CreditPaymentDialog(sale: sale, settle: settle),
      );
      if (draft == null || !mounted) return;

      try {
        final updated = await ref
            .read(ventasRepositoryProvider)
            .addCreditPayment(
              saleId: sale.id,
              cashAmount: draft.cashAmount,
              transferAmount: draft.transferAmount,
              note: draft.note,
            );
        if (!mounted) return;
        if (updated.status == 'PENDING_SYNC') {
          showCashToast(
            context,
            'Abono guardado en este equipo. Pendiente de confirmar; no lo repitas.',
          );
          return;
        }
        setState(
          () => _credits = [
            for (final row in _credits) row.id == updated.id ? updated : row,
          ],
        );
        showCashToast(
          context,
          updated.creditBalance <= 0.009
              ? 'Crédito saldado'
              : 'Abono registrado',
        );
        await _openCreditPdfPreview(updated);
      } catch (error) {
        if (!mounted) return;
        showCashToast(
          context,
          userSafeErrorMessage(
            error,
            fallback: 'No se pudo registrar el abono. Inténtalo nuevamente.',
          ),
          isError: true,
        );
      }
    } finally {
      _savingPayment = false;
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
        userSafeErrorMessage(
          error,
          fallback: 'No se pudo eliminar el crédito. Inténtalo nuevamente.',
        ),
        isError: true,
      );
    }
  }

  Future<Uint8List> _buildCreditPdf(SaleModel sale) async {
    final current = await ref.read(ventasRepositoryProvider).getById(sale.id);
    return ref
        .read(unifiedTicketPrinterProvider)
        .buildSaleInvoicePdf(sale: current);
  }

  Future<void> _printCreditPdf(SaleModel sale) async {
    try {
      final current = await ref.read(ventasRepositoryProvider).getById(sale.id);
      final result = await ref
          .read(unifiedTicketPrinterProvider)
          .reprintSale(sale: current);
      if (!mounted) return;
      showCashToast(context, result.message, isError: !result.success);
    } catch (error) {
      if (mounted) {
        showCashToast(
          context,
          userSafeErrorMessage(
            error,
            fallback: 'No se pudo preparar el ticket. El pago no se repite.',
          ),
          isError: true,
        );
      }
    }
  }

  Future<void> _openCreditPdfPreview(SaleModel sale) async {
    final filename = 'factura_${invoicePdfCode(sale.id)}.pdf';
    final downloadFileName = buildPdfDocumentFileName(
      documentKind: 'Factura',
      customerName: sale.customerName,
      fallbackCode: _shortId(sale),
    );
    // La construcción del PDF arranca antes de abrir el panel: la columna
    // aparece al instante y el documento se muestra en cuanto está listo.
    final pdfBytesFuture = _buildCreditPdf(sale);
    if (!mounted) return;
    await showPdfPreviewPanel<void>(
      context: context,
      barrierLabel: 'Vista previa del crédito',
      builder: (dialogContext) {
        return Column(
          children: [
            PdfPreviewPanelHeader(
              title: 'PDF factura · ${sale.customerName ?? 'Cliente'}',
              onClose: () => Navigator.of(dialogContext).pop(),
            ),
            Expanded(
              child: FutureBuilder(
                future: pdfBytesFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  return PdfPreviewStage(
                    bytes: bytes,
                    errorMessage: snapshot.hasError
                        ? userSafeErrorMessage(
                            snapshot.error!,
                            fallback:
                                'No se pudo preparar el crédito. Inténtalo nuevamente.',
                          )
                        : null,
                    actions: [
                      if (bytes != null)
                        PdfActionMenu(
                          bytes: bytes,
                          fileName: filename,
                          circular: true,
                          iconAsset: PdfPanelIcons.share,
                          onShareWithClient: (menuContext) =>
                              _shareCreditPdfWithClient(
                                launchContext: menuContext,
                                sale: sale,
                                bytes: bytes,
                                filename: filename,
                              ),
                        ),
                      if (bytes != null)
                        PdfPanelActionButton(
                          iconAsset: PdfPanelIcons.download,
                          label: 'Guardar factura',
                          onPressed: () async {
                            final saved = await savePdfBytes(
                              bytes: bytes,
                              fileName: downloadFileName,
                            );
                            if (!dialogContext.mounted) return;
                            showCashToast(
                              dialogContext,
                              saved
                                  ? 'Crédito guardado en Descargas como «$downloadFileName».'
                                  : 'No se pudo guardar el crédito en Descargas.',
                              isError: !saved,
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
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
        userSafeErrorMessage(
          e,
          fallback:
              'No se pudo preparar el crédito para WhatsApp. Inténtalo nuevamente.',
        ),
        isError: true,
      );
    }
  }

  String _buildCreditWhatsAppMessage(SaleModel sale, String pdfUrl) {
    final customerName = (sale.customerName ?? '').trim().isEmpty
        ? 'cliente'
        : sale.customerName!.trim();
    return 'Hola $customerName, te compartimos tu factura en PDF.\n'
        'Consulta los abonos y el saldo actualizado en el documento.\n'
        'PDF: $pdfUrl';
  }

  String _shortId(SaleModel sale) => TicketData.fromSale(sale).ticketNumber;
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

class _CreditTopPanel extends StatelessWidget {
  const _CreditTopPanel({required this.searchController});

  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: searchController,
      decoration: historySearchDecoration(
        'Buscar por cliente, teléfono o factura',
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
    required this.onPdf,
    required this.onPrint,
  });

  final SaleModel sale;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPdf;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy').format(toBusinessTime(sale.saleDate!));
    final paid = sale.creditBalance <= 0.009;
    final shortId = TicketData.fromSale(sale).ticketNumber;
    final cashier = (sale.userName ?? '').trim();
    final phone = (sale.customerPhone ?? '').trim();

    if (compact) {
      return HistoryDocumentRow(
        preserveCompactAmount: true,
        document: 'Factura $shortId',
        client: sale.customerName ?? 'Cliente sin nombre',
        date: date,
        extra: cashier,
        amount: formatRdCurrencyAccounting(sale.creditBalance),
        selected: selected,
        onTap: onTap,
        actions: [
          IconButton(
            tooltip: 'Imprimir',
            onPressed: onPrint,
            icon: const Icon(Icons.print_outlined, size: 19),
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'PDF',
            onPressed: onPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
            visualDensity: VisualDensity.compact,
          ),
        ],
      );
    }

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
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
                    child: OutlinedButton.icon(
                      onPressed: onPrint,
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: const Text('Imprimir'),
                    ),
                  ),
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
    this.onDelete,
  });
  final SaleModel sale;
  final VoidCallback onClose, onPayment;
  final VoidCallback? onSettle, onDelete;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Detalle del crédito',
                  style: Theme.of(context).textTheme.titleSmall,
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
        Expanded(
          child: _CreditDetailBody(
            sale: sale,
            onPayment: onPayment,
            onSettle: onSettle,
            onDelete: onDelete,
          ),
        ),
      ],
    ),
  );
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _ItemLine extends ConsumerWidget {
  const _ItemLine({required this.item});

  final SaleItemModel item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final measurementUnitsEnabled =
        ref
            .watch(companySettingsProvider)
            .valueOrNull
            ?.measurementUnitsEnabled ==
        true;
    final qty = formatQuantityForFeature(
      item.qty,
      unit: item.unitSnapshot,
      showMeasurementUnit: measurementUnitsEnabled,
      includeUnitForUnit: true,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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

class _CreditSelectionSummary extends StatelessWidget {
  const _CreditSelectionSummary({
    required this.count,
    required this.refreshing,
  });
  final int count;
  final bool refreshing;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Crédito seleccionado',
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      Text(
        refreshing
            ? 'Actualizando…'
            : '$count ${count == 1 ? 'crédito visible' : 'créditos visibles'}',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
    ],
  );
}

class _CreditResolutionActions extends StatelessWidget {
  const _CreditResolutionActions({
    required this.onPayment,
    required this.onSettle,
    this.onDelete,
  });
  final VoidCallback? onPayment, onSettle, onDelete;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 500;
      final icons =
          constraints.maxWidth >= 420 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.25;
      const shape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
      Widget label(String text) =>
          FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
      Widget action(
        String caption,
        String fullLabel,
        IconData icon,
        VoidCallback? callback, {
        bool primary = false,
        bool danger = false,
      }) {
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icons) ...[Icon(icon, size: 16), const SizedBox(width: 6)],
            Flexible(child: label(caption)),
          ],
        );
        final padding = EdgeInsets.symmetric(horizontal: compact ? 6 : 10);
        return Expanded(
          child: Tooltip(
            message: fullLabel,
            child: primary
                ? FilledButton(
                    onPressed: callback,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: padding,
                      shape: shape,
                    ),
                    child: content,
                  )
                : OutlinedButton(
                    onPressed: callback,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                      padding: padding,
                      shape: shape,
                      foregroundColor: danger ? AppColors.error : null,
                    ),
                    child: content,
                  ),
          ),
        );
      }

      return Row(
        key: const ValueKey('credit-resolution-actions'),
        children: [
          action(
            compact ? 'Abonar' : 'Registrar abono',
            'Registrar abono',
            Icons.payments_outlined,
            onPayment,
            primary: true,
          ),
          const SizedBox(width: 6),
          action('Saldar', 'Saldar crédito', Icons.done_all_rounded, onSettle),
          if (onDelete != null) ...[
            const SizedBox(width: 6),
            action(
              compact ? 'Eliminar' : 'Eliminar crédito',
              'Eliminar crédito',
              Icons.delete_outline_rounded,
              onDelete,
              danger: true,
            ),
          ],
        ],
      );
    },
  );
}

class _CreditFixedInfoColumn extends StatelessWidget {
  const _CreditFixedInfoColumn({
    required this.sale,
    required this.onPayment,
    required this.onSettle,
    this.onDelete,
  });
  final SaleModel? sale;
  final VoidCallback? onPayment, onSettle, onDelete;
  @override
  Widget build(BuildContext context) => sale == null
      ? const _CreditInfoEmptyState()
      : _CreditDetailBody(
          sale: sale!,
          onPayment: onPayment,
          onSettle: onSettle,
          onDelete: onDelete,
        );
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            colorScheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.request_quote_rounded,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FACTURA A CRÉDITO',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '#$number',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
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
                style: theme.textTheme.labelSmall?.copyWith(
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
    this.onDelete,
  });
  final SaleModel sale;
  final VoidCallback? onPayment, onSettle, onDelete;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 500 || constraints.maxHeight < 650;
      final inset = compact ? 8.0 : 12.0;
      final paid = sale.creditBalance <= 0.009;
      final date = sale.saleDate == null
          ? 'Sin fecha'
          : DateFormat('dd/MM/yyyy').format(toBusinessTime(sale.saleDate!));
      final phone = (sale.customerPhone ?? '').trim();
      final cashier = (sale.userName ?? '').trim();
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(inset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CreditDocHeader(
                    number: TicketData.fromSale(sale).ticketNumber,
                    date: date,
                  ),
                  LayoutBuilder(
                    builder: (context, space) {
                      final cellWidth = (space.maxWidth - 12) / 2;
                      return Wrap(
                        key: const ValueKey('credit-client-facts'),
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          SizedBox(
                            width: cellWidth,
                            child: _CreditFactField(
                              label: 'Cliente',
                              value: sale.customerName ?? 'Cliente sin nombre',
                            ),
                          ),
                          SizedBox(
                            width: cellWidth,
                            child: _CreditFactField(
                              label: 'Teléfono',
                              value: phone.isEmpty ? 'No registrado' : phone,
                            ),
                          ),
                          SizedBox(
                            width: cellWidth,
                            child: _CreditFactField(
                              label: 'Cajero',
                              value: cashier.isEmpty
                                  ? 'No registrado'
                                  : cashier,
                            ),
                          ),
                          SizedBox(
                            width: cellWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Estado',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                _CreditStatusDot(paid: paid),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (sale.paymentCashAmount > .009 ||
                      sale.paymentTransferAmount > .009) ...[
                    const SizedBox(height: 8),
                    _PanelSection(
                      title: 'Pagos registrados',
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (sale.paymentCashAmount > .009)
                            Expanded(
                              child: _CreditFactField(
                                label: 'Efectivo',
                                value: formatRdCurrencyAccounting(
                                  sale.paymentCashAmount,
                                ),
                              ),
                            ),
                          if (sale.paymentCashAmount > .009 &&
                              sale.paymentTransferAmount > .009)
                            const SizedBox(width: 12),
                          if (sale.paymentTransferAmount > .009)
                            Expanded(
                              child: _CreditFactField(
                                label: 'Transferencia',
                                value: formatRdCurrencyAccounting(
                                  sale.paymentTransferAmount,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _PanelSection(
                    title: 'Productos',
                    child: Column(
                      children: sale.items
                          .map((item) => _ItemLine(item: item))
                          .toList(growable: false),
                    ),
                  ),
                  if (_creditDisplayNote(sale).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _PanelSection(
                      title: 'Nota',
                      child: Text(
                        _creditDisplayNote(sale),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(inset, 6, inset, compact ? 6 : 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                Row(
                  key: const ValueKey('credit-totals'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _CreditMoneySummary(
                        label: 'Total factura',
                        value: sale.totalSold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CreditMoneySummary(
                        label: 'Total abonado',
                        value: sale.creditPaidAmount,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CreditMoneySummary(
                        label: paid ? 'Saldo saldado' : 'Saldo pendiente',
                        value: sale.creditBalance,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CreditResolutionActions(
                  onPayment: paid ? null : onPayment,
                  onSettle: paid ? null : onSettle,
                  onDelete: onDelete,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _CreditInfoEmptyState extends StatelessWidget {
  const _CreditInfoEmptyState();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surfaceSubtle,
    child: Center(
      child: Text(
        'Selecciona un crédito para ver el detalle',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted),
      ),
    ),
  );
}

class _CreditFactField extends StatelessWidget {
  const _CreditFactField({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 2),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _CreditMoneySummary extends StatelessWidget {
  const _CreditMoneySummary({required this.label, required this.value});
  final String label;
  final double value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
      ),
      const SizedBox(height: 2),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          formatRdCurrencyAccounting(value),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _CreditStatusDot extends StatelessWidget {
  const _CreditStatusDot({required this.paid});

  final bool paid;

  @override
  Widget build(BuildContext context) {
    final color = paid ? AppColors.success : const Color(0xFFB45309);
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
