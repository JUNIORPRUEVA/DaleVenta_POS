import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../ecf_models.dart';

/// Read-only projection of the authenticated company's backend state.
class EcfFiscalOverview extends StatelessWidget {
  const EcfFiscalOverview({
    super.key,
    required this.capabilities,
    required this.sequences,
    required this.onRetry,
  });

  final EcfCapabilities capabilities;
  final AsyncValue<List<EcfSequenceInfo>> sequences;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '${capabilities.environment == 'PRODUCTION' ? 'Producción' : 'Pruebas · sin validez fiscal'}'
        '${capabilities.posReady ? '' : ' · Revisa la habilitación'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 740
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: width,
                child: _panel(context, 'Tipos de comprobante', [
                  if (capabilities.documentTypes.isEmpty)
                    const Text('No hay tipos disponibles para consultar.'),
                  for (final type in capabilities.documentTypes)
                    Tooltip(
                      message: type.documentType == 'E34'
                          ? 'Requiere una factura aceptada y numeración válida.'
                          : 'La disponibilidad de emisión se valida al facturar.',
                      child: _row(
                        context,
                        type.documentType,
                        _typeDescription(type),
                      ),
                    ),
                ]),
              ),
              SizedBox(
                width: width,
                child: _panel(context, 'Rangos de numeración', [
                  sequences.when(
                    skipLoadingOnRefresh: false,
                    data: (items) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (items.isEmpty)
                          const Text('Todavía no hay rangos registrados.'),
                        for (final range in items)
                          _row(
                            context,
                            range.documentType,
                            '${range.startNumber} – ${range.endNumber}'
                            '${range.active ? '' : ' · Inactivo'}\n'
                            '${range.consumed} consumidos · ${range.remaining} restantes'
                            '${range.validUntil == null ? '' : '\nVence: ${DateFormat('dd/MM/yyyy').format(range.validUntil!)}'}',
                          ),
                      ],
                    ),
                    loading: () => const Text('Consultando numeración…'),
                    error: (_, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('No se pudo consultar la numeración.'),
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    ],
  );

  String _typeDescription(EcfDocumentTypeCapability type) {
    final name = switch (type.documentType) {
      'E31' => 'Crédito fiscal',
      'E32' => 'Consumo',
      'E34' => 'Nota de crédito',
      _ => 'Comprobante electrónico',
    };
    // POS types are determined by the server, never inferred from local ranges.
    final available = type.documentType == 'E34'
        ? capabilities.emissionPathAvailable &&
              type.allowedForCompany &&
              type.contractAllowsEmission
        : capabilities.posReady &&
              capabilities.posAvailableTypes.contains(type.documentType);
    if (type.documentType == 'E34' && available) {
      return name;
    }
    return available ? name : '$name · No disponible';
  }

  Widget _panel(BuildContext context, String title, List<Widget> children) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _row(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
