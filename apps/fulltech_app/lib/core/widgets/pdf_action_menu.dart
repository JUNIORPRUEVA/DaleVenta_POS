import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../utils/pdf_file_actions.dart';

enum PdfDocumentAction {
  print('Imprimir', Icons.print_rounded),
  share('Compartir PDF', Icons.ios_share_rounded),
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
  });

  final Uint8List bytes;
  final String fileName;
  final bool compact;
  final Future<void> Function(BuildContext context)? onShareWithClient;
  final String shareClientLabel;

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
      child: Container(
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
            const Icon(Icons.ios_share_rounded, size: 18, color: Colors.white),
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
        await Printing.sharePdf(bytes: bytes, filename: fileName);
        return;
      case PdfDocumentAction.save:
        final saved = await savePdfBytes(bytes: bytes, fileName: fileName);
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'PDF guardado en descargas.'
                  : 'No se pudo guardar el PDF.',
            ),
          ),
        );
        return;
    }
  }
}
