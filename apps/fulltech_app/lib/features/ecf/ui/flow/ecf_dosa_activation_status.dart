import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/ecf_repository.dart';
import '../../ecf_dosa_activation_models.dart';
import 'ecf_flow_kit.dart';

/// Estado de la autorización de emisión, con lo que falta y un botón para
/// reintentar.
///
/// Es la ÚNICA pieza de interfaz que faltaba para que el cliente cierre el
/// circuito solo: el asistente de DOSA completa la certificación, pero la
/// cuenta se activa cuando el backend comprueba la evidencia completa (sesión,
/// confirmación de DOSA, aprobación de la DGII y la autorización del propio
/// cliente). Cuando falta algo, aquí se dice qué — en español y sin códigos
/// crípticos.
///
/// Decisiones de diseño:
///
/// * **Consulta al aparecer.** Si el cliente vuelve días después, el estado se
///   actualiza solo; no tiene que adivinar que hay un botón.
/// * **No oculta motivos desconocidos.** Un código nuevo del backend se muestra
///   en crudo: el cliente puede pasárselo a soporte.
/// * **Un solo botón, protegido contra doble toque.** La llamada ya es
///   idempotente, pero dos peticiones simultáneas no aportan nada.
/// * **Autorizado desaparece.** Cuando queda autorizado no se deja un bloque
///   verde permanente: se muestra una línea y nada más que hacer.
class EcfDosaActivationStatus extends ConsumerStatefulWidget {
  const EcfDosaActivationStatus({
    super.key,
    required this.canManage,
    this.compact = false,
  });

  /// Mismo permiso que exige el backend (`manageEcfOnboarding`). Sin él no se
  /// muestra: un botón que el servidor va a rechazar es peor que no tenerlo.
  final bool canManage;

  /// Versión reducida, para el paso de Preparación.
  final bool compact;

  @override
  ConsumerState<EcfDosaActivationStatus> createState() =>
      _EcfDosaActivationStatusState();
}

class _EcfDosaActivationStatusState
    extends ConsumerState<EcfDosaActivationStatus> {
  EcfDosaActivationOutcome? _outcome;
  bool _running = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Se consulta al aparecer: el cliente que vuelve después no tiene que saber
    // que existe un botón para actualizar. Sin permiso NO se consulta: el
    // backend respondería 403 y no hay nada que mostrar.
    if (!widget.canManage) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _failed = false;
    });
    try {
      final outcome = await ref
          .read(ecfRepositoryProvider)
          .attemptDosaActivation();
      if (!mounted) return;
      setState(() => _outcome = outcome);
    } catch (_) {
      // Un fallo de red no se confunde con «falta evidencia»: son cosas
      // distintas y el cliente merece saber que se puede reintentar.
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canManage) return const SizedBox.shrink();

    final outcome = _outcome;

    if (_failed && outcome == null) {
      return EcfInlineNote(
        tone: EcfTone.warning,
        icon: Icons.cloud_off_outlined,
        text: 'No se pudo comprobar el estado. Revisa tu conexión e inténtalo '
            'de nuevo.',
      );
    }

    if (outcome == null) {
      // Primera consulta en curso: una línea, no un bloque que salte al llegar
      // la respuesta.
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            // `Expanded`: en pantallas de 360 px el texto debe envolver, no
            // desbordar el ancho.
            Expanded(
              child: Text(
                'Comprobando tu estado…',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (outcome.authorized) {
      return EcfInlineNote(
        tone: EcfTone.done,
        icon: Icons.verified_rounded,
        text: outcome.certificationStatus == 'PRODUCTION_READY'
            ? 'Autorizado para facturar electrónicamente en producción.'
            : 'Autorizado para facturar electrónicamente en ambiente de '
                  'certificación.',
      );
    }

    final pending = outcome.pendingMessages;

    // La tarjeta es la misma en Preparación y en Postulación: fuera de ella el
    // aviso parecía un texto suelto sobre el fondo y no se leía como un estado
    // del expediente. Cambia el título, no la estructura.
    return EcfSection(
      title: widget.compact
          ? 'Qué falta para facturar'
          : 'Autorización para facturar',
      subtitle: 'Esto es lo que falta para poder emitir comprobantes.',
      icon: Icons.fact_check_outlined,
      trailing: _running
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final message in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2, right: 8),
                    child: Icon(
                      Icons.radio_button_unchecked,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.compact && pending.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4),
              child: Text(
                // Plural real: «Y 1 paso(s) más» se leía como un texto sin
                // terminar. Con un único paso restante ni siquiera es plural.
                pending.length == 2
                    ? 'Y 1 paso más por completar.'
                    : 'Y ${pending.length - 1} pasos más por completar.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          const SizedBox(height: 6),
          _refreshAction(full: true),
        ],
      ),
    );
  }

  Widget _refreshAction({bool full = false}) {
    if (full) {
      return EcfPrimaryAction(
        label: 'Actualizar estado',
        icon: Icons.refresh_rounded,
        busy: _running,
        onPressed: _running ? null : _run,
        helper: 'Es seguro repetirlo: el sistema no activa dos veces.',
        buttonKey: const ValueKey('ecf_dosa_activation_refresh'),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _running ? null : _run,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: const Text(
          'Actualizar estado',
          style: TextStyle(fontSize: 12.5),
        ),
      ),
    );
  }
}
