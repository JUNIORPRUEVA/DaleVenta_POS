import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../ui/flow/ecf_flow_kit.dart';
import 'dosa_certification_diagnostic.dart';

/// Vista administrativa de solo lectura, cerrada hasta una acción explícita.
class DosaCertificationDiagnosticSection extends ConsumerStatefulWidget {
  const DosaCertificationDiagnosticSection({super.key});

  @override
  ConsumerState<DosaCertificationDiagnosticSection> createState() =>
      _DosaCertificationDiagnosticSectionState();
}

class _DosaCertificationDiagnosticSectionState
    extends ConsumerState<DosaCertificationDiagnosticSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final companyId = user?.companyId?.trim() ?? '';
    if (companyId.isEmpty ||
        !hasUserPermission(user, AppPermission.manageEcfOnboarding)) {
      return const SizedBox.shrink();
    }

    return EcfSection(
      title: 'Diagnóstico administrativo',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _open = !_open),
            icon: Icon(_open ? Icons.expand_less : Icons.expand_more),
            label: Text(_open ? 'Ocultar diagnóstico' : 'Ver diagnóstico'),
          ),
          if (_open) ...[
            const SizedBox(height: 8),
            ref
                .watch(dosaCertificationDiagnosticProvider(companyId))
                .when(
                  loading: () =>
                      const Text('Consultando el intento existente...'),
                  error: (error, _) => _error(context, error, companyId),
                  data: (value) => _details(context, value),
                ),
          ],
        ],
      ),
    );
  }

  Widget _error(BuildContext context, Object error, String companyId) {
    final failure = error is DosaDiagnosticException ? error.failure : null;
    final message = switch (failure) {
      DosaDiagnosticFailure.accessDenied =>
        'No tienes permiso para consultar este diagnóstico. Inicia sesión '
            'con una cuenta administradora autorizada.',
      DosaDiagnosticFailure.companyMismatch =>
        'La respuesta no corresponde a la empresa actual. No se muestran datos.',
      _ => 'No se pudo consultar el diagnóstico. Inténtalo de nuevo.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: Theme.of(context).textTheme.bodySmall),
        TextButton(
          onPressed: () =>
              ref.invalidate(dosaCertificationDiagnosticProvider(companyId)),
          child: const Text('Reintentar consulta'),
        ),
      ],
    );
  }

  Widget _details(BuildContext context, DosaCertificationDiagnostic value) {
    final attempt = value.attempt;
    if (attempt == null) {
      return const Text('No hay un intento registrado para esta empresa.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _line(context, 'Intento', '${attempt.number}'),
        _line(context, 'Estado', _status(attempt.status)),
        _line(
          context,
          'Proveedor registrado',
          _provider(attempt.recordedProvider),
        ),
        if (attempt.effectiveProvider != attempt.recordedProvider)
          _line(context, 'Proveedor efectivo', _provider(attempt.effectiveProvider)),
        _line(
          context,
          'Sesión externa',
          attempt.hasProviderSessionUrl
              ? 'Referencia presente'
              : 'Sin referencia',
        ),
        _line(
          context,
          'Postulación externa',
          attempt.hasProviderPostulationId
              ? 'Referencia presente'
              : 'Sin referencia',
        ),
        _line(
          context,
          'Atribución histórica',
          value.providerHistory.isEmpty
              ? 'Sin registro verificable'
              : value.providerHistory.map(_provider).join(' · '),
        ),
        _line(
          context,
          'Reconciliación administrativa',
          value.requiresReconciliation
              ? 'Necesaria antes de abrir el portal'
              : 'No requerida por atribución',
        ),
      ],
    );
  }

  Widget _line(BuildContext context, String label, String value) {
    final text = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('$label: $value', softWrap: true, style: text),
    );
  }

  String _provider(String value) => switch (value) {
    'DOSA' => 'FullPOS Cloud',
    'ALANUBE' => 'Proveedor anterior',
    _ => 'Sin atribución verificable',
  };

  String _status(String value) => switch (value) {
    'NOT_STARTED' => 'Sin iniciar',
    'RUNNING' => 'En curso',
    'ATTENTION' => 'Requiere atención',
    'COMPLETED' => 'Asistente completado',
    'FAILED' => 'No completado',
    'CANCELLED' => 'Cancelado',
    'EXPIRED' => 'Vencido',
    _ => 'Estado sin confirmar',
  };
}
