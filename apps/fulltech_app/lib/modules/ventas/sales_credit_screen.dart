import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../cash/cash_dialogs.dart';
import '../cash/cash_turn_menu_button.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';

final salesCreditsProvider = FutureProvider<List<SaleModel>>((ref) {
  return ref.watch(ventasRepositoryProvider).listCredits(includePaid: true);
});

class SalesCreditScreen extends ConsumerWidget {
  const SalesCreditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: credits.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _CreditMessage(
            title: 'No se pudieron cargar los créditos',
            detail: error is ApiException ? error.message : '$error',
          ),
          data: (rows) {
            final open = rows
                .where((sale) => sale.creditBalance > 0.009)
                .toList(growable: false);
            final total = open.fold<double>(
              0,
              (sum, sale) => sum + sale.creditBalance,
            );
            return Column(
              children: [
                Row(
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
                        value: formatRdCurrencyAccounting(total),
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: 'Actualizar',
                      onPressed: () => ref.invalidate(salesCreditsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: rows.isEmpty
                      ? const _CreditMessage(
                          title: 'Sin créditos',
                          detail:
                              'Las ventas a crédito aparecerán aquí para seguimiento y abonos.',
                        )
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _CreditCard(
                              sale: rows[index],
                              onPayment: () =>
                                  _openPaymentDialog(context, ref, rows[index]),
                              onPdf: () => _printCreditPdf(rows[index]),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openPaymentDialog(
    BuildContext context,
    WidgetRef ref,
    SaleModel sale,
  ) async {
    final cashCtrl = TextEditingController();
    final transferCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('Abono de ${sale.customerName ?? 'cliente'}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CreditInput(label: 'Efectivo', controller: cashCtrl),
                const SizedBox(height: 10),
                _CreditInput(label: 'Transferencia', controller: transferCtrl),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Saldo pendiente: ${formatRdCurrencyAccounting(sale.creditBalance)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Guardar abono'),
            ),
          ],
        ),
      );
      if (saved != true || !context.mounted) return;
      final cash = parseDominicanAmount(cashCtrl.text) ?? 0;
      final transfer = parseDominicanAmount(transferCtrl.text) ?? 0;
      await ref
          .read(ventasRepositoryProvider)
          .addCreditPayment(
            saleId: sale.id,
            cashAmount: cash,
            transferAmount: transfer,
            note: noteCtrl.text,
          );
      ref.invalidate(salesCreditsProvider);
      if (!context.mounted) return;
      showCashToast(context, 'Abono registrado');
    } catch (error) {
      if (!context.mounted) return;
      showCashToast(
        context,
        error is ApiException ? error.message : '$error',
        isError: true,
      );
    } finally {
      cashCtrl.dispose();
      transferCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<void> _printCreditPdf(SaleModel sale) async {
    final doc = pw.Document();
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy HH:mm').format(sale.saleDate!.toLocal());
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(28),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Estado de crédito',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text('Cliente: ${sale.customerName ?? 'Sin cliente'}'),
              pw.Text('Factura: ${sale.id}'),
              pw.Text('Fecha: $date'),
              pw.SizedBox(height: 16),
              pw.Text(
                'Total factura: ${formatRdCurrencyAccounting(sale.totalSold)}',
              ),
              pw.Text(
                'Pagado: ${formatRdCurrencyAccounting(sale.creditPaidAmount)}',
              ),
              pw.Text(
                'Pendiente: ${formatRdCurrencyAccounting(sale.creditBalance)}',
              ),
              pw.SizedBox(height: 24),
              pw.Text(
                'Carta de compromiso',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Por medio de la presente se deja constancia de que el cliente '
                '${sale.customerName ?? ''} mantiene un saldo pendiente de '
                '${formatRdCurrencyAccounting(sale.creditBalance)} correspondiente a la factura indicada. '
                'Los abonos realizados serán aplicados al saldo hasta completar la deuda.',
              ),
            ],
          ),
        ),
      ),
    );
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }
}

class _CreditInput extends StatelessWidget {
  const _CreditInput({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: r'RD$ ',
        border: const OutlineInputBorder(),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD3E0E7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1957E6)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
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

class _CreditCard extends StatelessWidget {
  const _CreditCard({
    required this.sale,
    required this.onPayment,
    required this.onPdf,
  });

  final SaleModel sale;
  final VoidCallback onPayment;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    final date = sale.saleDate == null
        ? 'Sin fecha'
        : DateFormat('dd/MM/yyyy HH:mm').format(sale.saleDate!.toLocal());
    final paid = sale.creditBalance <= 0.009;
    final shortId = sale.id.length <= 8 ? sale.id : sale.id.substring(0, 8);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD3E0E7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.customerName ?? 'Sin cliente',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text('Tomó crédito: $date · Factura $shortId'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        'Total ${formatRdCurrencyAccounting(sale.totalSold)}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Pagado ${formatRdCurrencyAccounting(sale.creditPaidAmount)}',
                      ),
                    ),
                    Chip(
                      label: Text(
                        'Debe ${formatRdCurrencyAccounting(sale.creditBalance)}',
                      ),
                      backgroundColor: paid
                          ? const Color(0xFFE8F8EF)
                          : const Color(0xFFFFEEF0),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: onPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: paid ? null : onPayment,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Abonar'),
          ),
        ],
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
