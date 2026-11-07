import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/company/company_settings_model.dart';
import 'ecf_flow_kit.dart';

/// Única pantalla de preparación antes de iniciar la postulación.
///
/// Reutiliza los datos que FullPOS ya tiene registrados. Solo pide lo que falta
/// y deja una única acción principal: completar los datos o iniciar el proceso
/// oficial. El certificado y las credenciales se gestionan dentro de DOSA, así
/// que no se duplican aquí.
class EcfPreparationStep extends StatelessWidget {
  const EcfPreparationStep({
    super.key,
    required this.settings,
    required this.companyReady,
    required this.contactEmailReady,
    required this.certificateReady,
    required this.dosaOwnsCertificate,
    required this.canManage,
    required this.busy,
    required this.onEditFiscalData,
    required this.onStart,
    required this.onGoCompany,
    required this.onGoCertificate,
    this.dosaEntry,
    this.activation,
    this.advanced,
    this.simulationAvailable = false,
    this.simulationBadge,
    this.simulationReason,
  });

  final CompanySettings? settings;

  /// Datos mínimos que exige la emisión (nombre, RNC y dirección).
  final bool companyReady;

  /// Correo fiscal que el backend usa al abrir la sesión oficial.
  final bool contactEmailReady;

  /// Certificado validado previamente en FullPOS. Para DOSA es historial.
  final bool certificateReady;

  /// El certificado lo pide DOSA dentro de su propio asistente.
  final bool dosaOwnsCertificate;

  final bool canManage;
  final bool busy;

  final VoidCallback onEditFiscalData;
  final VoidCallback onStart;
  final VoidCallback onGoCompany;
  final VoidCallback onGoCertificate;

  /// Acción oficial de DOSA. Si existe, es la única acción principal.
  final Widget? dosaEntry;

  /// Estado de la autorización de emisión (lo que falta para poder facturar).
  ///
  /// Va aquí y no en una pantalla aparte: el cliente ve el mismo recorrido, y
  /// cuando vuelve días después aparece con lo que le falta sin tener que
  /// buscar otro sitio.
  final Widget? activation;

  /// Controles administrativos fuera del recorrido del cliente.
  final Widget? advanced;

  final bool simulationAvailable;
  final String? simulationBadge;
  final String? simulationReason;

  bool get _dataReady => companyReady && contactEmailReady;

  bool get _certificateReadyForDosa => certificateReady || dosaOwnsCertificate;

  /// Copia un dato al portapapeles.
  ///
  /// El asistente oficial de DOSA vuelve a pedir el RNC y el correo y no
  /// admite prellenado por clave publicable, así que se copian desde aquí en
  /// lugar de reescribirlos.
  Future<void> _copy(BuildContext context, String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final companyName = (settings?.companyName ?? '').trim();
    final rnc = (settings?.rnc ?? '').trim();
    final email = (settings?.ecfContactEmail ?? '').trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EcfStepTitle(
            title: 'Preparación',
            subtitle:
                'Revisa los datos de tu empresa. Solo te pediremos lo que falte.',
          ),
          const SizedBox(height: 14),
          EcfSection(
            title: 'Tu empresa',
            icon: Icons.storefront_outlined,
            // Con DOSA y todos los datos listos no hay nada que revisar: se
            // oculta el botón en lugar de ofrecer una acción que no cambia
            // nada. Si falta algo, sigue estando ahí.
            trailing: dosaOwnsCertificate && _dataReady
                ? null
                : TextButton.icon(
                    onPressed: onEditFiscalData,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text(
                      'Revisar',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EcfField(
                  label: 'Razón social',
                  value: companyName.isEmpty ? null : companyName,
                ),
                EcfField(
                  label: 'RNC',
                  value: rnc.isEmpty ? null : rnc,
                  onCopy: rnc.isEmpty
                      ? null
                      : () => _copy(context, rnc, 'RNC copiado'),
                  copyTooltip: 'Copiar RNC',
                ),
                // Con DOSA, «Completos» no aporta nada al cliente: solo se
                // muestra cuando falta algo y hay que actuar.
                if (!(dosaOwnsCertificate && companyReady))
                  EcfSummaryRow(
                    label: 'Datos fiscales',
                    value: companyReady ? 'Completos' : 'Faltan datos',
                    tone: companyReady ? EcfTone.done : EcfTone.warning,
                    onTap: companyReady ? null : onEditFiscalData,
                  ),
                EcfSummaryRow(
                  label: 'Correo fiscal',
                  value: contactEmailReady
                      ? email
                      : 'Falta el correo de facturación',
                  tone: contactEmailReady ? EcfTone.done : EcfTone.warning,
                  onTap: contactEmailReady ? null : onEditFiscalData,
                  onCopy: contactEmailReady
                      ? () => _copy(context, email, 'Correo copiado')
                      : null,
                  copyTooltip: 'Copiar correo fiscal',
                ),
                // Con DOSA el certificado se carga dentro de su asistente.
                // No se muestra aquí para no dar a entender que ya está
                // registrado en FullPOS ni que hace falta subirlo antes.
                if (!dosaOwnsCertificate)
                  EcfSummaryRow(
                    label: 'Certificado digital',
                    value: certificateReady
                        ? 'Registrado'
                        : 'Pendiente de validar',
                    tone: certificateReady ? EcfTone.done : EcfTone.pending,
                    onTap: !certificateReady ? onGoCertificate : null,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!_dataReady)
            EcfPrimaryAction(
              label: 'Completar datos',
              icon: Icons.edit_outlined,
              onPressed: onEditFiscalData,
              helper:
                  'Solo completarás la información que falta. El resto ya está guardado.',
              buttonKey: const ValueKey('ecf_preparation_complete_data'),
            )
          else if (dosaEntry != null)
            dosaEntry!
          else if (!_certificateReadyForDosa)
            EcfPrimaryAction(
              label: 'Validar certificado',
              icon: Icons.verified_user_outlined,
              onPressed: onGoCertificate,
            )
          else if (simulationAvailable && canManage)
            EcfSection(
              title: 'Iniciar postulación',
              icon: Icons.arrow_forward_rounded,
              trailing: (simulationBadge ?? '').isNotEmpty
                  ? EcfBadge(label: simulationBadge!)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EcfPrimaryAction(
                    label: 'Iniciar postulación',
                    buttonKey: const ValueKey(
                      'ecf_intelligent_certification_button',
                    ),
                    icon: Icons.arrow_forward_rounded,
                    busy: busy,
                    onPressed: onStart,
                  ),
                  const SizedBox(height: 8),
                  EcfInlineNote(
                    tone: EcfTone.pending,
                    text: simulationReason?.trim().isNotEmpty == true
                        ? simulationReason!.trim()
                        : 'El proceso se abrirá en el entorno de certificación.',
                  ),
                ],
              ),
            )
          else
            const EcfInlineNote(
              tone: EcfTone.pending,
              text:
                  'Un administrador con permiso de facturación electrónica debe iniciar la postulación.',
            ),
          // Después de la acción principal: primero se abre el asistente, luego
          // se explica qué falta para poder facturar.
          if (activation != null) ...[
            const SizedBox(height: 14),
            activation!,
          ],
          if (advanced != null) ...[const SizedBox(height: 12), advanced!],
        ],
      ),
    );
  }
}
