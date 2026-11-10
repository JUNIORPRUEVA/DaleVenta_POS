import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
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
                          'E31, E32 y E34 consumen el rango de numeración que la '
                          'DGII autorizó a la empresa.',
                        ),
                        const SizedBox(height: 8),
                        for (final type in caps.documentTypes)
                          _DocumentTypeRow(type: type),
                      ],
                    ),
                  ),
                ],
                // Solo tiene sentido cuando la empresa YA factura
                // electrónicamente: sin e-CF no hay comprobante del que
                // prescindir.
                if (caps != null && caps.enabled) ...[
                  const SizedBox(height: 10),
                  EcfSalesWithoutDocumentSection(
                    capabilities: caps,
                    canManage: hasUserPermission(
                      ref.watch(authStateProvider).user,
                      AppPermission.manageEcfConfig,
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

/// Interruptor de la excepción fiscal «vender sin comprobante electrónico».
///
/// Es la única puerta por la que el POS puede ofrecer la opción «Normal», y está
/// apagada por defecto. Al encenderla se muestra el aviso **completo** que envía
/// el servidor: no se resume ni se suaviza, porque es lo que la empresa está
/// aceptando. Cada venta que use la excepción queda en el registro de auditoría
/// con su motivo y su usuario.
class EcfSalesWithoutDocumentSection extends ConsumerStatefulWidget {
  const EcfSalesWithoutDocumentSection({
    super.key,
    required this.capabilities,
    required this.canManage,
    this.embedded = false,
  });

  final EcfCapabilities capabilities;

  /// Mismo permiso que exige el backend (`manageEcfConfig`).
  final bool canManage;

  /// Embebida en el panel fiscal de Empresa: no dibuja contenedor propio para
  /// no dejar una tarjeta dentro de otra. El contenido y el guardado son los
  /// mismos que en la pantalla de estado del módulo.
  final bool embedded;

  @override
  ConsumerState<EcfSalesWithoutDocumentSection> createState() =>
      _EcfSalesWithoutDocumentSectionState();
}

class _EcfSalesWithoutDocumentSectionState
    extends ConsumerState<EcfSalesWithoutDocumentSection> {
  bool _saving = false;
  String? _error;

  Future<void> _toggle(bool value) async {
    if (_saving) return;
    final confirmed = await _confirm(value);
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(ecfRepositoryProvider)
          .updateAllowSalesWithoutEcf(allow: value);
      // La verdad la tiene el servidor: se relee en lugar de asumir el cambio.
      ref.invalidate(ecfCapabilitiesProvider);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo guardar el cambio. Revisa la conexión.';
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _confirm(bool value) {
    final warning = widget.capabilities.salesWithoutEcfWarning;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          value
              ? 'Habilitar ventas sin comprobante'
              : 'Deshabilitar ventas sin comprobante',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value && warning.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.errorBorder),
                  ),
                  child: Text(
                    warning,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                const Text(
                  'El POS dejará de ofrecer la opción de registrar ventas sin '
                  'comprobante electrónico. Las ventas ya registradas con la '
                  'excepción se conservan como evidencia.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(value ? 'Entiendo y habilito' : 'Deshabilitar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.capabilities.allowSalesWithoutEcf;
    final warning = widget.capabilities.salesWithoutEcfWarning;
    final canManage = widget.canManage;

    final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle('Ventas sin comprobante electrónico'),
                    SizedBox(height: 2),
                    _Muted(
                      'Permite cerrar una venta sin emitir e-CF, solo para '
                      'operaciones que la normativa permita. Cada uso queda '
                      'registrado con su motivo y su usuario.',
                    ),
                  ],
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(top: 4, left: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Switch(value: enabled, onChanged: canManage ? _toggle : null),
            ],
          ),
          if (enabled && warning.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.errorSoft,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.errorBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 11.5, color: AppColors.error),
            ),
          ],
          if (!canManage) ...[
            const SizedBox(height: 8),
            const _Muted(
              'Solo un administrador con permiso de configuración e-CF puede '
              'cambiar esta opción.',
            ),
          ],
        ],
      );

    return widget.embedded ? content : _Panel(child: content);
  }
}
