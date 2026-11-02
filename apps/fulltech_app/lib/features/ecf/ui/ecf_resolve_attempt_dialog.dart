import 'package:flutter/material.dart';

/// Resultado del diálogo de reconciliación de un intento bloqueado.
class EcfResolveAttemptInput {
  const EcfResolveAttemptInput({required this.evidence, required this.note});

  final String evidence;
  final String note;
}

/// Diálogo que obliga a dejar evidencia antes de desbloquear un intento.
///
/// Vive en su propio widget con estado para que los `TextEditingController`
/// se liberen cuando el diálogo termina de desmontarse (no antes de la
/// animación de salida).
class EcfResolveAttemptDialog extends StatefulWidget {
  const EcfResolveAttemptDialog({
    super.key,
    required this.operation,
    required this.applied,
  });

  final String operation;
  final bool applied;

  @override
  State<EcfResolveAttemptDialog> createState() =>
      _EcfResolveAttemptDialogState();
}

class _EcfResolveAttemptDialogState extends State<EcfResolveAttemptDialog> {
  final _evidence = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _evidence.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final evidence = _evidence.text.trim();
    if (evidence.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pop(EcfResolveAttemptInput(evidence: evidence, note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    const hint = TextStyle(fontSize: 11, color: Color(0xFF64748B));
    return AlertDialog(
      title: Text(
        widget.applied
            ? 'Confirmar que sí se aplicó'
            : 'Confirmar que no se aplicó',
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Operación: ${widget.operation}',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('ecf_resolve_evidence'),
              controller: _evidence,
              decoration: const InputDecoration(
                labelText: 'Referencia de la evidencia',
                helperText: 'Acuse, radicado o comprobante del proveedor.',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('ecf_resolve_note'),
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Nota de la decisión',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Sin evidencia no se puede desbloquear: el intento quedaría en '
              'revisión humana.',
              style: hint,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Registrar decisión'),
        ),
      ],
    );
  }
}
