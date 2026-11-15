import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/quotation_ai_controller.dart';
import '../../../../../core/utils/app_feedback.dart';

Future<void> openQuotationRuleDetailSheet(
  BuildContext context,
  WidgetRef ref, {
  String? ruleId,
  String? title,
}) async {
  final rule = await ref
      .read(quotationAiControllerProvider.notifier)
      .loadRuleDetail(ruleId: ruleId, title: title);

  if (!context.mounted) return;

  if (rule == null) {
    AppFeedback.showToast(
      context,
      title: 'Regla',
      body: 'No se pudo abrir la regla relacionada.',
      kind: AppFeedbackKind.error,
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(label: Text('Módulo: ${rule.module}')),
                    Chip(label: Text('Categoría: ${rule.category}')),
                    Chip(label: Text('Severidad: ${rule.severity.name}')),
                  ],
                ),
                if ((rule.summary ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    rule.summary!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      rule.content,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
