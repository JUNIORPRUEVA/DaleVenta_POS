import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ecf_repository.dart';
import '../ecf_models.dart';
import 'ecf_credit_note_action.dart';

/// Estado técnico del módulo e-CF.
///
/// Es una pantalla de DIAGNÓSTICO, no un paso de configuración: qué tipos de
/// comprobante admite la empresa, qué rangos tiene registrados y qué facturas
/// puede acreditar. Para una empresa que todavía está en habilitación todo esto
/// está vacío, así que las secciones sin contenido no se pintan.
///
/// No incluye acceso a la habilitación DGII: esa acción vive en la barra del
/// módulo y repetirla aquí solo añadía un paso intermedio.
class EcfConfigPage extends ConsumerWidget {
  const EcfConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(ecfCapabilitiesProvider);
    final sequences = ref.watch(ecfSequencesProvider);
    final originals = ref.watch(ecfEligibleOriginalsProvider);

    // Las secciones sin datos se omiten: una lista de «no hay nada» es ruido.
    final sequenceItems = sequences.valueOrNull ?? const <EcfSequenceInfo>[];
    final originalItems =
        originals.valueOrNull ?? const <EcfEligibleOriginal>[];
    final caps = capabilities.valueOrNull;

    return Scaffold(
      // Sin barra propia: el shell ya muestra el título y el botón de volver.
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(ecfCapabilitiesProvider);
          ref.invalidate(ecfSequencesProvider);
          ref.invalidate(ecfEligibleOriginalsProvider);
          await ref.read(ecfCapabilitiesProvider.future);
        },
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 940),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estado del módulo',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      const _Muted(
                        'Información técnica de la facturación electrónica de '
                        'esta empresa. La activación se hace en Menú → Empresa.',
                      ),
                      const SizedBox(height: 12),
                      capabilities.when(
                        data: (data) => _CapabilitiesLine(capabilities: data),
                        loading: () => const _Muted('Cargando…'),
                        error: (error, _) => const _Muted(
                          'No se pudo consultar el estado del módulo.',
                        ),
                      ),
                    ],
                  ),
                ),
                if (caps != null) ...[
                  const SizedBox(height: 10),
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle('Tipos de comprobante'),
                        const SizedBox(height: 2),
                        const _Muted(
                          'E32 usa un cupo de un solo uso; E31 y E34 consumen '
                          'el rango de numeración de la empresa.',
                        ),
                        const SizedBox(height: 8),
                        for (final type in caps.documentTypes)
                          _DocumentTypeRow(type: type),
                      ],
                    ),
                  ),
                ],
                if (sequenceItems.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle('Rangos de numeración'),
                        const SizedBox(height: 2),
                        const _Muted(
                          'Un número consumido no se reutiliza, ni siquiera si '
                          'el comprobante se anula o falla la emisión.',
                        ),
                        const SizedBox(height: 8),
                        for (final sequence in sequenceItems)
                          _SequenceRow(sequence: sequence),
                      ],
                    ),
                  ),
                ],
                if (originalItems.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle(
                          'Facturas originales para nota de crédito (E34)',
                        ),
                        const SizedBox(height: 2),
                        const _Muted(
                          'Solo aparecen facturas fiscalmente aceptadas con '
                          'saldo disponible.',
                        ),
                        const SizedBox(height: 8),
                        for (final original in originalItems)
                          _OriginalRow(original: original),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilitiesLine extends StatelessWidget {
  const _CapabilitiesLine({required this.capabilities});

  final EcfCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final enabled = capabilities.enabled;
    final color = enabled ? const Color(0xFF15803D) : const Color(0xFFB45309);
    final text =
        '${enabled ? 'Activa' : 'Inactiva'} · ambiente '
        '${capabilities.environment} · certificación '
        '${capabilities.certificationStatus}'
        '${capabilities.productionEnabled ? ' · producción activa' : ''}';
    return Row(
      children: [
        Icon(
          enabled ? Icons.check_circle_outline : Icons.info_outline,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Un tipo de comprobante explicado en lenguaje del negocio, sin enums crudos
/// del proveedor.
class _DocumentTypeRow extends StatelessWidget {
  const _DocumentTypeRow({required this.type});

  final EcfDocumentTypeCapability type;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      type.allowedForCompany ? 'habilitado' : 'no habilitado',
      type.allocatable ? 'consume rango propio' : 'cupo de un solo uso',
    ];
    if (!type.contractAllowsEmission) {
      parts.add('contrato del proveedor incompleto');
    }
    final blocked = !type.allowedForCompany || !type.contractAllowsEmission;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 46,
            child: Text(
              type.documentType,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Expanded(
            child: Text(
              parts.join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: blocked
                    ? const Color(0xFFB45309)
                    : const Color(0xFF475569),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SequenceRow extends StatelessWidget {
  const _SequenceRow({required this.sequence});

  final EcfSequenceInfo sequence;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              sequence.documentType,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${sequence.startNumber} – ${sequence.endNumber}'
              ' · consumidos ${sequence.consumed}'
              ' · disponibles ${sequence.remaining}'
              '${sequence.active ? '' : ' · inactivo'}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginalRow extends StatelessWidget {
  const _OriginalRow({required this.original});

  final EcfEligibleOriginal original;

  @override
  Widget build(BuildContext context) {
    final label = '${original.documentType} · ${original.encf ?? original.id}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$label · saldo disponible ${original.availableAmount}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
        ),
        const SizedBox(height: 6),
        EcfCreditNoteAction(
          originalId: original.id,
          originalLabel: label,
          availableAmount: original.availableAmount,
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1F2A37),
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
    );
  }
}
