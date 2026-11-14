import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/user_safe_error_text.dart';
import '../../../core/printing/ecf_document_pdf.dart';
import '../../../core/printing/models/ticket_data.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/widgets/pdf_action_menu.dart';
import '../../../core/widgets/pdf_preview_panel.dart';
import '../data/ecf_repository.dart';

/// Uses the installed sales printer; it never emits or changes a document.
class EcfDocumentPrintAction extends ConsumerStatefulWidget {
  const EcfDocumentPrintAction({super.key, required this.documentId});
  final String documentId;
  @override
  ConsumerState<EcfDocumentPrintAction> createState() =>
      _EcfDocumentPrintActionState();
}

class _EcfDocumentPrintActionState
    extends ConsumerState<EcfDocumentPrintAction> {
  bool _busy = false;
  String? _error;
  Future<void> _open({required bool ticket}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Fresh backend projection: no stale QR or credentials in client state.
      final document = await ref
          .read(ecfRepositoryProvider)
          .printDocument(widget.documentId);
      if (!mounted) return;
      if (ticket) {
        final result = await ref
            .read(unifiedTicketPrinterProvider)
            .printTicket(TicketData.fromEcf(document), overrideCopies: 1);
        if (!result.success && mounted) {
          setState(() => _error = result.message);
        }
      } else {
        final bytes = await buildEcfDocumentPdf(document);
        if (!mounted) return;
        await showPdfPreviewPanel<void>(
          context: context,
          barrierLabel: 'Comprobante electrónico',
          builder: (dialogContext) => Column(
            children: [
              PdfPreviewPanelHeader(
                title: document.label,
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
              Expanded(
                child: PdfPreviewStage(
                  bytes: bytes,
                  actions: [
                    PdfActionMenu(
                      bytes: bytes,
                      fileName: '${document.encf}.pdf',
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    } catch (error, stack) {
      debugPrint('No se pudo preparar la impresión fiscal: $error\n$stack');
      if (mounted) {
        setState(
          () => _error = userSafeErrorMessage(
            error,
            fallback:
                'No se pudo preparar el comprobante. Revisa la conexión y vuelve a intentar.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 8,
      runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _open(ticket: true),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir ticket'),
          ),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _open(ticket: false),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Ver PDF fiscal'),
          ),
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
