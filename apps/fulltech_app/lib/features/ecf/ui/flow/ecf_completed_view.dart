import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import 'ecf_flow_kit.dart';

/// Pantalla de cierre del trámite: la empresa ya puede facturar.
///
/// Por qué una pantalla y no otra tarjeta
/// --------------------------------------
/// El recorrido guiado existía porque el cliente no sabía qué le faltaba. Una
/// vez terminado, ese andamiaje sobra: lo único útil es confirmar el final y
/// llevar al sitio donde se factura. Si el módulo siguiera abriendo en los
/// pasos, el cliente creería que aún queda algo por hacer.
///
/// Se centra de verdad (no solo horizontalmente): el mensaje es el contenido y
/// debe leerse como una confirmación, no como un formulario.
/// No se afirma en qué ambiente se emite: el estado de certificación habla de
/// credenciales y el ambiente lo decide la configuración, así que aquí solo se
/// afirma lo que consta.
class EcfCompletedView extends StatelessWidget {
  const EcfCompletedView({
    super.key,
    required this.onGoToSales,
    required this.onViewDocuments,
    this.invoicingReady = true,
    this.numbering,
  });

  /// Lleva al punto de venta, que es el único paso que queda.
  final VoidCallback onGoToSales;

  /// Alternativa secundaria para quien solo quiere revisar lo emitido.
  final VoidCallback onViewDocuments;
  final bool invoicingReady;
  final Widget? numbering;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            // Ocupa el alto disponible para que el mensaje quede centrado en la
            // pantalla; si no cabe, desplaza en vez de desbordar.
            constraints: BoxConstraints(
              minHeight: constraints.hasBoundedHeight
                  ? (constraints.maxHeight - 64).clamp(0.0, double.infinity)
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: const BoxDecoration(
                          color: AppColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_rounded,
                          size: 46,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Text(
                      invoicingReady
                          ? '¡Felicidades!'
                          : 'Revisa la facturación',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      invoicingReady
                          ? 'Terminaste el proceso de postulación. Tu empresa ya puede '
                                'facturar electrónicamente con la numeración que autorizó '
                                'la DGII.'
                          : 'Tu autorización está registrada. Revisa la numeración '
                                'y la habilitación de emisión del ambiente actual.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (!invoicingReady && numbering != null) numbering!,
                    if (invoicingReady)
                      EcfPrimaryAction(
                        label: 'Ir a ventas',
                        icon: Icons.point_of_sale_outlined,
                        onPressed: onGoToSales,
                        helper:
                            'El comprobante electrónico se elige al cobrar.',
                        buttonKey: const ValueKey('ecf_completed_go_sales'),
                      ),
                    const SizedBox(height: 6),
                    TextButton(
                      key: const ValueKey('ecf_completed_view_documents'),
                      onPressed: onViewDocuments,
                      child: const Text('Ver comprobantes electrónicos'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
