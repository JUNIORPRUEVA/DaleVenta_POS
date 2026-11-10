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
  /// Gris del resumen del diseño (entre el secundario y el atenuado).
  static const _summaryColor = Color(0xFF637085);

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

    // Preparación: tarjeta sobria —título, motivos y una sola acción a la
    // derecha— tal como quedó definida en el diseño. El título nombra el
    // trámite de certificación para no confundirse con la numeración de la
    // DGII, que es otro paso y se muestra justo debajo.
    if (widget.compact) {
      return EcfSection(
        title: 'Certificación DGII',
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
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    pending.length == 1
                        ? '1 paso por completar'
                        : '${pending.length} pasos por completar',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _summaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _compactRefreshAction(),
              ],
            ),
          ],
        ),
      );
    }

    return EcfSection(
      title: 'Autorización para facturar',
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
          const SizedBox(height: 6),
          _refreshAction(),
        ],
      ),
    );
  }

  /// Botón del diseño de Preparación: compacto y alineado a la derecha.
  Widget _compactRefreshAction() {
    return SizedBox(
      height: 30,
      child: FilledButton(
        onPressed: _running ? null : _run,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: const Size(132, 30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: _running
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Actualizar estado'),
      ),
    );
  }

  Widget _refreshAction() {
    return EcfPrimaryAction(
      label: 'Actualizar estado',
      icon: Icons.refresh_rounded,
      busy: _running,
      onPressed: _running ? null : _run,
      helper: 'Es seguro repetirlo: el sistema no activa dos veces.',
      buttonKey: const ValueKey('ecf_dosa_activation_refresh'),
    );
  }
}
