import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';
import 'ecf_dgii_application_wizard.dart';

/// Activación e-CF self-service.
///
/// Un solo botón y un progreso honesto. La pantalla NO decide qué está hecho:
/// lo lee del motor del backend, que solo ejecuta los pasos de los que es dueño.
/// Lo que depende del cliente o de la DGII se muestra como espera con su motivo,
/// nunca como completado.
class EcfActivationPage extends ConsumerStatefulWidget {
  const EcfActivationPage({super.key});

  @override
  ConsumerState<EcfActivationPage> createState() => _EcfActivationPageState();
}

class _ActivationStep {
  const _ActivationStep({
    required this.key,
    required this.label,
    required this.className,
    required this.status,
    required this.resolved,
    required this.executable,
    required this.awaiting,
  });

  final String key;
  final String label;
  final String className;
  final String status;
  final bool resolved;

  /// El backend solo marca `executable` en los pasos que puede avanzar por su
  /// cuenta. Los que dependen del cliente o de la DGII nunca lo están.
  final bool executable;
  final String? awaiting;

  factory _ActivationStep.fromJson(Map<String, dynamic> json) => _ActivationStep(
    key: (json['key'] ?? '').toString(),
    label: (json['label'] ?? '').toString(),
    className: (json['className'] ?? '').toString(),
    status: (json['status'] ?? '').toString(),
    resolved: json['resolved'] == true,
    executable: json['executable'] == true,
    awaiting: json['awaiting'] as String?,
  );
}

class _ActivationView {
  const _ActivationView({
    required this.stage,
    required this.resolvedCount,
    required this.total,
    required this.percent,
    required this.transport,
    required this.steps,
  });

  final String stage;
  final int resolvedCount;
  final int total;
  final int percent;
  final String transport;
  final List<_ActivationStep> steps;

  factory _ActivationView.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] is Map
        ? (json['summary'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final rawSteps = json['steps'];
    return _ActivationView(
      stage: (summary['stage'] ?? '').toString(),
      resolvedCount: summary['resolvedCount'] is num
          ? (summary['resolvedCount'] as num).toInt()
          : 0,
      total: summary['total'] is num ? (summary['total'] as num).toInt() : 0,
      percent: summary['percent'] is num ? (summary['percent'] as num).toInt() : 0,
      transport: (json['transport'] ?? '').toString(),
      steps: rawSteps is List
          ? rawSteps
                .whereType<Map>()
                .map((row) => _ActivationStep.fromJson(row.cast<String, dynamic>()))
                .toList(growable: false)
          : const <_ActivationStep>[],
    );
  }
}

class _EcfActivationPageState extends ConsumerState<EcfActivationPage> {
  _ActivationView? _view;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(dioProvider)
          .get('/ecf/dgii/activation');
      if (!mounted) return;
      setState(() {
        _view = _ActivationView.fromJson((res.data as Map).cast<String, dynamic>());
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(dioProvider)
          .post('/ecf/dgii/activation/start');
      if (!mounted) return;
      setState(() {
        _view = _ActivationView.fromJson((res.data as Map).cast<String, dynamic>());
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  String _messageFor(Object error) {
    final text = error.toString();
    if (text.contains('ECF_ACTIVATION_REAL_TRANSPORT_NOT_CONFIGURED')) {
      return 'La conexión real con el proveedor aún no está habilitada.';
    }
    if (text.contains('ECF_ACTIVATION_FISCAL_DATA_MISSING')) {
      return 'Faltan datos fiscales de la empresa.';
    }
    if (text.contains('ECF_ACTIVATION_APPLICATION_NOT_SUBMITTED')) {
      return 'Primero envía el expediente desde el asistente de postulación.';
    }
    return 'No se pudo consultar la activación. Inténtalo de nuevo.';
  }

  /// Solo se ofrece ejecutar cuando el motor tiene algún paso que de verdad
  /// puede avanzar solo. Si todo depende del cliente o de la DGII, el botón no
  /// debe prometer un avance que el backend no va a poder hacer.
  bool get _canRun =>
      _view?.steps.any((step) => step.executable && !step.resolved) ?? false;

  String get _stageText {
    switch (_view?.stage) {
      case 'NOT_STARTED':
        return 'Sin iniciar';
      case 'RUNNING':
        return 'En proceso';
      case 'BLOCKED_ON_CLIENT':
        return 'Necesita tu intervención';
      case 'BLOCKED_ON_PROVIDER':
        return 'En manos del proveedor';
      case 'AWAITING_AUTHORITY':
        return 'Pendiente de la DGII';
      case 'COMPLETED':
        return 'Proceso interno completado';
      default:
        return 'Consultando…';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activar facturación electrónica'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy && _view == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_stageText, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: (_view?.percent ?? 0) / 100),
                        const SizedBox(height: 6),
                        Text(
                          '${_view?.resolvedCount ?? 0} de ${_view?.total ?? 0} pasos · ${_view?.percent ?? 0} %',
                          style: theme.textTheme.bodySmall,
                        ),
                        if ((_view?.transport ?? '').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.science_outlined, size: 16, color: theme.colorScheme.outline),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Transporte ${_view!.transport}. Las pruebas no acreditan habilitación de la DGII.',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy || !_canRun ? null : _start,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Activar facturación electrónica'),
                          ),
                        ),
                        if (!_busy &&
                            !_canRun &&
                            (_view?.steps.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 8),
                          Text(
                            'En este momento no hay ningún paso que el sistema '
                            'pueda ejecutar por su cuenta. Completa lo que depende '
                            'de ti y vuelve a consultar.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Pasos', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                for (final step in _view?.steps ?? const <_ActivationStep>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      step.resolved
                          ? Icons.check_circle
                          : step.className == 'AUTOMATIC_LOCAL' ||
                                step.className == 'PROVIDER_WAIT'
                          ? Icons.pending_outlined
                          : Icons.lock_clock,
                      size: 20,
                      color: step.resolved
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                    ),
                    title: Text(step.label),
                    subtitle: Text(step.awaiting ?? step.className),
                    trailing: step.className == 'CLIENT_ACTION'
                        ? TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const EcfDgiiApplicationWizard(),
                              ),
                            ),
                            child: const Text('Completar'),
                          )
                        : null,
                  ),
              ],
            ),
    );
  }
}
