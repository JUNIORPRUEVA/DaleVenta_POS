import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../utils/pdf_file_actions.dart';
import '../utils/pdf_share.dart';

enum PdfDocumentAction {
  print('Imprimir', Icons.print_rounded),
  share('Compartir PDF', Icons.ios_share_rounded),
  shareClient('Compartir con cliente', Icons.person_outline_rounded),
  save('Guardar en descargas', Icons.download_rounded);

  const PdfDocumentAction(this.label, this.icon);

  final String label;
  final IconData icon;
}

class PdfActionMenu extends StatelessWidget {
  const PdfActionMenu({
    super.key,
    required this.bytes,
    required this.fileName,
    this.compact = false,
    this.onShareWithClient,
    this.shareClientLabel = '',
    this.circular = false,
    this.iconAsset,
  });

  final Uint8List bytes;
  final String fileName;
  final bool compact;
  final Future<void> Function(BuildContext context)? onShareWithClient;
  final String shareClientLabel;

  /// Muestra el disparador como botón circular flotante en vez de la píldora.
  final bool circular;

  /// Icono de imagen del disparador circular; si falta se usa el de Material.
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PdfDocumentAction>(
      tooltip: 'Opciones de documento',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 10,
      color: Colors.white,
      onSelected: (action) => _runAction(context, action),
      itemBuilder: (context) => [
        for (final action in PdfDocumentAction.values)
          if (action != PdfDocumentAction.shareClient ||
              onShareWithClient != null)
            PopupMenuItem<PdfDocumentAction>(
              value: action,
              child: Row(
                children: [
                  Icon(action.icon, size: 18, color: const Color(0xFF1957E6)),
                  const SizedBox(width: 10),
                  Text(
                    action.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1D2430),
                    ),
                  ),
                ],
              ),
            ),
      ],
      child: circular
          ? _PdfMenuCircleTrigger(iconAsset: iconAsset)
          : Container(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 9 : 11,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1957E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.ios_share_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'Compartir',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Future<void> _runAction(
    BuildContext context,
    PdfDocumentAction action,
  ) async {
    switch (action) {
      case PdfDocumentAction.print:
        await Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
        return;
      case PdfDocumentAction.share:
        final outcome = await sharePdfWithSystem(
          bytes: bytes,
          fileName: fileName,
        );
        if (!context.mounted) return;
        switch (outcome) {
          case PdfShareOutcome.shared:
            return;
          case PdfShareOutcome.savedToDownloads:
            _showMessage(
              context,
              'No se pudo abrir Compartir. El PDF se guardó en Descargas.',
            );
            return;
          case PdfShareOutcome.failed:
            _showMessage(
              context,
              'No se pudo compartir el PDF. Inténtalo nuevamente.',
            );
            return;
        }
      case PdfDocumentAction.shareClient:
        await onShareWithClient?.call(context);
        return;
      case PdfDocumentAction.save:
        final saved = await savePdfBytes(bytes: bytes, fileName: fileName);
        if (!context.mounted) return;
        _showMessage(
          context,
          saved ? 'PDF guardado en descargas.' : 'No se pudo guardar el PDF.',
        );
        return;
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Disparador circular del menú, para acompañar a las acciones flotantes.
class _PdfMenuCircleTrigger extends StatelessWidget {
  const _PdfMenuCircleTrigger({this.iconAsset});

  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    final asset = iconAsset;
    return Semantics(
      button: true,
      label: 'Compartir o imprimir el PDF',
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: const Color(0x33000000),
        shape: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: asset == null
                ? const Icon(
                    Icons.ios_share_rounded,
                    size: 18,
                    color: Color(0xFF1F2937),
                  )
                : Image.asset(
                    asset,
                    width: 18,
                    height: 18,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
          ),
        ),
      ),
    );
  }
}
