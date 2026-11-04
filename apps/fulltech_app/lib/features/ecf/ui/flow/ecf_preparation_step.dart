import 'package:flutter/material.dart';

import 'ecf_flow_kit.dart';

/// Paso «Preparación».
///
/// Un resumen de cuatro líneas y una sola acción. El botón del motor se habilita
/// exactamente con las mismas condiciones que valida el backend: no se fuerza
/// nada desde la interfaz.
class EcfPreparationStep extends StatelessWidget {
  const EcfPreparationStep({
    super.key,
    required this.companyReady,
    required this.certificateReady,
    required this.dgiiAccessReady,
    required this.pendingRequirements,
    required this.simulationAvailable,
    required this.simulationBadge,
    required this.simulationReason,
    required this.canManage,
    required this.busy,
    required this.onStart,
    required this.onGoCompany,
    required this.onGoCertificate,
    this.dosaEntry,
  });

  final bool companyReady;
  final bool certificateReady;
  final bool dgiiAccessReady;

  /// Requisitos obligatorios aún pendientes según el expediente real.
  final int pendingRequirements;

  final bool simulationAvailable;
  final String? simulationBadge;
  final String? simulationReason;
  final bool canManage;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onGoCompany;
  final VoidCallback onGoCertificate;

  /// Entrada al portal DOSA, independiente del motor de prueba legado.
  final Widget? dosaEntry;

  bool get _canRun => canManage && simulationAvailable && certificateReady;

  String get _blockedReason {
    if (!companyReady) {
      return 'Faltan datos de la empresa para postular.';
    }
    if (!certificateReady) {
      return 'Valida primero el certificado digital.';
    }
    if (!canManage) {
      return 'Solo un usuario con permiso de gestión puede iniciar la postulación.';
    }
    if (!simulationAvailable) {
      return simulationReason?.trim().isNotEmpty == true
          ? simulationReason!.trim()
          : 'El modo de prueba no está habilitado en este entorno.';
    }
    return 'Todo listo para iniciar.';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EcfStepTitle(
            title: 'Preparación',
            subtitle:
                'Revisa que todo esté listo. Después, FullPOS prepara el '
                'expediente contigo.',
          ),
          const SizedBox(height: 14),
          EcfSection(
            title: 'Antes de postular',
            icon: Icons.fact_check_outlined,
            child: Column(
              children: [
                EcfSummaryRow(
                  label: 'Datos de la empresa',
                  value: companyReady ? 'Listos' : 'Faltan datos',
                  tone: companyReady ? EcfTone.done : EcfTone.warning,
                  onTap: companyReady ? null : onGoCompany,
                ),
                EcfSummaryRow(
                  label: 'Certificado digital',
                  value: certificateReady ? 'Validado' : 'Sin validar',
                  tone: certificateReady ? EcfTone.done : EcfTone.warning,
                  onTap: certificateReady ? null : onGoCertificate,
                ),
                EcfSummaryRow(
                  label: 'Acceso al portal de la DGII',
                  value: dgiiAccessReady ? 'Confirmado' : 'Sin confirmar',
                  tone: dgiiAccessReady ? EcfTone.done : EcfTone.pending,
                ),
                EcfSummaryRow(
                  label: 'Requisitos pendientes',
                  value: pendingRequirements == 0
                      ? 'Ninguno'
                      : '$pendingRequirements',
                  tone: pendingRequirements == 0
                      ? EcfTone.done
                      : EcfTone.pending,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (dosaEntry != null) ...[dosaEntry!, const SizedBox(height: 12)],
          EcfSection(
            title: 'Postulación inteligente',
            icon: Icons.auto_awesome_outlined,
            subtitle:
                'FullPOS ejecuta los pasos que dependen del proveedor '
                'certificado. Lo que dependa de la DGII te lo indicaremos.',
            trailing: simulationAvailable && (simulationBadge ?? '').isNotEmpty
                ? EcfBadge(
                    key: const ValueKey('ecf_test_mode_badge'),
                    label: simulationBadge!,
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EcfPrimaryAction(
                  label: 'Iniciar postulación inteligente',
                  buttonKey: const ValueKey(
                    'ecf_intelligent_certification_button',
                  ),
                  icon: Icons.auto_awesome_outlined,
                  busy: busy,
                  onPressed: _canRun ? onStart : null,
                ),
                const SizedBox(height: 8),
                EcfInlineNote(
                  tone: _canRun ? EcfTone.done : EcfTone.pending,
                  icon: _canRun
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  text: _blockedReason,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
