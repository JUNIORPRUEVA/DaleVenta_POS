import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/config/uat_api_config.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';

/// ¿Se muestra la acción de despacho SIMULADO?
///
/// Es una constante de compilación (`FULLPOS_UAT_PROFILE`): en un build comercial
/// la acción **nunca** aparece. Se expone como provider para poder sustituirla en
/// las pruebas sin recompilar con `--dart-define`.
final ecfSimulatedDispatchVisibleProvider = Provider<bool>(
  (ref) => UatApiConfig.isUatProfile,
);

/// Acción de validación: **DESPACHO SIMULADO** de un comprobante e-CF.
///
/// Es una herramienta de validación local, no una emisión. Solo se renderiza si:
///
///  * el build es un perfil UAT (`FULLPOS_UAT_PROFILE`);
///  * la EMPRESA tiene la facturación electrónica habilitada;
///  * el usuario tiene `prepareEcfDocuments`;
///  * el comprobante está en un estado despachable.
///
/// El backend, además, se niega fuera de una UAT local o si el transporte real
/// estuviera activo. El resultado **nunca** es aceptación de la DGII: el
/// simulador solo sirve para comprobar la cadena.
class EcfSimulatedDispatchAction extends ConsumerStatefulWidget {
  const EcfSimulatedDispatchAction({
    super.key,
    required this.documentId,
    required this.status,
  });

  final String documentId;

  /// Estado persistido del comprobante. Solo se ofrece el despacho en los
  /// estados que el backend acepta (`LOCAL_VALIDATED`, `READY_TO_SEND`).
  final String status;

  @override
  ConsumerState<EcfSimulatedDispatchAction> createState() =>
      _EcfSimulatedDispatchActionState();
}

class _EcfSimulatedDispatchActionState
    extends ConsumerState<EcfSimulatedDispatchAction> {
  static const _dispatchable = {'LOCAL_VALIDATED', 'READY_TO_SEND'};

  /// Escenarios que el simulador sabe reproducir y que son útiles aquí. No
  /// existe ninguna opción "real".
  static const _scenarios = <String, String>{
    'PROVIDER_ACCEPTED': 'Aceptación del proveedor (simulada)',
    'PROVIDER_REJECTED': 'Rechazo del proveedor (simulado)',
    'PENDING_RECOVERY': 'Respuesta pendiente',
    'TIMEOUT': 'Timeout del proveedor',
    'MALFORMED_RESPONSE': 'Respuesta ilegible',
  };

  bool _running = false;
  String _scenario = 'PROVIDER_ACCEPTED';
  EcfSimulatedDispatchOutcome? _outcome;
  String? _blockedReason;
  String? _error;

  Future<void> _run() async {
    if (_running) return; // protección contra doble pulsación
    setState(() {
      _running = true;
      _outcome = null;
      _blockedReason = null;
      _error = null;
    });

    try {
      final outcome = await ref
          .read(ecfRepositoryProvider)
          .simulateDispatch(documentId: widget.documentId, scenario: _scenario);
      if (!mounted) return;
      setState(() {
        _running = false;
        _outcome = outcome;
      });
      // El estado persistido ha cambiado: se refresca el detalle, la bandeja y
      // los contadores desde el servidor (fuente única de verdad).
      ref.invalidate(ecfDocumentDetailProvider(widget.documentId));
      ref.invalidate(ecfDocumentsProvider);
      ref.invalidate(ecfCountersProvider);
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _running = false;
        if (status == 409) {
          _blockedReason = _reasonFrom(error.response?.data);
        } else {
          _error =
              'No se pudo ejecutar la simulación. Revisa la conexión e inténtalo de nuevo.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error =
            'No se pudo ejecutar la simulación. Revisa la conexión e inténtalo de nuevo.';
      });
    }
  }

  /// El backend devuelve el motivo del bloqueo como mensaje de error.
  String _reasonFrom(dynamic data) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
      if (message is List && message.isNotEmpty) {
        return message.whereType<String>().join(' | ');
      }
    }
    if (data is String && data.trim().isNotEmpty) return data.trim();
    return 'El backend rechazó la simulación en este entorno.';
  }

  @override
  Widget build(BuildContext context) {
    // Silencio deliberado, igual que en `EcfPrepareAction`: si no se cumplen
    // TODAS las condiciones, la acción no existe.
    if (!ref.watch(ecfSimulatedDispatchVisibleProvider)) {
      return const SizedBox.shrink();
    }
    final ecfEnabled =
        ref.watch(companySettingsProvider).valueOrNull?.ecfEnabled ?? false;
    if (!ecfEnabled) return const SizedBox.shrink();
    if (!hasUserPermission(
      ref.watch(authStateProvider).user,
      AppPermission.prepareEcfDocuments,
    )) {
      return const SizedBox.shrink();
    }
    if (!_dispatchable.contains(widget.status)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Aviso obligatorio: nunca debe confundirse con una aprobación real.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8A33D)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.science_outlined,
                  size: 20,
                  color: Color(0xFFB26A00),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SIMULACIÓN — NO VÁLIDO COMO ACEPTACIÓN DGII.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF7A4A00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ejecuta el comprobante contra el proveedor SIMULADO para '
                        'validar la cadena. No envía nada a Alanube ni a la DGII y '
                        'no asigna aceptación fiscal.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF7A4A00),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _scenario,
            decoration: const InputDecoration(
              labelText: 'Escenario simulado',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final entry in _scenarios.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: _running
                ? null
                : (value) {
                    if (value != null) setState(() => _scenario = value);
                  },
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(_running ? 'Ejecutando…' : 'Ejecutar despacho simulado'),
          ),
          if (_blockedReason != null) ...[
            const SizedBox(height: 10),
            Text(
              'Bloqueado por el backend: $_blockedReason',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_outcome != null) ...[
            const SizedBox(height: 12),
            _OutcomePanel(outcome: _outcome!),
          ],
        ],
      ),
    );
  }
}

class _OutcomePanel extends StatelessWidget {
  const _OutcomePanel({required this.outcome});

  final EcfSimulatedDispatchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      ('Escenario', outcome.scenario),
      ('Resultado observado', outcome.providerOutcome),
      ('Correlacionada', outcome.correlated ? 'sí' : 'no'),
      if (outcome.safeCode != null) ('Código', outcome.safeCode!),
      ('Aceptación fiscal oficial', 'no'),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resultado de la simulación',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '$label: $value',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'El comprobante queda en revisión humana. Esta simulación no acredita '
            'aceptación de la DGII.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
