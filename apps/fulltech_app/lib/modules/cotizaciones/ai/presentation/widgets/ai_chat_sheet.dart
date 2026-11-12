import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/quotation_ai_controller.dart';
import '../../domain/models/ai_chat_message.dart';
import '../../domain/models/ai_warning.dart';
import 'quick_ai_actions.dart';
import 'quotation_rule_detail_sheet.dart';

class AiChatSheet extends ConsumerStatefulWidget {
  const AiChatSheet({super.key, this.initialPrompt});

  final String? initialPrompt;

  @override
  ConsumerState<AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends ConsumerState<AiChatSheet> {
  final TextEditingController _messageController = TextEditingController();
  bool _sentInitialPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final initialPrompt = (widget.initialPrompt ?? '').trim();
      if (_sentInitialPrompt || initialPrompt.isEmpty || !mounted) return;
      _sentInitialPrompt = true;
      ref
          .read(quotationAiControllerProvider.notifier)
          .sendMessage(initialPrompt);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiState = ref.watch(quotationAiControllerProvider);
    final controller = ref.read(quotationAiControllerProvider.notifier);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return SafeArea(
      child: Align(
        alignment: isDesktop ? Alignment.centerRight : Alignment.bottomCenter,
        child: Container(
          width: isDesktop ? 520 : null,
          height: isDesktop
              ? double.infinity
              : MediaQuery.sizeOf(context).height * 0.88,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: isDesktop
                ? const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    bottomLeft: Radius.circular(28),
                  )
                : const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 10, 10),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Asistente FULLTECH',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Contexto actual: Cotización',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Acciones rápidas',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 10),
                            QuickAiActions(
                              onAction: (action) {
                                if (action == 'Explicar advertencias') {
                                  controller.explainWarnings();
                                  return;
                                }
                                controller.askQuickAction(action);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.menu_book_rounded,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Fuente de reglas',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    aiState.loadingRules
                                        ? 'Cargando Manual Interno y conocimiento interno autorizado...'
                                        : 'La IA usa Manual Interno, guias funcionales de la app y resúmenes autorizados del sistema para tu usuario. Reglas locales cargadas: ${aiState.rules.length}.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      height: 1.35,
                                    ),
                                  ),
                                  if ((aiState.analysisError ?? '')
                                      .trim()
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Aviso de carga: ${aiState.analysisError}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.error,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Recargar reglas',
                              onPressed: aiState.loadingRules
                                  ? null
                                  : controller.refreshRules,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (aiState.visibleWarnings.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Advertencias actuales',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 10),
                              for (final warning
                                  in aiState.visibleWarnings.take(3)) ...[
                                _WarningMiniTile(
                                  warning: warning,
                                  onTapRule: () => openQuotationRuleDetailSheet(
                                    context,
                                    ref,
                                    ruleId: warning.relatedRuleId,
                                    title: warning.relatedRuleTitle,
                                  ),
                                ),
                                if (warning !=
                                    aiState.visibleWarnings.take(3).last)
                                  const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    for (final message in aiState.messages) ...[
                      _ChatBubble(
                        message: message,
                        onOpenRule:
                            (message.relatedRuleId ?? '').trim().isEmpty &&
                                (message.relatedRuleTitle ?? '').trim().isEmpty
                            ? null
                            : () => openQuotationRuleDetailSheet(
                                context,
                                ref,
                                ruleId: message.relatedRuleId,
                                title: message.relatedRuleTitle,
                              ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText:
                              'Pregunta sobre reglas, precios, DVR o garantía...',
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: aiState.sendingMessage ? null : _send,
                      icon: aiState.sendingMessage
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _send() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    _messageController.clear();
    ref.read(quotationAiControllerProvider.notifier).sendMessage(message);
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, this.onOpenRule});

  final AiChatMessage message;
  final VoidCallback? onOpenRule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == AiChatRole.user;
    final hasOpenableRule =
        ((message.relatedRuleId ?? '').trim().isNotEmpty &&
            !(message.relatedRuleId ?? '').startsWith('app-')) ||
        message.citations.any((citation) => !citation.id.startsWith('app-'));
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final background = isUser
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerLowest;
    final foreground = isUser
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
            border: isUser
                ? null
                : Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.content,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    height: 1.35,
                  ),
                ),
                if (!isUser &&
                    (message.citations.isNotEmpty || onOpenRule != null)) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.45,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Base oficial usada',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final citation in message.citations)
                              ActionChip(
                                label: Text(citation.title),
                                onPressed: citation.id.startsWith('app-')
                                    ? null
                                    : onOpenRule,
                              ),
                            if (message.citations.isEmpty && onOpenRule != null)
                              ActionChip(
                                label: Text(
                                  message.relatedRuleTitle ??
                                      'Ver regla oficial',
                                ),
                                onPressed: hasOpenableRule ? onOpenRule : null,
                              ),
                          ],
                        ),
                      ],
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

class _WarningMiniTile extends StatelessWidget {
  const _WarningMiniTile({required this.warning, required this.onTapRule});

  final AiWarning warning;
  final VoidCallback onTapRule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: warning.relatedRuleId == null && warning.relatedRuleTitle == null
          ? null
          : onTapRule,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              warning.type == AiWarningType.warning
                  ? Icons.warning_amber_rounded
                  : warning.type == AiWarningType.success
                  ? Icons.verified_rounded
                  : Icons.info_outline_rounded,
              color: warning.type == AiWarningType.warning
                  ? theme.colorScheme.error
                  : warning.type == AiWarningType.success
                  ? theme.colorScheme.primary
                  : theme.colorScheme.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    warning.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    warning.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
