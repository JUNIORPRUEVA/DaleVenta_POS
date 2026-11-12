import 'package:flutter/material.dart';

import '../../../../core/support/support_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/assistant_whatsapp_service.dart';
import '../../domain/assistant_message_builder.dart';
import '../../domain/assistant_models.dart';
import '../widgets/assistant_widgets.dart';

/// Formulario de «Reportar avería».
///
/// No persiste nada ni asume que el reporte fue recibido: prepara un mensaje y
/// lo entrega a WhatsApp. Si la apertura falla, el texto del usuario se conserva
/// y queda disponible para copiar.
class AssistantFaultFormView extends StatefulWidget {
  const AssistantFaultFormView({super.key, required this.contextData});

  final AssistantMessageContext contextData;

  @override
  State<AssistantFaultFormView> createState() => _AssistantFaultFormViewState();
}

class _AssistantFaultFormViewState extends State<AssistantFaultFormView> {
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _extraCtrl = TextEditingController();
  AssistantSupportModule _module = AssistantSupportModule.billing;
  bool _showPreview = false;
  bool _busy = false;
  bool _noticeIsError = false;
  String? _notice;
  String? _descriptionError;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _extraCtrl.dispose();
    super.dispose();
  }

  String get _message => AssistantMessageBuilder.fault(
    module: _module,
    description: _descriptionCtrl.text,
    extra: _extraCtrl.text,
    companyName: widget.contextData.companyName,
    platformLabel: widget.contextData.platformLabel,
    appVersion: widget.contextData.appVersion,
  );

  bool _validate() {
    final description = _descriptionCtrl.text.trim();
    if (description.isEmpty) {
      setState(() {
        _descriptionError = 'Describe el problema para poder ayudarte.';
      });
      return false;
    }
    if (description.length < 10) {
      setState(() {
        _descriptionError = 'Escribe al menos 10 caracteres de detalle.';
      });
      return false;
    }
    setState(() => _descriptionError = null);
    return true;
  }

  Future<void> _send() async {
    if (_busy) return;
    if (!_validate()) return;
    setState(() {
      _busy = true;
      _notice = null;
      _showPreview = true;
    });
    final result = await AssistantWhatsAppService.send(_message);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _noticeIsError = !result.opened;
      _notice = result.opened
          ? 'WhatsApp abierto con el reporte preparado. Envíalo desde el chat para que soporte lo reciba.'
          : result.copied
          ? 'No se pudo abrir WhatsApp. Copiamos el reporte: pégalo en el chat de soporte ${SupportConfig.phoneDisplay}.'
          : 'No se pudo abrir WhatsApp. Usa «Copiar reporte» y envíalo al ${SupportConfig.phoneDisplay}.';
    });
  }

  Future<void> _copy() async {
    if (!_validate()) return;
    final copied = await AssistantWhatsAppService.copyText(_message);
    if (!mounted) return;
    setState(() {
      _noticeIsError = !copied;
      _notice = copied
          ? 'Reporte copiado. Pégalo en el chat de soporte ${SupportConfig.phoneDisplay}.'
          : 'No se pudo copiar el reporte.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        const Text(
          'Reportar avería',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Cuéntanos qué falla y lo enviamos a soporte por WhatsApp.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 12),
        AssistantCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AssistantFieldLabel('Módulo afectado'),
              DropdownButtonFormField<AssistantSupportModule>(
                initialValue: _module,
                isDense: true,
                isExpanded: true,
                decoration: assistantFieldDecoration(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
                items: [
                  for (final module in AssistantSupportModule.values)
                    DropdownMenuItem<AssistantSupportModule>(
                      value: module,
                      child: Text(module.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _module = value);
                      },
              ),
              const SizedBox(height: 12),
              const AssistantFieldLabel(
                'Descripción del problema',
                required: true,
              ),
              TextField(
                controller: _descriptionCtrl,
                enabled: !_busy,
                minLines: 3,
                maxLines: 5,
                maxLength: 600,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  if (_descriptionError != null) {
                    setState(() => _descriptionError = null);
                  }
                },
                decoration: assistantFieldDecoration(
                  hint:
                      'Ejemplo: al cobrar sale un mensaje de error y no guarda la venta.',
                  errorText: _descriptionError,
                ),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              const AssistantFieldLabel('Información adicional (opcional)'),
              TextField(
                controller: _extraCtrl,
                enabled: !_busy,
                minLines: 2,
                maxLines: 3,
                maxLength: 300,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                decoration: assistantFieldDecoration(
                  hint: 'Cuándo ocurre, qué intentaste, si pasa siempre...',
                ),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              _ContextSummary(contextData: widget.contextData),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _send,
                style: assistantPrimaryButtonStyle(),
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: const Text('Enviar por WhatsApp'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _copy,
              style: assistantSecondaryButtonStyle(),
              child: const Text('Copiar'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => setState(() => _showPreview = !_showPreview),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondary,
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 30),
            alignment: Alignment.centerLeft,
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          icon: Icon(
            _showPreview
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 15,
          ),
          label: Text(_showPreview ? 'Ocultar mensaje' : 'Revisar mensaje'),
        ),
        if (_showPreview) ...[
          const SizedBox(height: 6),
          AssistantMessagePreview(message: _message),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 10),
          AssistantInlineNotice(message: _notice!, isError: _noticeIsError),
        ],
        const SizedBox(height: 12),
        const Text(
          'El reporte no se guarda en la app ni se envía solo: se abre WhatsApp '
          'con el texto preparado para que tú lo envíes.',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 10.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ContextSummary extends StatelessWidget {
  const _ContextSummary({required this.contextData});

  final AssistantMessageContext contextData;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if ((contextData.platformLabel ?? '').trim().isNotEmpty)
        contextData.platformLabel!.trim(),
      if ((contextData.appVersion ?? '').trim().isNotEmpty)
        'v${contextData.appVersion!.trim()}',
      if ((contextData.companyName ?? '').trim().isNotEmpty)
        contextData.companyName!.trim(),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 13,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Se incluye: ${parts.join(' · ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
