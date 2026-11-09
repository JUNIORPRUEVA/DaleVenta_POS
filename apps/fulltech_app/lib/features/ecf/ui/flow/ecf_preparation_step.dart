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
    this.sequence,
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

  /// Declaración del rango de numeración (e-NCF). Se oculta sola si ya existe.
  final Widget? sequence;

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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfStepTitle(
                title: 'Preparación',
                subtitle: 'Solo te pediremos lo que falte.',
              ),
              const SizedBox(height: 14),
              // Solo lo PENDIENTE. Si los datos de la empresa ya están completos no
              // se repiten aquí: quedan a la vista en Configuración y esta pantalla
              // se dedica a lo que de verdad falta para poder facturar.
              if (!_dataReady) ...[
                EcfSection(
                  title: 'Completa lo que falta',
                  icon: Icons.edit_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!companyReady)
                        EcfSummaryRow(
                          label: 'Datos fiscales',
                          value: 'Faltan datos de tu empresa',
                          tone: EcfTone.warning,
                          onTap: onEditFiscalData,
                        ),
                      if (!contactEmailReady)
                        EcfSummaryRow(
                          label: 'Correo fiscal',
                          value: 'Falta el correo de facturación',
                          tone: EcfTone.warning,
                          onTap: onEditFiscalData,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (!dosaOwnsCertificate &&
                  (rnc.isNotEmpty || email.isNotEmpty))
                // Solo antes de postularse: el asistente oficial vuelve a pedir
                // el RNC y el correo y no admite prellenado, así que se copian
                // en un solo toque. Una empresa que ya se postuló no necesita
                // volver a verlos.
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 15,
                        color: Color(0xFF1B7F3B),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          companyName.isEmpty
                              ? 'Datos de tu empresa listos'
                              : '$companyName · $rnc',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // El asistente oficial vuelve a pedir el RNC y el correo y no
                      // admite prellenado: se copian desde aquí en un solo toque.
                      TextButton(
                        onPressed: () => _copy(
                          context,
                          [
                            rnc,
                            email,
                          ].where((value) => value.isNotEmpty).join('\n'),
                          'Datos copiados',
                        ),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text(
                          'Copiar',
                          style: TextStyle(fontSize: 12),
                        ),
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
              if (sequence != null) ...[const SizedBox(height: 12), sequence!],
              if (advanced != null) ...[const SizedBox(height: 12), advanced!],
            ],
          ),
        ),
      ),
    );
  }
}
