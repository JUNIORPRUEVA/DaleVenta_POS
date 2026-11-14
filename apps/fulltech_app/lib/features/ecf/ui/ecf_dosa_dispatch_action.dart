import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_feedback.dart';
import '../data/ecf_repository.dart';
import '../data/ecf_connection_guard.dart';
import '../ecf_dosa_dispatch_models.dart';
import '../ecf_models.dart';

/// Acción de EMISIÓN AUTORIZADA contra el proveedor DOSA de la empresa.
///
/// Cuándo aparece (todas las condiciones):
///
///  * el backend informa `emissionPathAvailable == true`, que sólo ocurre con
///    el proveedor DOSA, la emisión encendida en el servidor y la certificación
///    de la empresa autorizada;
///  * el usuario tiene `prepareEcfDocuments`;
///  * el comprobante está en un estado despachable.
///
/// La interfaz NO decide nada: si aparece, el backend igualmente vuelve a
/// comprobar barrera, compuerta y credenciales. Ocultar el botón es comodidad,
/// no seguridad.
class EcfDosaDispatchAction extends ConsumerStatefulWidget {
  const EcfDosaDispatchAction({
    super.key,
    required this.documentId,
    required this.status,
    this.capabilities,
  });

  final String documentId;

  /// Estado persistido del comprobante.
  final String status;

  /// Capacidades de la empresa. Si no se aportan se leen del servidor; se deja
  /// el parámetro para poder fijarlas en pruebas sin depender de la red.
  final EcfCapabilities? capabilities;

  @override
  ConsumerState<EcfDosaDispatchAction> createState() =>
      _EcfDosaDispatchActionState();
}

class _EcfDosaDispatchActionState
    extends ConsumerState<EcfDosaDispatchAction> {
  static const _dispatchable = {'LOCAL_VALIDATED', 'READY_TO_SEND'};

  bool _running = false;
  bool _uncertain = false;
  EcfDosaDispatchOutcome? _outcome;
  String? _error;

  Future<void> _run() async {
    // Protección explícita contra doble pulsación: aunque el backend ya impide
    // el segundo envío, no queremos ni una petición de más desde la interfaz.
    if (_running || _uncertain) return;
    setState(() {
      _running = true;
      _outcome = null;
      _error = null;
    });

    try {
      final outcome =
          await ref.read(ecfRepositoryProvider).dispatchDosa(widget.documentId);
      if (!mounted) return;
      setState(() {
        _running = false;
        _outcome = outcome;
      });
      // El estado persistido cambió: se refresca desde el servidor, que es la
      // única fuente de verdad.
      ref.invalidate(ecfDocumentDetailProvider(widget.documentId));
      ref.invalidate(ecfDocumentsProvider);
      ref.invalidate(ecfCountersProvider);
    } on EcfConnectionException catch (error) {
      if (!mounted) return;
      setState(() { _running = false; _uncertain = error.uncertain; });
      ref.invalidate(ecfDocumentDetailProvider(widget.documentId));
      AppFeedback.showToast(context, title: error.noticeTitle, body: error.message,
        kind: AppFeedbackKind.warning, duration: const Duration(seconds: 4), dedupeKey: 'ecf-connection');
    } on DioException catch (error) {
      if (!mounted) return;
      final status = error.response?.statusCode;
      setState(() {
        _running = false;
        _error = status == 409
            ? 'Este comprobante ya tiene un envío registrado. No se reenvía para '
                'no duplicar el e-CF.'
            : 'No se pudo completar la emisión. Revisa la conexión e inténtalo '
                'de nuevo.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = 'No se pudo completar la emisión. Revisa la conexión e '
            'inténtalo de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = widget.capabilities ??
        ref.watch(ecfCapabilitiesProvider).valueOrNull;
    // Sin capacidades no hay decisión: el botón no aparece hasta saber si la
    // empresa puede emitir.
    if (capabilities == null || !capabilities.emissionPathAvailable) {
      return const SizedBox.shrink();
    }
    if (!hasUserPermission(
      ref.watch(authStateProvider).user,
      AppPermission.prepareEcfDocuments,
    )) {
      return const SizedBox.shrink();
    }
    if (!_dispatchable.contains(widget.status)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final outcome = _outcome;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF7FB2E5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.send_outlined,
                  size: 20,
                  color: Color(0xFF1B5E9E),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EMISIÓN ELECTRÓNICA',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF12446F),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Se enviará este comprobante al proveedor fiscal con el '
                        'RNC y las credenciales de tu empresa. Un solo envío por '
                        'comprobante.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF12446F),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _running ? null : _uncertain ? () async {
              try {
                final updated = await ref.refresh(ecfDocumentDetailProvider(widget.documentId).future);
                if (mounted && updated.summary.id == widget.documentId) setState(() => _uncertain = false);
              } catch (_) {
                if (context.mounted) {
                  AppFeedback.showToast(context, title: 'Sin conexión', body: 'No se pudo actualizar el estado.',
                    duration: const Duration(seconds: 4), dedupeKey: 'ecf-connection');
                }
              }
            } : _run,
            icon: _running
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(_running ? 'Emitiendo…' : _uncertain ? 'Actualizar estado' : 'Emitir comprobante'),
          ),
          if (outcome != null) ...[
            const SizedBox(height: 10),
            Text(
              outcome.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: outcome.ok
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (outcome.ok && outcome.encf != null) ...[
              const SizedBox(height: 2),
              Text(
                'e-NCF ${outcome.encf} · ambiente ${outcome.environment ?? "-"}',
                style: theme.textTheme.bodySmall,
              ),
            ],
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
        ],
      ),
    );
  }
}
