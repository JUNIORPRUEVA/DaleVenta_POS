import 'package:flutter/material.dart';

import '../../../../core/company/company_settings_model.dart';
import 'ecf_flow_kit.dart';

/// Paso «Empresa y certificado digital».
///
/// Todo lo que FullPOS ya sabe se **muestra**, no se vuelve a pedir. Cuando
/// falta un dato obligatorio se ofrece el mecanismo que ya existe (`EcfFiscalDataContent`),
/// nunca un segundo expediente.
class EcfCompanyStep extends StatelessWidget {
  const EcfCompanyStep({
    super.key,
    required this.settings,
    required this.fiscalReady,
    required this.certificate,
    required this.onEditFiscalData,
    required this.onContinue,
    required this.wide,
    this.certificateReady = false,
    this.certificateVerifiedHere = false,
    this.certificateBlockedReason,
    this.dosaOwnsCertificate = false,
  });

  final CompanySettings? settings;
  final bool fiscalReady;

  /// Bloque de certificado digital (se inyecta para poder probarlo solo).
  final Widget certificate;

  /// El certificado ya es utilizable y su titular está identificado (o el
  /// expediente ya lo tiene registrado). Es la condición que habilita avanzar.
  final bool certificateReady;

  /// Oculta el texto de ayuda una vez verificado en esta sesión.
  final bool certificateVerifiedHere;

  /// Qué falta exactamente cuando el certificado bloquea el avance.
  final String? certificateBlockedReason;

  /// El certificado lo pide el asistente oficial de DOSA durante la
  /// postulación. En ese caso la validación previa en FullPOS deja de ser un
  /// requisito para avanzar: se conserva como historial, no como duplicado.
  final bool dosaOwnsCertificate;

  final VoidCallback onEditFiscalData;
  final VoidCallback onContinue;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final company = _CompanyCard(
      settings: settings,
      fiscalReady: fiscalReady,
      onEdit: onEditFiscalData,
    );
    final cert = EcfSection(
      title: 'Certificado digital',
      icon: Icons.verified_user_outlined,
      // La descripción refleja el tratamiento real: el archivo y la contraseña
      // se validan en FullPOS Cloud (cifrados en tránsito) y no se guardan.
      subtitle: certificateVerifiedHere
          ? null
          : dosaOwnsCertificate
          ? 'El asistente de DOSA solicita el certificado durante la '
                'postulación. Aquí solo se conserva el historial de la última '
                'comprobación: no hay que subirlo dos veces.'
          : 'Se comprueba en FullPOS Cloud y no se guarda. No se envía a la '
                'la DGII ni al proveedor de certificación.',
      child: certificate,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EcfStepTitle(
            title: 'Tu empresa',
            subtitle:
                'Usamos los datos que ya tienes registrados en FullPOS. No '
                'tienes que volver a escribirlos.',
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: company),
                const SizedBox(width: 12),
                Expanded(flex: 6, child: cert),
              ],
            )
          else ...[
            company,
            const SizedBox(height: 12),
            cert,
          ],
          const SizedBox(height: 16),
          if (!fiscalReady)
            EcfPrimaryAction(
              label: 'Completar datos de la empresa',
              icon: Icons.edit_outlined,
              onPressed: onEditFiscalData,
              helper: 'Sin estos datos la DGII no puede identificar al emisor.',
              buttonKey: const ValueKey('ecf_company_step_primary'),
            )
          else
            EcfPrimaryAction(
              label: 'Continuar',
              // Con DOSA al mando del certificado, avanzar solo depende de los
              // datos de la empresa. Sin esa excepción se pediría el mismo
              // certificado dos veces.
              onPressed: (certificateReady || dosaOwnsCertificate)
                  ? onContinue
                  : null,
              helper: certificateReady
                  ? 'Certificado comprobado. Puedes continuar.'
                  : dosaOwnsCertificate
                  ? 'Puedes continuar: el certificado se pide dentro del '
                        'asistente de DOSA.'
                  : (certificateBlockedReason ??
                        'Valida el certificado digital para continuar.'),
              buttonKey: const ValueKey('ecf_company_step_continue'),
            ),
        ],
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({
    required this.settings,
    required this.fiscalReady,
    required this.onEdit,
  });

  final CompanySettings? settings;
  final bool fiscalReady;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return EcfSection(
      title: 'Datos de la empresa',
      icon: Icons.storefront_outlined,
      subtitle: 'Tomados de la configuración de tu empresa.',
      trailing: TextButton.icon(
        onPressed: onEdit,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: const Icon(Icons.edit_outlined, size: 15),
        label: const Text('Editar', style: TextStyle(fontSize: 12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EcfField(label: 'RNC', value: settings?.rnc),
          EcfField(label: 'Razón social', value: settings?.companyName),
          EcfField(label: 'Dirección', value: settings?.address),
          EcfField(label: 'Teléfono', value: settings?.phone),
          EcfField(
            label: 'Representante autorizado',
            value: settings?.legalRepresentativeName,
          ),
          if ((settings?.legalRepresentativeCedula ?? '').trim().isNotEmpty)
            EcfField(
              label: 'Cédula del representante',
              value: settings?.legalRepresentativeCedula,
            ),
          if ((settings?.legalRepresentativeRole ?? '').trim().isNotEmpty)
            EcfField(label: 'Cargo', value: settings?.legalRepresentativeRole),
          if (!fiscalReady)
            const EcfInlineNote(
              tone: EcfTone.warning,
              text:
                  'Faltan datos obligatorios para facturar. Los completas en '
                  'un momento y no tienes que volver a escribir lo que ya está.',
            ),
        ],
      ),
    );
  }
}
