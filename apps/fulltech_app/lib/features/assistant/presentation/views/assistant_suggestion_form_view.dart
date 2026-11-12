import 'package:flutter/material.dart';

import '../../../../core/support/support_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/assistant_whatsapp_service.dart';
import '../../domain/assistant_message_builder.dart';
import '../../domain/assistant_models.dart';
import '../widgets/assistant_widgets.dart';

/// Formulario de «Sugerir mejora».
///
/// Igual que el reporte de avería: no guarda nada, prepara un mensaje y lo
/// entrega a WhatsApp; si falla la apertura, conserva el texto para copiarlo.
class AssistantSuggestionFormView extends StatefulWidget {
  const AssistantSuggestionFormView({super.key, required this.contextData});

  final AssistantMessageContext contextData;

  @override
  State<AssistantSuggestionFormView> createState() =>
      _AssistantSuggestionFormViewState();
}

class _AssistantSuggestionFormViewState
    extends State<AssistantSuggestionFormView> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  bool _showPreview = false;
  bool _busy = false;
  bool _noticeIsError = false;
  String? _notice;
  String? _titleError;
  String? _descriptionError;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  String get _message => AssistantMessageBuilder.suggestion(
    title: _titleCtrl.text,
    description: _descriptionCtrl.text,
    companyName: widget.contextData.companyName,
    platformLabel: widget.contextData.platformLabel,
    appVersion: widget.contextData.appVersion,
  );

  bool _validate() {
    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    String? titleError;
    String? descriptionError;
    if (title.isEmpty) {
      titleError = 'Escribe un título breve.';
    } else if (title.length < 4) {
      titleError = 'El título es demasiado corto.';
    }
    if (description.isEmpty) {
      descriptionError = 'Describe tu idea.';
    } else if (description.length < 10) {
      descriptionError = 'Escribe al menos 10 caracteres de detalle.';
    }
    setState(() {
      _titleError = titleError;
      _descriptionError = descriptionError;
    });
    return titleError == null && descriptionError == null;
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
          ? 'WhatsApp abierto con la sugerencia preparada. Envíala desde el chat.'
          : result.copied
          ? 'No se pudo abrir WhatsApp. Copiamos la sugerencia: pégalo en el chat de soporte ${SupportConfig.phoneDisplay}.'
          : 'No se pudo abrir WhatsApp. Usa «Copiar» y envíalo al ${SupportConfig.phoneDisplay}.';
    });
  }

  Future<void> _copy() async {
    if (!_validate()) return;
    final copied = await AssistantWhatsAppService.copyText(_message);
    if (!mounted) return;
    setState(() {
      _noticeIsError = !copied;
      _notice = copied
          ? 'Sugerencia copiada. Pégalo en el chat de soporte ${SupportConfig.phoneDisplay}.'
          : 'No se pudo copiar la sugerencia.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        const Text(
          'Sugerir mejora',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Comparte una idea o solicita una funcionalidad.',
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
              const AssistantFieldLabel('Título breve', required: true),
              TextField(
                controller: _titleCtrl,
                enabled: !_busy,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  if (_titleError != null) setState(() => _titleError = null);
                },
                decoration: assistantFieldDecoration(
                  hint: 'Ejemplo: exportar la lista de ventas a Excel',
                  errorText: _titleError,
                ),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              const AssistantFieldLabel(
                'Descripción de la idea',
                required: true,
              ),
              TextField(
                controller: _descriptionCtrl,
                enabled: !_busy,
                minLines: 4,
                maxLines: 6,
                maxLength: 600,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  if (_descriptionError != null) {
                    setState(() => _descriptionError = null);
                  }
                },
                decoration: assistantFieldDecoration(
                  hint: '¿Qué necesitas y para qué te serviría?',
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
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Se incluye: ${[if ((widget.contextData.platformLabel ?? '').trim().isNotEmpty) widget.contextData.platformLabel!.trim(), if ((widget.contextData.appVersion ?? '').trim().isNotEmpty) 'v${widget.contextData.appVersion!.trim()}'].join(' · ')}',
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
      ],
    );
  }
}
