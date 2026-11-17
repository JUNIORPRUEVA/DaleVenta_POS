import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ai_assistant_controller.dart';
import '../../data/voice_note_recorder.dart';
import '../../domain/models/ai_assistant_citation.dart';
import '../../domain/models/ai_chat_context.dart';
import '../../domain/models/ai_assistant_message.dart';
import '../../../widgets/app_navigation.dart';
import '../../../theme/app_colors.dart';
import 'ai_assistant_dock_button.dart';
import '../ai_chat_context_resolver.dart';

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
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiState = ref.watch(aiAssistantControllerProvider);
    final controller = ref.read(aiAssistantControllerProvider.notifier);
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
    final narrow = docked && widget.panelWidth! < 360;
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
              color: AppColors.surfaceAlt,
              shape: const Border(left: BorderSide(color: AppColors.border)),
              child: Column(
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
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tu asistente de trabajo',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!narrow)
                          _StatusChip(online: aiState.lastError == null),
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
                  _QuickActionsGrid(
                    actions: _quickPromptsForContext(aiState.context),
                    enabled: !busy && !_recording,
                    onSelected: (action) =>
                        _sendPreset(controller, action.prompt),
                  ),
                  Expanded(
                    child: _ChatMessagesList(
                      controller: _scrollController,
                      messages: aiState.messages,
                    ),
                  ),
                  if ((aiState.lastError ?? '').trim().isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.errorSoft,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.errorBorder),
                      ),
                      child: Text(
                        aiState.lastError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.error,
                        ),
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
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: const BoxDecoration(color: AppColors.surface),
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
                            onSubmitted: busy ? null : (_) => _send(controller),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w400,
                              height: 1.5,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Escribe tu pregunta…',
                              hintStyle: theme.textTheme.bodySmall?.copyWith(
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
                                semanticsLabel: 'Adjuntar imagen o documento',
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
                                semanticsLabel: _recording
                                    ? 'Detener y enviar la nota de voz'
                                    : 'Grabar nota de voz',
                                icon: _recording
                                    ? Icons.stop_rounded
                                    : Icons.mic_none_rounded,
                                active: _recording,
                                onPressed: busy
                                    ? null
                                    : (_recording
                                          ? () => _finishRecording(controller)
                                          : _startRecording),
                              ),
                              const Spacer(),
                              _SendButton(
                                busy: aiState.sending || _finishingRecording,
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
    );
  }

  bool _isSameContext(AiChatContext a, AiChatContext b) {
    return a.module == b.module &&
        a.screenName == b.screenName &&
        a.route == b.route &&
        a.entityType == b.entityType &&
        a.entityId == b.entityId;
  }

  /// Acciones que el cliente puede hacer aquí, adaptadas al módulo en el que está.
  List<_QuickAction> _quickPromptsForContext(AiChatContext context) {
    final module = _prettyModule(context.module);
    return [
      const _QuickAction(
        'Explícame esta pantalla',
        Icons.visibility_rounded,
        'Explícame esta pantalla paso a paso',
      ),
      _QuickAction(
        'Qué puedo hacer en $module',
        Icons.dashboard_customize_rounded,
        'Qué puedo hacer en el módulo $module',
      ),
      const _QuickAction(
        'Normas del manual aquí',
        Icons.menu_book_rounded,
        'Qué normas del manual interno aplican en esta pantalla',
      ),
      const _QuickAction(
        'Reportar una avería',
        Icons.report_problem_rounded,
        'Quiero reportar una avería',
        tone: _QuickActionTone.alert,
      ),
      const _QuickAction(
        'Hablar con soporte humano',
        Icons.support_agent_rounded,
        'Quiero hablar con soporte humano',
        tone: _QuickActionTone.support,
      ),
    ];
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

  String _prettyModule(String module) {
    final normalized = module.trim().toLowerCase();
    switch (normalized) {
      case 'clientes':
        return 'Clientes';
      case 'catalogo':
      case 'catálogo':
        return 'Productos';
      case 'ventas':
        return 'Ventas';
      case 'cotizaciones':
        return 'Cotizaciones';
      case 'service-orders':
        return 'Operaciones';
      case 'media-gallery':
        return 'Galería media';
      case 'ponche':
        return 'Ponche';
      case 'nomina':
      case 'nómina':
        return 'Nómina';
      case 'manual-interno':
        return 'Manual Interno';
      case 'configuracion':
        return 'Configuración';
      case 'administracion':
        return 'Administración';
      default:
        return 'General';
    }
  }
}

/// Acción sugerida del asistente: etiqueta, icono, pregunta que se envía y tono.
///
/// El tono separa las acciones normales de las dos que abren un caso con una persona
/// (reportar una avería y hablar con soporte), que se ven con su color para encontrarlas antes.
class _QuickAction {
  const _QuickAction(
    this.label,
    this.icon,
    this.prompt, {
    this.tone = _QuickActionTone.normal,
  });

  final String label;
  final IconData icon;
  final String prompt;
  final _QuickActionTone tone;
}

enum _QuickActionTone { normal, alert, support }

/// Estado del asistente.
///
/// Se deriva del último error conocido: sin error, «En línea»; con error, «Revisar conexión».
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
        borderRadius: BorderRadius.circular(999),
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
            online ? 'En línea' : 'Revisar conexión',
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

/// Rejilla de acciones rápidas.
///
/// Antes eran cápsulas en una fila que se desplazaba: se cortaban y las dos acciones que abren un
/// caso (avería y soporte) quedaban ocultas al final. En tarjetas se ven todas a la vez y cada una
/// ocupa el mismo ancho, sin depender de la longitud del texto.
class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
    required this.actions,
    required this.enabled,
    required this.onSelected,
  });

  final List<_QuickAction> actions;
  final bool enabled;
  final ValueChanged<_QuickAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var index = 0; index < actions.length; index += 2) {
      final left = actions[index];
      final right = index + 1 < actions.length ? actions[index + 1] : null;
      if (index > 0) {
        rows.add(const SizedBox(height: 8));
      }
      rows.add(
        SizedBox(
          height: 54,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _QuickActionCard(
                  action: left,
                  enabled: enabled,
                  onSelected: onSelected,
                ),
              ),
              if (right == null)
                // Número impar de acciones: la última ocupa la fila entera en vez de dejar un hueco.
                const SizedBox.shrink()
              else ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionCard(
                    action: right,
                    enabled: enabled,
                    onSelected: onSelected,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// Tarjeta de una acción: esquinas rectas, icono a la izquierda y texto a dos líneas.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
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
    final accent = switch (action.tone) {
      _QuickActionTone.alert => AppColors.error,
      _QuickActionTone.support => AppColors.accent,
      _QuickActionTone.normal => AppColors.primary,
    };
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: enabled ? () => onSelected(action) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(action.icon, size: 18, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMessagesList extends StatelessWidget {
  const _ChatMessagesList({required this.controller, required this.messages});

  final ScrollController controller;
  final List<AiAssistantMessage> messages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (messages.isEmpty) {
      return ListView(
        reverse: true,
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Listo para orientarte con el manual y la app.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Puedes preguntarme por normas del Manual Interno, cómo usar la pantalla actual o por datos reales autorizados como clientes, cotizaciones y operaciones. Si me das un nombre, teléfono o contexto concreto, responderé mejor.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      height: 1.5,
                      letterSpacing: 0.05,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      reverse: true,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[messages.length - 1 - index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _MessageBubble(message: msg),
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
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isUser ? 20 : 6),
              bottomRight: Radius.circular(isUser ? 6 : 20),
            ),
            border: isUser ? null : Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isUser) ...[
                  Text(
                    'FullPOS IA',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (attachment != null) ...[
                  _AttachmentPreview(attachment: attachment, isUser: isUser),
                  if (message.content.trim().isNotEmpty) const SizedBox(height: 10),
                ],
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isUser ? Colors.white : AppColors.textPrimary,
                    fontSize: 14.5,
                    height: 1.6,
                    letterSpacing: 0.1,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (!isUser && message.citations.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _SourceChips(citations: message.citations),
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
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.attachment, required this.isUser});

  final AiAssistantAttachment attachment;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onUser = isUser ? Colors.white : AppColors.textPrimary;
    final onUserMuted = isUser
        ? Colors.white.withValues(alpha: 0.78)
        : AppColors.textMuted;

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
            color: isUser ? Colors.white : AppColors.primary,
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
          borderRadius: BorderRadius.circular(12),
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
                    onTap: () => _openFullImage(context, bytes, attachment.filename),
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

/// Fuentes citadas: cápsulas cortas en vez de una línea de texto larga.
class _SourceChips extends StatelessWidget {
  const _SourceChips({required this.citations});

  final List<AiAssistantCitation> citations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final citation in citations.take(3))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.secondaryBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  size: 12,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    citation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Botón redondo del compositor (adjuntar, micrófono).
///
/// Un fondo suave permanente hace que se vea como un control y no como un icono suelto; en rojo
/// cuando se está grabando, para que el estado se lea sin buscarlo.
class _ComposerIconButton extends StatelessWidget {
  const _ComposerIconButton({
    required this.tooltip,
    required this.semanticsLabel,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.active = false,
  });

  final String tooltip;
  final String semanticsLabel;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        foregroundColor: active ? AppColors.error : AppColors.textSecondary,
        backgroundColor: active
            ? AppColors.errorSoft
            : AppColors.surfaceSubtle,
        disabledBackgroundColor: AppColors.surfaceSubtle,
        shape: const CircleBorder(),
      ),
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20, semanticLabel: semanticsLabel),
    );
  }
}

/// Botón de enviar: círculo relleno con sombra, separado del resto de controles.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x331957E6),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: IconButton.filled(
        onPressed: onPressed,
        tooltip: 'Enviar',
        style: IconButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.borderStrong,
          minimumSize: const Size(44, 44),
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
            : const Icon(
                Icons.send_rounded,
                size: 20,
                semanticLabel: 'Enviar',
              ),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
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
                  attachment.isAudio ? 'Nota de voz lista' : attachment.filename,
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
          borderRadius: BorderRadius.circular(8),
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
