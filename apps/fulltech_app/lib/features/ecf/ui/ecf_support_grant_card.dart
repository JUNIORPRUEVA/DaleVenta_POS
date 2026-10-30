import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ecf_repository.dart';
import '../ecf_support_grant_models.dart';

/// Asistencia temporal al equipo de Fulltech, controlada por la EMPRESA.
///
/// Principios que respeta esta tarjeta:
///
///  * **Nada se concede por defecto.** Sin una concesión explícita, el personal
///    de Fulltech no ve el expediente: el backend responde `403`.
///  * **La empresa manda.** Solo el cliente crea y revoca; el personal de
///    plataforma no puede fabricarse acceso ni ampliarse alcances.
///  * **El alcance es explícito y acotado.** Se eligen permisos concretos, no un
///    "acceso total" implícito.
///  * **Caduca.** Toda concesión tiene fecha de fin; no hay acceso indefinido.
///  * **Revocación inmediata.** Al revocar, el siguiente acceso del staff ya se
///    deniega. La tarjeta lo dice tal cual, porque es lo que hace el backend.
///
/// La concesión NO autoriza a Fulltech a aprobar nada ante la DGII: las reglas
/// de evidencia oficial se aplican igual después.
class EcfSupportGrantCard extends ConsumerStatefulWidget {
  const EcfSupportGrantCard({super.key, required this.canManage});

  /// Mismo permiso que exige el backend para crear o revocar la concesión.
  final bool canManage;

  @override
  ConsumerState<EcfSupportGrantCard> createState() =>
      _EcfSupportGrantCardState();
}

class _EcfSupportGrantCardState extends ConsumerState<EcfSupportGrantCard> {
  bool _busy = false;
  String? _error;
  bool _showHistory = false;

  Future<void> _refresh() async {
    ref.invalidate(ecfSupportGrantsProvider);
    try {
      await ref.read(ecfSupportGrantsProvider.future);
    } catch (_) {
      // El provider ya expone el error a la vista; aquí solo se evita una
      // excepción asíncrona sin manejar.
    }
  }

  Future<void> _grant() async {
    final request = await showDialog<_GrantRequest>(
      context: context,
      builder: (_) => const _GrantDialog(),
    );
    if (request == null) return;
    await _run(
      () => ref.read(ecfRepositoryProvider).createSupportGrant(
        scopes: request.scopes,
        days: request.days,
        reason: request.reason,
      ),
    );
  }

  Future<void> _revoke(EcfSupportGrant grant) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revocar la asistencia'),
        content: const Text(
          'El equipo de Fulltech perderá el acceso a tu expediente en la '
          'siguiente petición. Los documentos y el estado del proceso no se '
          'modifican.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => ref.read(ecfRepositoryProvider).revokeSupportGrant(grant.id),
    );
  }

  /// Ejecuta una mutación sin dejar la tarjeta en estado inconsistente.
  Future<void> _run(Future<Object?> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(ecfSupportGrantsProvider);
      await ref.read(ecfSupportGrantsProvider.future);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo completar la operación. Inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grants = ref.watch(ecfSupportGrantsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.support_agent_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Asistencia de Fulltech',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Autoriza al equipo de Fulltech a revisar tu expediente durante '
              'un tiempo limitado. Sin esta autorización nadie de Fulltech puede '
              'verlo, y puedes revocarla cuando quieras.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            grants.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(minHeight: 3),
              ),
              error: (_, __) => Row(
                children: [
                  const Expanded(
                    child: Text('No se pudo consultar el estado de la asistencia.'),
                  ),
                  TextButton(
                    onPressed: _refresh,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
              data: (list) => _buildBody(context, theme, list),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    EcfSupportGrantList list,
  ) {
    final active = list.activeGrant;
    final closed = list.items.where((grant) => !grant.active).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (active != null)
          _ActiveGrant(active: active)
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'No hay ninguna asistencia activa. Fulltech no tiene acceso a tu '
              'expediente.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 10),
        // `Wrap`, no `Row`: en móvil estrecho "Conceder asistencia" + "Ver
        // historial" no caben en una línea y un `Row` desbordaría.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.canManage && active == null)
              FilledButton.icon(
                onPressed: _busy ? null : _grant,
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: const Text('Conceder asistencia'),
              ),
            if (widget.canManage && active != null)
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _revoke(active),
                icon: const Icon(Icons.block_outlined, size: 18),
                label: const Text('Revocar ahora'),
              ),
            if (closed.isNotEmpty)
              TextButton(
                onPressed: () =>
                    setState(() => _showHistory = !_showHistory),
                child: Text(
                  _showHistory ? 'Ocultar historial' : 'Ver historial',
                ),
              ),
          ],
        ),
        if (_showHistory && closed.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final grant in closed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    grant.revoked
                        ? Icons.cancel_outlined
                        : Icons.schedule_outlined,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${grant.statusLabel} · ${_formatDate(grant.expiresAt)} · '
                      '${grant.scopeLabels.join(", ")}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}

class _ActiveGrant extends StatelessWidget {
  const _ActiveGrant({required this.active});

  final EcfSupportGrant active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              // `Expanded` no es decorativo: sin él el `Text` reclama su ancho
              // natural y desborda en móvil (medido: 328 px a 320 px de ancho).
              Expanded(
                child: Text(
                  'Asistencia activa hasta ${_fmt(active.expiresAt)}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final scope in active.scopeLabels)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 2),
              child: Text('· $scope', style: theme.textTheme.bodySmall),
            ),
          if ((active.reason ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                'Motivo: ${active.reason}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmt(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }
}

class _GrantRequest {
  const _GrantRequest({
    required this.scopes,
    required this.days,
    this.reason,
  });

  final List<String> scopes;
  final int days;
  final String? reason;
}

/// Diálogo de concesión: alcances explícitos, duración acotada y motivo.
class _GrantDialog extends StatefulWidget {
  const _GrantDialog();

  @override
  State<_GrantDialog> createState() => _GrantDialogState();
}

class _GrantDialogState extends State<_GrantDialog> {
  final Set<String> _scopes = <String>{'VIEW_DOSSIER'};
  int _days = 7;
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Conceder asistencia a Fulltech'),
      content: ConstrainedBox(
        // Ancho MÁXIMO, no fijo: en escritorio el diálogo no se estira sin
        // sentido y en móvil se adapta al espacio real en lugar de desbordar.
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Elige exactamente qué podrá hacer el equipo de Fulltech. No '
                'podrá aprobar nada ante la DGII en tu nombre.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final option in EcfSupportScopeOption.all)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _scopes.contains(option.value),
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _scopes.add(option.value);
                      } else {
                        _scopes.remove(option.value);
                      }
                    });
                  },
                  title: Text(option.label),
                  subtitle: Text(
                    option.description,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              Text('Duración', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final days in const [1, 7, 30])
                    ChoiceChip(
                      label: Text(days == 1 ? '1 día' : '$days días'),
                      selected: _days == days,
                      onSelected: (_) => setState(() => _days = days),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Motivo (opcional)',
                  hintText: 'Por qué necesitas asistencia',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLength: 200,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _scopes.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _GrantRequest(
                    scopes: _scopes.toList(growable: false),
                    days: _days,
                    reason: _reason.text,
                  ),
                ),
          child: const Text('Conceder'),
        ),
      ],
    );
  }
}
