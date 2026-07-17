import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ai_assistant_controller.dart';
import '../../domain/models/ai_chat_context.dart';
import '../../domain/models/ai_assistant_message.dart';
import '../../../widgets/app_navigation.dart';
import '../ai_chat_context_resolver.dart';

class GlobalAiChatSheet extends ConsumerStatefulWidget {
  const GlobalAiChatSheet({
    super.key,
    this.onClose,
    this.embeddedInScreen = false,
  });

  final VoidCallback? onClose;
  final bool embeddedInScreen;

  @override
  ConsumerState<GlobalAiChatSheet> createState() => _GlobalAiChatSheetState();
}

class _GlobalAiChatSheetState extends ConsumerState<GlobalAiChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = -1;

  static const _defaultQuickPrompts = <String>[
    'Explícame esta pantalla',
    'Qué norma del manual aplica aquí',
    'Este cliente existe en la app',
    'Qué puedo hacer en este módulo',
  ];

  @override
  void dispose() {
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

    final liveLocation = safeCurrentLocation(context);
    final liveContext = buildAiChatContextFromLocation(liveLocation);
    if (!_isSameContext(liveContext, aiState.context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        controller.setContext(liveContext);
      });
    }
    final size = MediaQuery.sizeOf(context);
    final isDesktop = size.width >= 900;
    final embeddedInScreen = widget.embeddedInScreen;
    final quickPrompts = _quickPromptsForContext(aiState.context);
    final panelRadius = embeddedInScreen
        ? BorderRadius.circular(isDesktop ? 30 : 26)
        : BorderRadius.only(
            topLeft: Radius.circular(isDesktop ? 32 : 28),
            bottomLeft: Radius.circular(isDesktop ? 32 : 28),
            topRight: Radius.circular(isDesktop ? 0 : 28),
            bottomRight: Radius.circular(isDesktop ? 0 : 28),
          );

    if (_lastMessageCount != aiState.messages.length) {
      _lastMessageCount = aiState.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          embeddedInScreen ? 0 : (isDesktop ? 0 : 10),
          embeddedInScreen ? 0 : 10,
          embeddedInScreen ? 0 : (isDesktop ? 0 : 10),
          embeddedInScreen ? 0 : (isDesktop ? 10 : 0),
        ),
        child: Align(
          alignment: embeddedInScreen
              ? Alignment.center
              : (isDesktop ? Alignment.centerRight : Alignment.bottomCenter),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: embeddedInScreen
                  ? (isDesktop ? 980 : size.width)
                  : (isDesktop ? 468 : size.width),
              maxHeight: embeddedInScreen
                  ? size.height
                  : (isDesktop ? 820 : size.height * 0.84),
            ),
            child: Container(
              height: embeddedInScreen ? double.infinity : null,
              width: embeddedInScreen
                  ? double.infinity
                  : (isDesktop ? 468 : null),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF3F7FF), Color(0xFFFFFFFF)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: panelRadius,
                border: Border.all(
                  color: const Color(0xFFB9C9F3).withValues(alpha: 0.72),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF12367E).withValues(alpha: 0.16),
                    blurRadius: 34,
                    offset: const Offset(-10, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: panelRadius,
                child: Material(
                  color: Colors.transparent,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF0F2F73).withValues(alpha: 0.06),
                                Colors.white,
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 88,
                        left: -50,
                        child: Container(
                          width: 180,
                          height: 180,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(
                              0xFF29B7C8,
                            ).withValues(alpha: 0.09),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -20,
                        right: -30,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(
                              0xFF2457D6,
                            ).withValues(alpha: 0.11),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Color(0xFF0F2F73),
                                  Color(0xFF1D4FBE),
                                  Color(0xFF15AFC0),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.18,
                                      ),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.memory_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'FULLTECH AI',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.2,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _buildContextLabel(aiState.context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: Colors.white.withValues(
                                                alpha: 0.82,
                                              ),
                                              height: 1.3,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    embeddedInScreen
                                        ? 'Asistente IA'
                                        : 'Contexto actual',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                if (!embeddedInScreen)
                                  IconButton(
                                    onPressed:
                                        widget.onClose ??
                                        () => Navigator.of(context).pop(),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                            color: const Color(0xFFEDF4FF),
                            child: Text(
                              'Base principal: Manual Interno. También puedo explicarte la pantalla actual y responder con datos reales autorizados de la app.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF26427D),
                                fontWeight: FontWeight.w600,
                                height: 1.35,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: quickPrompts
                                      .map(
                                        (prompt) => Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: ActionChip(
                                            onPressed: aiState.sending
                                                ? null
                                                : () => _sendPreset(
                                                    controller,
                                                    prompt,
                                                  ),
                                            backgroundColor: Colors.white,
                                            side: BorderSide(
                                              color: const Color(
                                                0xFFB7C8EF,
                                              ).withValues(alpha: 0.9),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            label: Text(
                                              prompt,
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                    color: const Color(
                                                      0xFF173D8E,
                                                    ),
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: _ChatMessagesList(
                              controller: _scrollController,
                              messages: aiState.messages,
                            ),
                          ),
                          if ((aiState.lastError ?? '').trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3F0),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFF3B3A6),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    aiState.lastError!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF8A2D1B),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _messageController,
                                    minLines: 1,
                                    maxLines: 4,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) async {
                                      await _send(controller);
                                    },
                                    decoration: InputDecoration(
                                      hintText:
                                          'Pregunta por normas, pantalla actual, clientes, operaciones o procesos...',
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 15,
                                          ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFB7C8EF),
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFB7C8EF),
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF2457D6),
                                          width: 1.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  height: 52,
                                  width: 52,
                                  child: FilledButton(
                                    onPressed: aiState.sending
                                        ? null
                                        : () => _send(controller),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF1D4FBE),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                    child: aiState.sending
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.arrow_upward_rounded,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

  List<String> _quickPromptsForContext(AiChatContext context) {
    switch (context.module.trim().toLowerCase()) {
      case 'catalogo':
      case 'catálogo':
        return const [
          'Qué productos hay en catálogo',
          'Búscame taladros disponibles en catálogo',
          'Qué categorías de productos existen',
          'Muéstrame productos con precio',
        ];
      case 'clientes':
        return const [
          'Explícame esta pantalla',
          'Este cliente existe en la app',
          'Qué información puedo ver del cliente',
          'Resumen del cliente seleccionado',
        ];
      case 'cotizaciones':
        return const [
          'Explícame esta pantalla',
          'Resumen de la cotización actual',
          'Qué reglas del manual aplican aquí',
          'Qué puedo hacer en este módulo',
        ];
      case 'service-orders':
        return const [
          'Explícame esta pantalla',
          'Resumen de esta orden de servicio',
          'Qué reglas del manual aplican aquí',
          'Qué puedo hacer en este módulo',
        ];
      case 'manual-interno':
        return const [
          'Explícame esta pantalla',
          'Qué normas del manual están vigentes',
          'Resúmeme las reglas más importantes',
          'Qué tipo de regla debo buscar aquí',
        ];
      case 'profile':
      case 'nomina':
        return const [
          'Cuál es mi información en la app',
          'Cuál es mi rol',
          'Qué datos míos puedes ver',
          'Explícame esta pantalla',
        ];
      default:
        return _defaultQuickPrompts;
    }
  }

  Future<void> _send(AiAssistantController controller) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
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

  String _buildContextLabel(AiChatContext context) {
    final module = _prettyModule(context.module);
    final screen = (context.screenName ?? '').trim();
    if (screen.isEmpty) return 'Contexto actual: $module';
    return 'Contexto actual: $module · $screen';
  }

  String _prettyModule(String module) {
    final normalized = module.trim().toLowerCase();
    switch (normalized) {
      case 'clientes':
        return 'Clientes';
      case 'catalogo':
      case 'catálogo':
        return 'Catálogo';
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
              border: Border.all(color: const Color(0xFFB7C8EF)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Listo para orientarte con el manual y la app.',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFF173D8E),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Puedes preguntarme por normas del Manual Interno, cómo usar la pantalla actual o por datos reales autorizados como clientes, cotizaciones y operaciones. Si me das un nombre, teléfono o contexto concreto, responderé mejor.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.4,
                      color: const Color(0xFF31446E),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiAssistantMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;

    final background = isUser ? const Color(0xFF2457D6) : Colors.white;

    final foreground = isUser ? Colors.white : const Color(0xFF1A2A4E);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: isUser ? null : Border.all(color: const Color(0xFFB7C8EF)),
            boxShadow: [
              BoxShadow(
                color:
                    (isUser ? const Color(0xFF2457D6) : const Color(0xFF173D8E))
                        .withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Text(
                  isUser ? 'Tú' : 'FULLTECH AI',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.84)
                        : const Color(0xFF2457D6),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    height: 1.35,
                  ),
                ),
                if (!isUser && message.citations.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Fuentes: ${message.citations.map((c) => c.title).take(3).join(' • ')}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF566B96),
                    ),
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
