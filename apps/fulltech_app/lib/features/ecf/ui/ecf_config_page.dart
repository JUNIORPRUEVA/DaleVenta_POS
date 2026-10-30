import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';
import 'ecf_credit_note_action.dart';

/// Configuración e-CF de la empresa.
///
/// e-CF está APAGADO por defecto: habilitarlo solo enciende el interruptor de la
/// empresa y nunca emite ni contacta al proveedor.
class EcfConfigPage extends ConsumerWidget {
  const EcfConfigPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(ecfCapabilitiesProvider);
    final sequences = ref.watch(ecfSequencesProvider);
    final originals = ref.watch(ecfEligibleOriginalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración e-CF'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Routes.ecf),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          capabilities.when(
            data: (data) => _EnabledCard(capabilities: data),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text(
              'No se pudo cargar la configuración e-CF.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 16),
          capabilities.when(
            data: (data) => _DocumentTypesCard(capabilities: data),
            loading: () => const SizedBox.shrink(),
            error: (error, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Habilitación DGII',
            subtitle:
                'Seguimiento del proceso de incorporación de la empresa. Nadie '
                'dentro de FullPOS puede declarar la aprobación oficial: eso '
                'depende de la DGII.',
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: () => context.go(Routes.ecfDgii),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Abrir habilitación DGII'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Rangos de numeración',
            subtitle:
                'Un número consumido nunca se reutiliza, ni siquiera si el '
                'comprobante se anula o falla la emisión.',
            child: sequences.when(
              data: (items) => items.isEmpty
                  ? const Text('Sin rangos registrados para esta empresa.')
                  : Column(
                      children: [
                        for (final sequence in items)
                          _SequenceTile(sequence: sequence),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => const Text('No se pudieron cargar los rangos.'),
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Facturas originales para nota de crédito (E34)',
            subtitle:
                'Solo aparecen facturas fiscalmente aceptadas con saldo '
                'disponible. El saldo lo calcula la política fiscal del backend.',
            child: originals.when(
              data: (items) => items.isEmpty
                  ? const Text('No hay facturas elegibles en este momento.')
                  : Column(
                      children: [
                        for (final original in items)
                          _OriginalTile(original: original),
                      ],
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  const Text('No se pudieron cargar las facturas elegibles.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EnabledCard extends ConsumerStatefulWidget {
  const _EnabledCard({required this.capabilities});

  final EcfCapabilities capabilities;

  @override
  ConsumerState<_EnabledCard> createState() => _EnabledCardState();
}

class _EnabledCardState extends ConsumerState<_EnabledCard> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capabilities = widget.capabilities;
    // Solo lectura a propósito: el interruptor vive en Menú → Empresa, junto a
    // impuestos y comprobantes fiscales. Tenerlo también aquí era una segunda
    // fuente de verdad para el mismo dato.
    return Card(
      child: ListTile(
        leading: Icon(
          capabilities.enabled
              ? Icons.toggle_on_outlined
              : Icons.toggle_off_outlined,
        ),
        title: Text(
          capabilities.enabled
              ? 'Facturación electrónica habilitada'
              : 'Facturación electrónica deshabilitada',
        ),
        subtitle: Text(
          'Ambiente ${capabilities.environment} · '
          'certificación ${capabilities.certificationStatus}'
          '${capabilities.productionEnabled ? ' · producción activa' : ''}\n'
          'Para activarla o desactivarla, ve a Menú → Empresa.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _DocumentTypesCard extends StatelessWidget {
  const _DocumentTypesCard({required this.capabilities});

  final EcfCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Tipos de comprobante',
      subtitle:
          'E32 usa un cupo de un solo uso; E31 y E34 consumen el rango de la '
          'empresa.',
      child: Column(
        children: [
          for (final type in capabilities.documentTypes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Chip(label: Text(type.documentType)),
              title: Text('Contrato: ${type.contractStatus}'),
              subtitle: Text(
                [
                  type.allowedForCompany ? 'habilitado' : 'no habilitado',
                  type.allocatable ? 'rango propio' : 'cupo único',
                  type.contractAllowsEmission
                      ? 'contrato apto'
                      : 'contrato incompleto',
                ].join(' · '),
              ),
            ),
        ],
      ),
    );
  }
}

class _SequenceTile extends StatelessWidget {
  const _SequenceTile({required this.sequence});

  final EcfSequenceInfo sequence;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: sequence.active
            ? scheme.primary.withValues(alpha: 0.15)
            : scheme.surfaceContainerHighest,
        child: Text(sequence.documentType),
      ),
      title: Text(
        '${sequence.startNumber} – ${sequence.endNumber}'
            '${sequence.active ? '' : ' (inactivo)'}',
      ),
      subtitle: Text(
        'Consumidos ${sequence.consumed} · disponibles ${sequence.remaining}',
      ),
    );
  }
}

class _OriginalTile extends StatelessWidget {
  const _OriginalTile({required this.original});

  final EcfEligibleOriginal original;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long_outlined),
          title: Text('${original.documentType} · ${original.encf ?? original.id}'),
          subtitle: Text('Saldo disponible ${original.availableAmount}'),
        ),
        EcfCreditNoteAction(
          originalId: original.id,
          originalLabel: '${original.documentType} · ${original.encf ?? original.id}',
          availableAmount: original.availableAmount,
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
