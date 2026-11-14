import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/debug/app_error_reporter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../modules/ventas/data/ventas_repository.dart';
import '../../../modules/ventas/sales_models.dart';
import '../data/ecf_connection_guard.dart';
import '../data/ecf_repository.dart';
import '../ecf_sale_fiscal.dart';
import '../ecf_status_presentation.dart';
import 'ecf_document_print_action.dart';

String saleFiscalStatusLabel(EcfSaleFiscalDocument document) =>
    document.conditional
    ? 'Aceptado condicional'
    : presentEcfStatus(document.status).label;

class EcfSaleHistoryBadge extends StatelessWidget {
  const EcfSaleHistoryBadge({super.key, this.fiscal, this.intent});
  final EcfSaleFiscal? fiscal;
  final String? intent;
  @override
  Widget build(BuildContext context) {
    final type = fiscal?.requiresReview == true
        ? 'e-CF'
        : fiscal?.original?.documentType ?? fiscal?.intent ?? intent;
    if (type != 'E31' && type != 'E32' && type != 'e-CF') {
      return const SizedBox.shrink();
    }
    final original = fiscal?.original;
    final status = fiscal?.requiresReview == true
        ? 'Requiere revisión'
        : original == null
        ? 'Pendiente'
        : saleFiscalStatusLabel(original);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Tooltip(
        message: '$type · ${original?.encf ?? "Sin numerar"} · $status',
        child: Text(
          '$type · ${original?.encf ?? "Sin numerar"}\n$status',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Existing sale/refund documents and guarded fiscal actions, without a second
/// financial operation. Server statuses remain the only fiscal authority.
class EcfSaleHistoryPanel extends ConsumerStatefulWidget {
  const EcfSaleHistoryPanel({super.key, required this.sale});
  final SaleModel sale;
  @override
  ConsumerState<EcfSaleHistoryPanel> createState() =>
      _EcfSaleHistoryPanelState();
}

class _EcfSaleHistoryPanelState extends ConsumerState<EcfSaleHistoryPanel> {
  bool _busy = false;
  bool _uncertain = false;
  void _notice(String title, String message) => AppFeedback.showToast(
    context,
    title: title,
    body: message,
    kind: AppFeedbackKind.info,
    duration: const Duration(seconds: 4),
    dedupeKey: 'ecf-history',
  );

  Future<void> _refresh() async {
    try {
      final updated = await ref.refresh(
        ecfSalesFiscalProvider(widget.sale.id).future,
      );
      if (mounted && updated.containsKey(widget.sale.id)) {
        setState(() => _uncertain = false);
      }
    } catch (_) {
      if (mounted) {
        _notice('Sin conexión', 'No se pudo actualizar el estado fiscal.');
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || _uncertain) return;
    setState(() => _busy = true);
    try {
      await operation();
      ref.invalidate(ecfSalesFiscalProvider);
      ref.invalidate(ecfDocumentsProvider);
      ref.invalidate(ecfCountersProvider);
    } on EcfConnectionException catch (error) {
      if (mounted) {
        setState(() => _uncertain = error.uncertain);
        _notice(error.noticeTitle, error.message);
      }
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Historial de ventas: acción fiscal',
        notifyUser: false,
      );
      if (mounted) {
        _notice(
          'No se pudo completar',
          'Actualiza el estado fiscal antes de continuar.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send(EcfSaleFiscalDocument document) => _run(() async {
    final outcome = await ref
        .read(ecfRepositoryProvider)
        .dispatchDosa(document.documentId);
    if (mounted) {
      _notice(
        outcome.result == 'FISCAL_RESULT_RECORDED'
            ? 'Resultado fiscal registrado'
            : 'Comprobante actualizado',
        outcome.message,
      );
    }
  });

  Future<void> _prepare(EcfSaleFiscal fiscal) => _run(() async {
    final repo = ref.read(ecfRepositoryProvider);
    final outcome = fiscal.intent == 'E31'
        ? await repo.prepareFromSale(
            saleId: widget.sale.id,
            paymentType: widget.sale.paymentMethod == 'credit' ? 2 : 1,
            incomeType: 1,
            sequenceDueDate: fiscal.sequenceDueDate,
          )
        : await repo.prepareConsumoFromSale(
            saleId: widget.sale.id,
            paymentType: widget.sale.paymentMethod == 'credit' ? 2 : 1,
            incomeType: 1,
          );
    if (mounted) {
      _notice(
        outcome.ok ? 'Comprobante preparado' : 'Comprobante pendiente',
        outcome.ok ? 'El documento está listo para su envío.' : outcome.message,
      );
    }
  });

  Future<void> _recover(String refundId) => _run(() async {
    final result = await ref
        .read(ventasRepositoryProvider)
        .retryRefundFiscal(widget.sale.id, refundId);
    if (mounted) {
      _notice(
        result.fiscalPending ? 'E34 pendiente' : 'E34 preparada',
        result.fiscalPending
            ? result.fiscalPendingMessage ??
                  'La devolución conserva una revisión fiscal pendiente.'
            : 'La nota está preparada. No se repitió la devolución.',
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ecfSalesFiscalProvider(widget.sale.id));
    final user = ref.watch(authStateProvider).user;
    final canPrepare = hasUserPermission(
      user,
      AppPermission.prepareEcfDocuments,
    );
    final canRefund = hasUserPermission(user, AppPermission.refundSales);
    final canView = hasUserPermission(user, AppPermission.viewEcfDocuments);
    final fiscal = state.valueOrNull?[widget.sale.id];
    final expected = const {
      'E31',
      'E32',
    }.contains(widget.sale.fiscalVoucherType);
    if (fiscal?.isElectronic != true && !expected) {
      return const SizedBox.shrink();
    }
    final disabled = _busy || _uncertain || fiscal?.requiresReview == true;
    Widget document(EcfSaleFiscalDocument doc) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '${doc.documentType} · ${doc.encf ?? "Sin numerar"}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(
            '${saleFiscalStatusLabel(doc)}${doc.environment == "SANDBOX" ? " · TEST" : ""}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (canPrepare && doc.canDispatch)
            TextButton.icon(
              onPressed: disabled ? null : () => _send(doc),
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(_busy ? 'Procesando…' : 'Emitir ${doc.documentType}'),
            ),
          if (canPrepare && const {'UNKNOWN_RESULT', 'SEND_IN_PROGRESS', 'DGII_STATUS_PENDING'}.contains(doc.status))
            TextButton.icon(
              onPressed: disabled ? null : () => _run(() async {
                final outcome=await ref.read(ecfRepositoryProvider).recoverDosa(doc.documentId);
                if(mounted) _notice('Resultado fiscal',outcome.message);
              }),
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Verificar con DOSA'),
            ),
          if (canView && doc.documentType == 'E34')
            EcfDocumentPrintAction(documentId: doc.documentId),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Facturación electrónica',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                onPressed: _busy ? null : _refresh,
                tooltip: 'Actualizar estado fiscal',
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (state.isLoading) const LinearProgressIndicator(),
          if (state.hasError)
            const Text('No se pudo consultar el estado fiscal.'),
          if (fiscal?.requiresReview == true)
            const Text(
              'Hay más de un comprobante vinculado. Requiere revisión.',
            ),
          for (final doc in fiscal?.documents ?? <EcfSaleFiscalDocument>[])
            document(doc),
          if (fiscal != null &&
              fiscal.documents.isEmpty &&
              canPrepare &&
              !fiscal.requiresReview)
            TextButton.icon(
              onPressed: disabled ? null : () => _prepare(fiscal),
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Preparar comprobante pendiente'),
            ),
          if (_uncertain)
            const Text(
              'Resultado pendiente de verificar. Actualiza el estado antes de continuar.',
            ),
          if (fiscal != null &&
              (fiscal.creditNotes.isNotEmpty ||
                  fiscal.pendingRefundIds.isNotEmpty))
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Notas de crédito (${fiscal.creditNotes.length})'),
              children: [
                for (final doc in fiscal.creditNotes) document(doc),
                for (final refundId in fiscal.pendingRefundIds)
                  if (canRefund)
                    TextButton.icon(
                      onPressed: disabled ? null : () => _recover(refundId),
                      icon: const Icon(Icons.restore_page_outlined, size: 18),
                      label: const Text('Preparar E34 pendiente'),
                    ),
              ],
            ),
        ],
      ),
    );
  }
}
