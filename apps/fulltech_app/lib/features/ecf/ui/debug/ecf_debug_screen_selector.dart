import 'package:flutter/material.dart';

import '../../../../core/company/company_settings_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../flow/ecf_dosa_tracking_step.dart';
import '../flow/ecf_flow_kit.dart';
import '../flow/ecf_preparation_step.dart';
import '../flow/ecf_welcome_step.dart';

/// Vistas del selector de revisión visual.
///
/// Solo se construye desde código envuelto en `kDebugMode`. No existe una ruta
/// para ellas y nunca se conectan a providers ni al backend.
enum EcfDebugScreen {
  welcome('Bienvenida'),
  preparation('Preparación'),
  postulation('Tu postulación');

  const EcfDebugScreen(this.label);

  final String label;
}

/// Datos de presentación, solo en memoria.
CompanySettings _debugSettings({
  bool email = true,
  bool address = true,
}) => CompanySettings.empty().copyWith(
  companyName: 'FULLTECH, SRL',
  rnc: '133080206',
  address: address ? 'Av. 27 de Febrero 123, Santo Domingo' : '',
  phone: '8095550101',
  ecfContactEmail: email ? 'facturacion@fulltech.example' : '',
  legalRepresentativeName: 'Representante Legal',
  legalRepresentativeCedula: '00100000001',
  legalRepresentativeRole: 'Gerente',
);

/// Contenido completo de una vista de revisión.
class EcfDebugPreview extends StatelessWidget {
  const EcfDebugPreview({
    super.key,
    required this.screen,
    this.onExit,
  });

  final EcfDebugScreen screen;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final body = switch (screen) {
      EcfDebugScreen.welcome => EcfWelcomeStep(
        videoUrl: '',
        onStart: () {},
      ),
      EcfDebugScreen.preparation => EcfPreparationStep(
        settings: _debugSettings(),
        companyReady: true,
        contactEmailReady: true,
        // DOSA captura el certificado dentro de su asistente: la vista de
        // revisión no debe simular que ya está registrado en FullPOS.
        certificateReady: false,
        dosaOwnsCertificate: true,
        canManage: true,
        busy: false,
        onEditFiscalData: () {},
        onStart: () {},
        onGoCompany: () {},
        onGoCertificate: () {},
        onContinue: () {},
        dosaEntry: const _DebugActionCard(
          title: 'Postulación electrónica',
          message:
              'Abriremos el asistente oficial de DOSA con los datos de tu empresa.',
          label: 'Iniciar postulación',
        ),
      ),
      EcfDebugScreen.postulation => const EcfDosaTrackingStep(
        milestone: 1,
        statusLabel: 'En pruebas',
        statusMessage:
            'Tu solicitud fue recibida. Puedes consultar el estado real y '
            'continuar en DOSA cuando lo necesites.',
        official: false,
        portal: _DebugActionCard(
          title: 'Asistente de certificación electrónica',
          message:
              'Continúa el proceso en el asistente oficial con los datos de tu empresa.',
          label: 'Continuar con el asistente',
        ),
      ),
    };

    return Column(
      children: [
        _PreviewBar(
          screen: screen,
          onExit: onExit,
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: body,
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewBar extends StatelessWidget {
  const _PreviewBar({required this.screen, this.onExit});

  final EcfDebugScreen screen;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Vista de revisión · ${screen.label}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (onExit != null)
            TextButton(
              onPressed: onExit,
              child: const Text(
                'Volver',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}

class _DebugActionCard extends StatelessWidget {
  const _DebugActionCard({
    required this.title,
    required this.message,
    required this.label,
  });

  final String title;
  final String message;
  final String label;

  @override
  Widget build(BuildContext context) {
    return EcfSection(
      title: title,
      icon: Icons.open_in_new,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          EcfPrimaryAction(
            label: label,
            onPressed: () {},
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}


