import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/pdf_action_menu.dart';
import '../cash/cash_dialogs.dart';
import '../cash/cash_turn_menu_button.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';

final salesCreditsProvider = FutureProvider<List<SaleModel>>((ref) {
  return ref.watch(ventasRepositoryProvider).listCredits(includePaid: true);
});

class SalesCreditScreen extends ConsumerStatefulWidget {
  const SalesCreditScreen({super.key});

  @override
  ConsumerState<SalesCreditScreen> createState() => _SalesCreditScreenState();
}

class _SalesCreditScreenState extends ConsumerState<SalesCreditScreen> {
  final _searchController = TextEditingController();
  Timer? _refreshTimer;
  String? _selectedCreditId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.invalidate(salesCreditsProvider);
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      ref.invalidate(salesCreditsProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final credits = ref.watch(salesCreditsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FA),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const FullTechPageHeader(
        title: 'Créditos',
        preferDrawerLeading: true,
        actions: [CashTurnMenuButton(), SizedBox(width: 10)],
      ),
      body: credits.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: _CreditMessage(
            title: 'No se pudieron cargar los créditos',
            detail: error is ApiException ? error.message : '$error',
          ),
        ),
        data: _buildContent,
      ),
    );
  }

  Widget _buildContent(List<SaleModel> rows) {
    final open = rows.where((sale) => sale.creditBalance > 0.009).toList();
    final totalPending = open.fold<double>(
      0,
      (sum, sale) => sum + sale.creditBalance,
    );
    final totalPaid = rows.fold<double>(
      0,
      (sum, sale) => sum + sale.creditPaidAmount,
    );
    final query = _searchController.text.trim().toLowerCase();
    final filtered = rows
        .where((sale) {
          if (query.isEmpty) return true;
          return (sale.customerName ?? '').toLowerCase().contains(query) ||
              sale.id.toLowerCase().contains(query) ||
              (sale.customerPhone ?? '').toLowerCase().contains(query);
        })
        .toList(growable: false);
    final selected = _selectedCredit(rows);

    final mobile = MediaQuery.sizeOf(context).width < 820;

    return Padding(
      padding: EdgeInsets.all(mobile ? 10 : 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                mobile
                    ? Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _CreditStat(
                                  label: 'Abiertos',
                                  value: open.length.toString(),
                                  icon: Icons.credit_score_outlined,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip: 'Actualizar',
                                onPressed: () =>
                                    ref.invalidate(salesCreditsProvider),
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _CreditStat(
                                  label: 'Pendiente',
                                  value: formatRdCurrencyAccounting(
                                    totalPending,
                                  ),
                                  icon: Icons.account_balance_wallet_outlined,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CreditStat(
                                  label: 'Abonado',
                                  value: formatRdCurrencyAccounting(totalPaid),
                                  icon: Icons.payments_outlined,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: _CreditStat(
                              label: 'Créditos abiertos',
                              value: open.length.toString(),
                              icon: Icons.credit_score_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _CreditStat(
                              label: 'Total pendiente',
                              value: formatRdCurrencyAccounting(totalPending),
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _CreditStat(
                              label: 'Abonado',
                              value: formatRdCurrencyAccounting(totalPaid),
                              icon: Icons.payments_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton.filledTonal(
                            tooltip: 'Actualizar',
                            onPressed: () =>
                                ref.invalidate(salesCreditsProvider),
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                const SizedBox(height: 14),
                _CreditSearchBar(controller: _searchController),
                const SizedBox(height: 14),
                Expanded(
                  child: filtered.isEmpty
                      ? const _CreditMessage(
                          title: 'Sin créditos',
                          detail:
                              'Las ventas a crédito aparecerán aquí para seguimiento, abonos y saldos.',
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final sale = filtered[index];
                            return _CreditCard(
                              sale: sale,
                              selected: !mobile && sale.id == _selectedCreditId,
                              onTap: () {
                                if (mobile) {
                                  _openMobileCreditDetail(sale);
                                } else {
                                  setState(() => _selectedCreditId = sale.id);
                                }
                              },
                              onPayment: () => _openPaymentDialog(sale),
                              onPdf: () => _openCreditPdfPreview(sale),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (!mobile && selected != null)
            _CreditDetailPanel(
              sale: selected,
              onClose: () => setState(() => _selectedCreditId = null),
              onPayment: () => _openPaymentDialog(selected),
              onSettle: selected.creditBalance <= 0.009
                  ? null
                  : () => _openPaymentDialog(selected, settle: true),
              onPrint: () => _printCreditPdf(selected),
              onSharePdf: () => _openCreditPdfPreview(selected),
              onWhatsApp: () => _sendCreditWhatsApp(selected),
            ),
        ],
      ),
    );
  }

  Future<void> _openMobileCreditDetail(SaleModel sale) async {
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
      ref.invalidate(salesCreditsProvider);
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

class _CreditSearchBar extends StatelessWidget {
  const _CreditSearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Buscar por cliente, teléfono o factura',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD3E0E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD3E0E7)),
        ),
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
    final mobile = MediaQuery.sizeOf(context).width < 520;
    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD3E0E7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1957E6), size: mobile ? 20 : 24),
          SizedBox(width: mobile ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
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
    required this.selected,
    required this.onTap,
    required this.onPayment,
    required this.onPdf,
  });

  final SaleModel sale;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onPayment;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 620;
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy HH:mm').format(sale.saleDate!.toLocal());
    final paid = sale.creditBalance <= 0.009;
    final shortId = sale.id.length <= 8 ? sale.id : sale.id.substring(0, 8);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1957E6)
                  : const Color(0xFFD3E0E7),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: mobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CreditCardInfo(
                      sale: sale,
                      date: date,
                      shortId: shortId,
                      paid: paid,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onPdf,
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                            ),
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
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _CreditCardInfo(
                        sale: sale,
                        date: date,
                        shortId: shortId,
                        paid: paid,
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: onPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: paid ? null : onPayment,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Abonar'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CreditCardInfo extends StatelessWidget {
  const _CreditCardInfo({
    required this.sale,
    required this.date,
    required this.shortId,
    required this.paid,
  });

  final SaleModel sale;
  final String date;
  final String shortId;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          sale.customerName ?? 'Sin cliente',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(
          'Crédito: $date · Factura $shortId',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF52657A)),
        ),
        const SizedBox(height: 8),
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
      ],
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
  });

  final SaleModel sale;
  final VoidCallback onClose;
  final VoidCallback onPayment;
  final VoidCallback? onSettle;
  final VoidCallback onPrint;
  final VoidCallback onSharePdf;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy HH:mm').format(sale.saleDate!.toLocal());
    final paid = sale.creditBalance <= 0.009;
    final mobile = MediaQuery.sizeOf(context).width < 620;
    return Container(
      width: mobile ? double.infinity : 460,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detalle del crédito',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Factura ${sale.id.length <= 8 ? sale.id : sale.id.substring(0, 8)}',
                        style: const TextStyle(color: Color(0xFF64748B)),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: danger ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 4),
          Text(
            formatRdCurrencyAccounting(value),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: danger ? const Color(0xFFBE123C) : const Color(0xFF111827),
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
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$qty x ${formatRdCurrencyAccounting(item.priceSoldUnit)}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatRdCurrencyAccounting(item.subtotalSold),
            style: const TextStyle(fontWeight: FontWeight.w900),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFEEF0) : const Color(0xFFF6FAFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: danger ? const Color(0xFFF3B8C2) : const Color(0xFFD3E0E7),
        ),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.paid});

  final bool paid;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: paid ? const Color(0xFFE8F8EF) : const Color(0xFFFFEEF0),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          paid ? 'Saldado' : 'Pendiente',
          style: TextStyle(
            color: paid ? const Color(0xFF047857) : const Color(0xFFBE123C),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
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
