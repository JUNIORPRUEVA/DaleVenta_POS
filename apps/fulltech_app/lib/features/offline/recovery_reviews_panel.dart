import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/offline/recovery_review_repository.dart';
import '../../core/theme/app_colors.dart';
import 'recovery_presentation.dart';

final recoveryReviewsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      if (ref.watch(authStateProvider).user?.role != 'ADMIN') return [];
      ref.watch(
        authStateProvider.select(
          (state) => (state.user?.companyId, state.user?.id),
        ),
      );
      return ref.watch(recoveryReviewRepositoryProvider).list();
    });

class RecoveryReviewsPanel extends ConsumerStatefulWidget {
  const RecoveryReviewsPanel({super.key, this.localSaleAttemptIds = const {}});
  final Set<String> localSaleAttemptIds;
  @override
  ConsumerState<RecoveryReviewsPanel> createState() =>
      _RecoveryReviewsPanelState();
}

class _RecoveryReviewsPanelState extends ConsumerState<RecoveryReviewsPanel> {
  final Set<String> _busy = {};
  Future<void> _perform(String id, Future<void> Function() task) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await task();
      ref.invalidate(recoveryReviewsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Revisión actualizada.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userSafeErrorMessage(
                error,
                fallback: 'No se pudo actualizar. La operación sigue guardada.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _decision(Map<String, dynamic> row, String decision) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          decision == 'NOT_PERFORMED'
              ? 'Declarar no realizada'
              : 'Mantener en revisión',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  decision == 'NOT_PERFORMED'
                      ? 'Confirma la evidencia. Esta decisión no anula ventas ni pagos.'
                      : 'Explica qué falta comprobar. La operación seguirá pendiente.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    helperText: 'Mínimo 10 caracteres',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => FilledButton(
              onPressed: value.text.trim().length < 10
                  ? null
                  : () => Navigator.pop(dialogContext, value.text.trim()),
              child: const Text('Guardar decisión'),
            ),
          ),
        ],
      ),
    );
    // Wait for the route's transition before releasing its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (note != null && mounted) {
      await _perform(
        row['id'] as String,
        () => ref
            .read(recoveryReviewRepositoryProvider)
            .decide(row, decision, note),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(authStateProvider).user?.role == 'ADMIN';
    if (!admin) return const SizedBox.shrink();
    final reviews = ref.watch(recoveryReviewsProvider);
    return reviews.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text(
          'Revisiones sin comprobar',
          style: TextStyle(fontSize: 14),
        ),
        subtitle: const Text('Vuelve a consultar cuando haya conexión.'),
        trailing: IconButton(
          tooltip: 'Consultar revisiones',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.invalidate(recoveryReviewsProvider),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) return const SizedBox.shrink();
        final userId = ref.read(authStateProvider).user?.id;
        final open = rows.where((r) => r['needsIntervention'] == true &&
          !(r['sourceUserId'] == userId &&
            widget.localSaleAttemptIds.contains(r['sourceActionId']))).toList();
        if (open.isEmpty) return const SizedBox.shrink();
        Widget entry(Map<String, dynamic> row) {
          final id = row['id'] as String;
          final busy = _busy.contains(id);
          return ExpansionTile(
            key: PageStorageKey('review-$id'),
            shape: const Border(),
            collapsedShape: const Border(),
            expandedAlignment: Alignment.centerLeft,
            tilePadding: EdgeInsets.zero,
            title: Text(
              recoveryOperationLabel('${row['actionType']}'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              recoveryReviewStatus(row['status']),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            childrenPadding: const EdgeInsets.only(bottom: 12),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                key: PageStorageKey('review-reference-$id'),
                'Referencia: ${row['operationId']}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              if (row['expectedAmount'] != null)
                Text(
                  'Importe: ${row['expectedAmount']}',
                  style: const TextStyle(fontSize: 12),
                ),
              if (row['needsIntervention'] == true) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _perform(
                              id,
                              () => ref
                                  .read(recoveryReviewRepositoryProvider)
                                  .verify(id),
                            ),
                      icon: const Icon(Icons.search, size: 18),
                      label: Text(busy ? 'Comprobando…' : 'Comprobar registro'),
                    ),
                    TextButton(
                        onPressed: busy ? null : () => _decision(row, 'NOT_PERFORMED'),
                        child: const Text('Eliminar pendiente'),
                      ),
                  ],
                ),
              ],
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (open.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Por comprobar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final row in open) entry(row),
            ],
          ],
        );
      },
    );
  }
}
