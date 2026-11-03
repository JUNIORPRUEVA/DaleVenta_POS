import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_feedback.dart';
import '../data/ecf_certification_repository.dart';
import '../ecf_certification_models.dart';

/// Incorporación guiada del XML de postulación.
///
/// El cliente lo obtiene del Portal de Certificación de la DGII y lo sube aquí.
/// FullPOS lo valida (estructura y seguridad) y lo guarda como evidencia de la
/// empresa. Subirlo **no** es presentarlo ante la DGII ni una aprobación.
class EcfPostulationXmlCard extends ConsumerStatefulWidget {
  const EcfPostulationXmlCard({super.key, this.onUploaded, this.pickFile});

  final VoidCallback? onUploaded;

  /// Selector inyectable para pruebas.
  final Future<({String name, List<int> bytes})?> Function()? pickFile;

  @override
  ConsumerState<EcfPostulationXmlCard> createState() =>
      _EcfPostulationXmlCardState();
}

class _EcfPostulationXmlCardState extends ConsumerState<EcfPostulationXmlCard> {
  String? _fileName;
  List<int>? _bytes;
  bool _busy = false;
  String? _error;
  EcfPostulationXmlResult? _result;

  Future<void> _pick() async {
    final picker = widget.pickFile;
    final picked = picker != null ? await picker() : await _pickWithDialog();
    if (picked == null) return;
    setState(() {
      _fileName = picked.name;
      _bytes = picked.bytes;
      _error = null;
      _result = null;
    });
  }

  Future<({String name, List<int> bytes})?> _pickWithDialog() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['xml'],
    );
    final file = (result == null || result.files.isEmpty)
        ? null
        : result.files.first;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    return (name: file.name, bytes: bytes);
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    final name = _fileName;
    if (bytes == null || name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(ecfCertificationRepositoryProvider)
          .uploadPostulationXml(bytes: bytes, fileName: name);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
      AppFeedback.showToast(
        context,
        title: result.duplicate ? 'Documento ya registrado' : 'XML incorporado',
        body:
            'Quedó validado y asociado a tu expediente. Todavía no es una '
            'presentación ante la DGII.',
        kind: AppFeedbackKind.success,
        dedupeKey: 'ecf_postulation_xml',
      );
      widget.onUploaded?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    if (raw.contains('ECF_POSTULATION_XML_TOO_LARGE')) {
      return 'El archivo supera el tamaño máximo (1 MB).';
    }
    if (raw.contains('ECF_POSTULATION_XML_DOCTYPE') ||
        raw.contains('ECF_POSTULATION_XML_ENTITY') ||
        raw.contains('ECF_POSTULATION_XML_EXTERNAL_REF')) {
      return 'El XML contiene instrucciones no permitidas (DTD o entidades).';
    }
    if (raw.contains('ECF_POSTULATION_XML_ENCODING')) {
      return 'El XML debe estar en UTF-8.';
    }
    if (raw.contains('ECF_POSTULATION_XML_WRONG_STAGE')) {
      return 'Ese archivo es un comprobante electrónico, no el XML de postulación.';
    }
    if (raw.contains('ECF_POSTULATION_XML_RNC_MISMATCH')) {
      return 'El RNC del documento no corresponde a tu empresa.';
    }
    if (raw.contains('ECF_POSTULATION_XML_NOT_XML')) {
      return 'El archivo no es un XML válido.';
    }
    return 'No se pudo incorporar el documento. Revisa el archivo e inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _fileName ?? 'Sin XML de postulación cargado',
                key: const ValueKey('ecf_postulation_xml_file_name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: _fileName == null
                      ? FontWeight.w400
                      : FontWeight.w600,
                  color: _fileName == null
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF1F2A37),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _pick,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
              child: Text(_fileName == null ? 'Seleccionar' : 'Cambiar'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('ecf_postulation_xml_upload'),
            onPressed: _busy || _bytes == null ? null : _upload,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined, size: 18),
            label: Text(_busy ? 'Validando…' : 'Incorporar XML'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              color: const Color(0xFFB91C1C),
              height: 1.3,
            ),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFB7E4C7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _result!.duplicate
                      ? 'Este XML ya estaba registrado'
                      : 'XML validado y asociado al expediente',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2A37),
                  ),
                ),
                if (_result!.rootElement.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Elemento raíz: ${_result!.rootElement} · '
                      'Huella ${_result!.sha256Prefix}…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                for (final note in _result!.notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      note,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        height: 1.3,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
