import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_feedback.dart';
import '../data/ecf_certification_repository.dart';
import '../ecf_certification_models.dart';
import 'ecf_resolve_attempt_dialog.dart';

/// Pantalla administrativa de reconciliación de intentos bloqueados.
///
/// Solo metadatos: operación, estado, fecha, intento, referencia y motivo. Nunca
/// certificados, contraseñas ni documentos.
///
/// Regla que la pantalla respeta: **no existe «reintentar»**. Confirmar que la
/// operación NO se aplicó exige una referencia de evidencia; si no la hay, el
/// intento se queda bloqueado para revisión humana.
class EcfCertificationRecoveryPage extends ConsumerStatefulWidget {
  const EcfCertificationRecoveryPage({super.key});

  @override
  ConsumerState<EcfCertificationRecoveryPage> createState() =>
      _EcfCertificationRecoveryPageState();
}

class _EcfCertificationRecoveryPageState
    extends ConsumerState<EcfCertificationRecoveryPage> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<EcfBlockedAttempt> _attempts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(ecfCertificationRepositoryProvider)
          .blockedAttempts();
      if (!mounted) return;
      setState(() {
        _attempts = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los intentos bloqueados.';
      });
    }
  }

  Future<void> _resolve(EcfBlockedAttempt attempt, String decision) async {
    final input = await showDialog<EcfResolveAttemptInput>(
      context: context,
      builder: (context) => EcfResolveAttemptDialog(
        operation: attempt.operation,
        applied: decision == 'CONFIRM_APPLIED_WITH_EVIDENCE',
      ),
    );
    if (input == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(ecfCertificationRepositoryProvider)
          .resolveAttempt(
            attemptId: attempt.attemptId,
            decision: decision,
            evidenceRef: input.evidence,
            note: input.note,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      AppFeedback.showToast(
        context,
        title: 'Decisión registrada',
        body: 'La reconciliación quedó auditada con tu usuario.',
        kind: AppFeedbackKind.success,
        dedupeKey: 'ecf_attempt_resolved',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppFeedback.showToast(
        context,
        title: 'No se pudo registrar la decisión',
        body: error.toString().replaceFirst('Exception: ', ''),
        kind: AppFeedbackKind.error,
        dedupeKey: 'ecf_attempt_resolve_error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Reconciliación de intentos')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Operaciones que quedaron sin confirmación. No se reenvían: hay '
              'que comprobar el resultado y dejar constancia.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error))
            else if (_attempts.isEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'No hay intentos bloqueados en esta empresa.',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else
              for (final attempt in _attempts) ...[
                _AttemptCard(
                  attempt: attempt,
                  busy: _busy,
                  onResolve: (decision) => _resolve(attempt, decision),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _AttemptCard extends StatelessWidget {
  const _AttemptCard({
    required this.attempt,
    required this.busy,
    required this.onResolve,
  });

  final EcfBlockedAttempt attempt;
  final bool busy;
  final void Function(String decision) onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    attempt.operation,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Bloqueado',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              attempt.reason,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            _Meta(label: 'Intento', value: attempt.attemptId),
            if (attempt.reference != null)
              _Meta(label: 'Referencia', value: attempt.reference!),
            if (attempt.errorCode != null)
              _Meta(label: 'Código', value: attempt.errorCode!),
            _Meta(label: 'Fecha', value: _date(attempt.createdAt)),
            const SizedBox(height: 8),
            Text(
              attempt.safeAction,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: const Color(0xFF64748B),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: busy
                      ? null
                      : () => onResolve('CONFIRM_APPLIED_WITH_EVIDENCE'),
                  child: const Text('Sí se aplicó (con evidencia)'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => onResolve('CONFIRM_NOT_APPLIED_RETRYABLE'),
                  child: const Text('No se aplicó (con evidencia)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _date(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day $hour:$minute';
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
