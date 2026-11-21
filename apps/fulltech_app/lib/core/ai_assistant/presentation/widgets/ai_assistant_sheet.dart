import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ai_assistant_controller.dart';
import '../../data/voice_note_recorder.dart';
import '../../data/assistant_feedback_sound.dart';
import '../../domain/models/ai_chat_context.dart';
import '../../domain/models/ai_assistant_message.dart';
import '../../../widgets/app_navigation.dart';
import '../../../theme/app_colors.dart';
import 'ai_assistant_dock_button.dart';
import '../ai_chat_context_resolver.dart';
import 'ai_assistant_resource_card.dart';
import 'ai_chat_panel_host.dart';
import 'ai_chat_experience.dart';
import 'ai_support_case_link.dart';

final aiAssistantSoundEnabledProvider = StateProvider<bool>((ref) => true);

class GlobalAiChatSheet extends ConsumerStatefulWidget {
  const GlobalAiChatSheet({
    super.key,
    this.onClose,
    this.embeddedInScreen = false,
    this.panelWidth,
    this.recorder,
  });

  final VoidCallback? onClose;
  final bool embeddedInScreen;

  /// Sólo para pruebas: permite inyectar un grabador de notas de voz falso.
  /// En producción se usa el micrófono real.
  final VoiceNoteRecorderContract? recorder;

  /// Ancho fijo del panel acoplado al lateral (escritorio).
  ///
  /// Cuando se indica, el panel ocupa todo el alto de la pantalla y ese ancho,
  /// de modo que puede cubrir la columna de detalle de ventas al deslizarse.
  final double? panelWidth;

  @override
  ConsumerState<GlobalAiChatSheet> createState() => _GlobalAiChatSheetState();
}

class _GlobalAiChatSheetState extends ConsumerState<GlobalAiChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = -1;
  final _sound = AssistantFeedbackSound();
  bool get _soundEnabled => ref.read(aiAssistantSoundEnabledProvider);

  /// Nota de voz: grabador, estado y temporizador visible mientras se graba.
  late final VoiceNoteRecorderContract _recorder;
  bool _recording = false;
  bool _finishingRecording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;

  @override
  void initState() {
    super.initState();
    _recorder = widget.recorder ?? VoiceNoteRecorder();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    if (_recording) {
      // Cerrar el panel grabando descarta la nota en curso.
      _recording = false;
      unawaited(_recorder.cancel());
    }
    unawaited(_recorder.dispose());
    _messageController.dispose();
    _scrollController.dispose();
    _sound.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final soundEnabled = ref.watch(aiAssistantSoundEnabledProvider);
    final aiState = ref.watch(aiAssistantControllerProvider);
    final controller = ref.read(aiAssistantControllerProvider.notifier);
    ref.listen(aiAssistantControllerProvider, (previous, next) {
      if (_soundEnabled && previous?.sending == true && !next.sending &&
          next.lastError == null && next.messages.lastOrNull?.isUser == false) {
        unawaited(_sound.play(reply: true));
      }
    });
    final liveContext = buildAiChatContextFromLocation(
      safeCurrentLocation(context),
    );
    if (!_isSameContext(liveContext, aiState.context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.setContext(liveContext);
      });
    }
    if (_lastMessageCount != aiState.messages.length) {
      _lastMessageCount = aiState.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom();
      });
    }

    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 900;
    final embedded = widget.embeddedInScreen;
    final docked = isDesktop && widget.panelWidth != null;
    final narrow = (widget.panelWidth ?? size.width) < 460;
    final busy =
        aiState.sending || aiState.uploadingAttachment || _finishingRecording;

    return SafeArea(
      top: !docked,
      bottom: !docked,
      left: !docked,
      right: !docked,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: embedded ? 0 : MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Align(
          alignment: embedded
              ? Alignment.center
              : (isDesktop ? Alignment.centerRight : Alignment.bottomCenter),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: embedded
                  ? (isDesktop ? 980 : size.width)
                  : (isDesktop ? (widget.panelWidth ?? 468) : size.width),
              maxHeight: embedded || docked
                  ? size.height
                  : (isDesktop ? 820 : size.height * 0.84),
            ),
            child: Material(
              color: AppColors.surfaceSubtle,
              shape: const Border(left: BorderSide(color: AppColors.border)),
              child: AiChatPanelHost(
                child: Builder(
                  builder: (panelContext) => Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          border: Border(
                            bottom: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            Image.asset(
                              AiAssistantDockButton.imageAsset,
                              width: 40,
                              height: 40,
                              excludeFromSemantics: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'FullPOS IA',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700, letterSpacing: -.3),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tu asistente de FullPOS',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!narrow)
                              _StatusChip(online: aiState.lastError == null),
                            IconButton(
                              tooltip: soundEnabled ? 'Silenciar sonidos' : 'Activar sonidos',
                              onPressed: () => ref.read(aiAssistantSoundEnabledProvider.notifier).state = !soundEnabled,
                              icon: Icon(soundEnabled ? Icons.volume_up_outlined : Icons.volume_off_outlined, size: 18),
                              color: AppColors.textMuted,
                            ),
                            if (!embedded)
                              IconButton(
                                tooltip: 'Cerrar asistente',
                                onPressed:
                                    widget.onClose ??
                                    () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded, size: 20),
                                color: AppColors.textSecondary,
                              ),
                          ],
                        ),
                      ),
                      _QuickActionLinks(
                        actions: _quickPromptsForContext(aiState.context),
                        enabled: !busy && !_recording,
                        onSelected: (action) => _reportIncident(controller, panelContext),
                      ),
                      Expanded(
                        child: _ChatMessagesList(
                          controller: _scrollController,
                          messages: aiState.messages,
                          sending: aiState.sending,
                        ),
                      ),
                      if ((aiState.lastError ?? '').trim().isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.errorSoft,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.errorBorder),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _friendlyError(aiState.lastError!),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                              if (controller.canRetryLastMessage) ...[
                                const SizedBox(width: 8),
                                IconButton.outlined(
                                  tooltip: 'Reintentar',
                                  onPressed: busy || _recording
                                      ? null
                                      : controller.retryLastMessage,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(40, 40),
                                    foregroundColor: AppColors.error,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.refresh_rounded,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          border: Border(
                            top: BorderSide(color: AppColors.borderStrong),
                          ),
                        ),
                        child: Container(
                          key: const ValueKey('ai-assistant-composer'),
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (aiState.attachment != null)
                                _PendingAttachmentChip(
                                  attachment: aiState.attachment!,
                                  onRemove: busy
                                      ? null
                                      : controller.clearAttachment,
                                ),
                              if (_recording)
                                _RecordingBar(
                                  elapsed: _recordElapsed,
                                  busy: _finishingRecording,
                                  onCancel: _cancelRecording,
                                ),
                              TextField(
                                controller: _messageController,
                                enabled: !_recording,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                onSubmitted: busy
                                    ? null
                                    : (_) => _send(controller),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Escribe tu pregunta…',
                                  hintStyle: theme.textTheme.bodyMedium
                                      ?.copyWith(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w400,
                                      ),
                                  filled: false,
                                  isDense: true,
                                  contentPadding: const EdgeInsets.all(8),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  _ComposerIconButton(
                                    tooltip: 'Adjuntar imagen o documento',
                                    icon: Icons.image_outlined,
                                    busy: aiState.uploadingAttachment,
                                    onPressed: busy || _recording
                                        ? null
                                        : () => _pickAttachment(controller),
                                  ),
                                  const SizedBox(width: 6),
                                  _ComposerIconButton(
                                    tooltip: _recording
                                        ? 'Detener y enviar la nota de voz'
                                        : 'Grabar nota de voz',
                                    icon: _recording
                                        ? Icons.stop_rounded
                                        : Icons.mic_none_rounded,
                                    active: _recording,
                                    onPressed: busy
                                        ? null
                                        : (_recording
                                              ? () =>
                                                    _finishRecording(controller)
                                              : _startRecording),
                                  ),
                                  const Spacer(),
                                  _SendButton(
                                    busy:
                                        aiState.sending || _finishingRecording,
                                    onPressed: busy || _recording
                                        ? null
                                        : () => _send(controller),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameContext(AiChatContext a, AiChatContext b) {
    return a.module == b.module &&
        a.screenName == b.screenName &&
        a.route == b.route &&
        a.entityType == b.entityType &&
        a.entityId == b.entityId;
  }

  Future<void> _reportIncident(
    AiAssistantController controller,
    BuildContext panelContext,
  ) async {
    final form = GlobalKey<FormState>();
    String description = '';
    final confirmed = await showDialog<bool>(
      context: panelContext,
      useRootNavigator: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reportar una avería'),
        scrollable: true,
        content: Form(
          key: form,
          child: TextFormField(
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 1200,
            decoration: const InputDecoration(
              labelText: '¿Qué ocurrió?',
              hintText:
                  'Describe lo que intentaste hacer y el error que apareció.',
              helperText: 'No incluyas contraseñas ni datos de pago.',
              helperMaxLines: 2,
            ),
            onChanged: (value) => description = value.trim(),
            validator: (value) => (value ?? '').trim().length < 12
                ? 'Describe el problema con un poco más de detalle.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Registrar avería'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !controller.mounted) return;
    await _sendPreset(controller, 'Quiero reportar una avería: $description');
  }

  /// Acciones que el cliente puede hacer aquí, adaptadas al módulo en el que está.
  List<_QuickAction> _quickPromptsForContext(AiChatContext context) {
    return [
      const _QuickAction(
        'Reportar una avería',
        'Quiero reportar una avería',
        tone: _QuickActionTone.alert,
      ),
    ];
  }

  String _friendlyError(String error) {
    if (error.toLowerCase().contains('motor de archivos')) {
      return 'Los archivos no están disponibles en este momento. Puedes continuar por texto.';
    }
    return error.replaceFirst(RegExp(r'^ApiException:\s*'), '')
      .replaceFirst(RegExp(r'\s*\(code:\s*\d+\)\s*$'), '');
  }

  /// Abre el selector de archivos y sube el elegido para el próximo mensaje.
  ///
  /// El archivo no se guarda en la app: se envía al backend, que lo procesa y devuelve el
  /// identificador que el mensaje siguiente necesita. Mientras sube, el botón queda ocupado.
  Future<void> _pickAttachment(AiAssistantController controller) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'doc',
          'docx',
          'txt',
          'csv',
          'png',
          'jpg',
          'jpeg',
          'webp',
          'mp4',
          'mov',
          'mp3',
          'wav',
          'm4a',
        ],
        withData: true,
      );
      final files = result?.files ?? const <PlatformFile>[];
      if (files.isEmpty) return;
      final file = files.first;
      final bytes = file.bytes;
      if (bytes == null) return;
      await controller.attachFile(
        filename: file.name,
        bytes: bytes,
        mimeType: _guessMime(file.name),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('No se pudo adjuntar el archivo: $e')),
      );
    }
  }

  /// Empieza a grabar una nota de voz.
  ///
  /// Windows no pide permiso; Android/iOS sí y ya lo declaran. Si el micrófono no
  /// está disponible se avisa y no se deja el compositor en un estado raro.
  Future<void> _startRecording() async {
    if (_recording || _finishingRecording) return;
    final allowed = await _recorder.hasPermission();
    if (!mounted) return;
    if (!allowed) {
      _showMessage(
        'No hay permiso para usar el micrófono. Actívalo en los ajustes del sistema.',
      );
      return;
    }
    try {
      await _recorder.startNew(DateTime.now());
    } catch (e) {
      if (!mounted) return;
      _showMessage('No se pudo iniciar la grabación: $e');
      return;
    }
    if (!mounted) {
      unawaited(_recorder.cancel());
      return;
    }
    setState(() {
      _recording = true;
      _recordElapsed = Duration.zero;
    });
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _recordElapsed = Duration(seconds: timer.tick));
      if (_recordElapsed >= _recorder.maxDuration) {
        // Tope de duración: se detiene y se envía sola.
        unawaited(
          _finishRecording(ref.read(aiAssistantControllerProvider.notifier)),
        );
      }
    });
  }

  /// Detiene la grabación, sube la nota de voz y la envía en el mismo gesto.
  Future<void> _finishRecording(AiAssistantController controller) async {
    if (!_recording || _finishingRecording) return;
    _recordTimer?.cancel();
    _recordTimer = null;
    setState(() {
      _recording = false;
      _finishingRecording = true;
    });
    try {
      final path = await _recorder.stop();
      if (path == null || path.trim().isEmpty) {
        _showMessage('No se pudo guardar la nota de voz.');
        return;
      }
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        _showMessage('La nota de voz quedó vacía. Inténtalo otra vez.');
        return;
      }
      await controller.attachFile(
        filename: VoiceNoteRecorder.fileNameFor(DateTime.now()),
        bytes: bytes,
        mimeType: VoiceNoteRecorder.mimeType,
      );
      if (!mounted) return;
      final pending = ref.read(aiAssistantControllerProvider).attachment;
      if (pending != null) {
        await _send(controller);
      } else {
        final failure = ref.read(aiAssistantControllerProvider).lastError;
        if (failure != null) _showMessage(failure);
      }
      try {
        await file.delete();
      } catch (_) {
        // El temporal lo limpia el sistema si ahora no se puede borrar.
      }
    } catch (e) {
      if (mounted) {
        _showMessage('No se pudo enviar la nota de voz: $e');
      }
    } finally {
      if (mounted) setState(() => _finishingRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    _recordTimer = null;
    if (!_recording) return;
    setState(() {
      _recording = false;
      _recordElapsed = Duration.zero;
    });
    await _recorder.cancel();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Tipo MIME aproximado por extensión.
  ///
  /// El motor multimedia decide la capacidad por el archivo real; esto sólo evita mandar
  /// `application/octet-stream` en los formatos habituales.
  String _guessMime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }

  Future<void> _send(AiAssistantController controller) async {
    final text = _messageController.text.trim();
    // Con un adjunto listo no hace falta escribir nada: la nota de voz, la foto
    // o el documento también son un mensaje.
    if (text.isEmpty &&
        ref.read(aiAssistantControllerProvider).attachment == null) {
      return;
    }
    _messageController.clear();
    if (_soundEnabled) unawaited(_sound.play());

    final location = safeCurrentLocation(context);
    controller.setContext(buildAiChatContextFromLocation(location));
    await controller.sendMessage(text);
  }

  Future<void> _sendPreset(
    AiAssistantController controller,
    String prompt,
  ) async {
    _messageController.clear();

    final location = safeCurrentLocation(context);
    controller.setContext(buildAiChatContextFromLocation(location));
    await controller.sendMessage(prompt);
  }

}

/// Acción sugerida del asistente: texto que se envía y tono.
///
/// El tono sólo cambia el color: las dos acciones que abren un caso con una persona (avería y
/// soporte) se ven distintas sin necesidad de una caja que ocupe media pantalla.
class _QuickAction {
  const _QuickAction(
    this.label,
    this.prompt, {
    this.tone = _QuickActionTone.normal,
  });

  final String label;
  final String prompt;
  final _QuickActionTone tone;
}

enum _QuickActionTone { normal, alert, support }

/// Estado del asistente.
///
/// Se deriva del último error conocido: sin error, «En línea»; con error, «Revisar aviso».
/// No se inventa un ping ni se muestra «en línea» cuando la última petición falló.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: online ? AppColors.successSoft : AppColors.warningSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: online ? AppColors.successBorder : AppColors.warningBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            online ? 'En línea' : 'Revisar aviso',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Acciones rápidas como enlaces de texto.
///
/// Antes eran tarjetas grandes que tapaban la conversación. Ahora son una o dos líneas de texto
/// pequeño, sin cajas ni iconos: se leen como parte del panel y dejan el espacio para los mensajes.
/// Las dos acciones que abren un caso con una persona conservan su color para no perderse.
class _QuickActionLinks extends StatelessWidget {
  const _QuickActionLinks({
    required this.actions,
    required this.enabled,
    required this.onSelected,
  });

  final List<_QuickAction> actions;
  final bool enabled;
  final ValueChanged<_QuickAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: actions
              .map(
                (action) => Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                  child: _QuickActionLink(action: action, enabled: enabled, onSelected: onSelected),
                )),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

/// Un enlace de acción: texto pequeño, sin fondo ni borde.
class _QuickActionLink extends StatelessWidget {
  const _QuickActionLink({
    required this.action,
    required this.enabled,
    required this.onSelected,
  });

  final _QuickAction action;
  final bool enabled;
  final ValueChanged<_QuickAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (action.tone) {
      _QuickActionTone.alert => AppColors.textPrimary,
      _QuickActionTone.support => AppColors.primaryDark,
      _QuickActionTone.normal => AppColors.textSecondary,
    };
    return OutlinedButton.icon(
      onPressed: enabled ? () => onSelected(action) : null,
      icon: Icon(action.tone == _QuickActionTone.alert
        ? Icons.report_problem_outlined : Icons.support_agent_rounded, size: 16),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      label: Text(
        action.label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ChatMessagesList extends StatelessWidget {
  const _ChatMessagesList({required this.controller, required this.messages, required this.sending});
  final ScrollController controller;
  final List<AiAssistantMessage> messages;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final visible = messages.where((message) => !message.id.startsWith('ai-assistant-intro')).toList();
    if (visible.isEmpty && !sending) {
      return LayoutBuilder(builder: (context, bounds) => SingleChildScrollView(
        controller: controller,
        child: ConstrainedBox(constraints: BoxConstraints(minHeight: bounds.maxHeight),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const AiChatWelcome(),
          ])),
      ));
    }
    final extras = sending ? 1 : 0;
    return ListView.builder(
      reverse: true, controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      itemCount: visible.length + extras,
      itemBuilder: (context, index) {
        if (sending && index == 0) {
          return const Padding(padding: EdgeInsets.only(bottom: 12), child: AiTypingBubble());
        }
        final offset = index - (sending ? 1 : 0);
        final messageIndex = offset;
        final message = visible[visible.length - 1 - messageIndex];
        return TweenAnimationBuilder<double>(
          key: ValueKey(message.id), tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Opacity(opacity: value, alwaysIncludeSemantics: true,
            child: Transform.translate(offset: Offset(0, 10 * (1 - value)), child: child)),
          child: Padding(padding: const EdgeInsets.only(bottom: 14),
            child: _MessageBubble(message: message)),
        );
      },
    );
  }
}

/// Burbuja de un mensaje de la conversación.
///
/// Decisiones de aspecto:
/// - El lado y el color identifican a quién habla; no hace falta repetir «Tú» en cada mensaje.
/// - La esquina inferior del lado que habla va más cerrada: la burbuja «se apoya» en la
///   conversación en vez de quedar flotando como una tarjeta.
/// - Si el mensaje lleva una imagen, se enseña la miniatura dentro de la burbuja y se puede abrir a
///   tamaño completo; un audio o un documento se muestran como ficha con su icono.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiAssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final attachment = message.attachment;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          decoration: BoxDecoration(
            color: isUser ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(6),
              topRight: const Radius.circular(6),
              bottomLeft: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
            border: isUser ? null : Border.all(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (attachment != null) ...[
                  _AttachmentPreview(attachment: attachment, isUser: isUser),
                  if (message.content.trim().isNotEmpty)
                    const SizedBox(height: 10),
                ],
                Text.rich(
                  TextSpan(
                    children: isUser
                        ? [TextSpan(text: message.content)]
                        : _answerSpans(message.content),
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isUser ? AppColors.surface : AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.65,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (!isUser && message.supportCase != null)
                  AiSupportCaseLink(supportCase: message.supportCase!),
                if (!isUser && message.incident != null) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    'Caso ${message.incident!.reference}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ] else if (!isUser && message.requiresHumanReview) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Requiere revisión de soporte',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
                if (!isUser)
                  for (final resource in message.resources) ...[
                    const SizedBox(height: 10),
                    AiAssistantResourceCard(
                      key: ValueKey(
                        'ai-resource-${resource.id}-${resource.version}',
                      ),
                      resource: resource,
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Miniatura del archivo que acompaña al mensaje.
///
/// Se apoya en el `mediaJobId`: los bytes son sólo para dibujar la vista previa. Si no hay bytes
/// (archivo grande) se enseña la ficha con el nombre, nunca un hueco vacío.
List<InlineSpan> _answerSpans(String text) {
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final match in RegExp(r'\*\*([^*]+)\*\*|`([^`]+)`').allMatches(text)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
    }
    spans.add(
      TextSpan(
        text: match.group(1) ?? match.group(2),
        style: TextStyle(
          fontWeight: match.group(1) != null
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
    );
    offset = match.end;
  }
  if (offset < text.length) {
    spans.add(TextSpan(text: text.substring(offset)));
  }
  return spans;
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment, required this.isUser});

  final AiAssistantAttachment attachment;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onUser = isUser ? AppColors.surface : AppColors.textPrimary;
    final onUserMuted = isUser ? AppColors.surface.withValues(alpha: .8) : AppColors.textMuted;

    if (!attachment.hasPreview) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            attachment.isAudio
                ? Icons.graphic_eq_rounded
                : (attachment.isImage
                      ? Icons.image_outlined
                      : Icons.description_outlined),
            size: 18,
            color: onUserMuted,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              attachment.isAudio ? 'Nota de voz' : attachment.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: onUser,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }

    final bytes = attachment.bytes!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Image.memory(
                Uint8List.fromList(bytes),
                width: double.infinity,
                height: 190,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                semanticLabel: 'Imagen adjunta: ${attachment.filename}',
              ),
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () =>
                        _openFullImage(context, bytes, attachment.filename),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          attachment.filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: onUserMuted),
        ),
      ],
    );
  }

  void _openFullImage(BuildContext context, List<int> bytes, String name) {
    showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 4,
              child: Image.memory(
                Uint8List.fromList(bytes),
                fit: BoxFit.contain,
                semanticLabel: 'Imagen adjunta: $name',
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Control compacto del compositor (adjuntar, micrófono).
///
/// Un fondo suave permanente hace que se vea como un control y no como un icono suelto; en rojo
/// cuando se está grabando, para que el estado se lea sin buscarlo.
class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          foregroundColor: active ? AppColors.error : AppColors.textSecondary,
          backgroundColor: active ? AppColors.errorSoft : AppColors.surface,
          disabledBackgroundColor: AppColors.surfaceSubtle,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, size: 20),
      ),
    );
  }
}

/// Acción principal del compositor, con el mismo radio que los otros controles.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Enviar',
      onTap: onPressed,
      excludeSemantics: true,
      child: IconButton.filled(
        onPressed: onPressed,
        tooltip: 'Enviar',
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderStrong,
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : const Icon(Icons.send_rounded, size: 20),
      ),
    );
  }
}

/// Ficha del archivo que se enviará con el siguiente mensaje.
///
/// Si es una imagen se ve la miniatura: es la forma de confirmar que se adjuntó la captura
/// correcta antes de enviarla.
class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  final AiPendingAttachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = attachment.bytes;
    final canPreview = attachment.isImage && bytes != null && bytes.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 44,
              height: 44,
              child: canPreview
                  ? Image.memory(
                      Uint8List.fromList(bytes),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      semanticLabel: 'Vista previa de ${attachment.filename}',
                    )
                  : ColoredBox(
                      color: AppColors.primarySoft,
                      child: Icon(
                        attachment.isAudio
                            ? Icons.graphic_eq_rounded
                            : Icons.description_outlined,
                        size: 22,
                        color: AppColors.primary,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.isAudio
                      ? 'Nota de voz lista'
                      : attachment.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Se enviará con tu mensaje',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'Quitar adjunto',
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Franja que se ve mientras se graba una nota de voz.
///
/// Mantiene el gesto claro: se graba, se ve el tiempo y se puede cancelar sin
/// enviar nada. El envío se hace con el botón de detener del compositor.
class _RecordingBar extends StatelessWidget {
  const _RecordingBar({
    required this.elapsed,
    required this.busy,
    required this.onCancel,
  });

  final Duration elapsed;
  final bool busy;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    String two(int value) => value.toString().padLeft(2, '0');
    final time =
        '${two(elapsed.inMinutes)}:${two(elapsed.inSeconds.remainder(60))}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFDECEA),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF3B3A6)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.fiber_manual_record_rounded,
              size: 12,
              color: Color(0xFFD92D20),
            ),
            const SizedBox(width: 8),
            Text(
              'Grabando nota de voz · $time',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A2D1B),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: busy ? null : onCancel,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}
