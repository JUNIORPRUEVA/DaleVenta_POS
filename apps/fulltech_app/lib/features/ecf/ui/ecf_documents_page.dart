import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';
import '../ecf_status_presentation.dart';
import 'ecf_simulated_dispatch_action.dart';

/// Tamaño de página de la bandeja.
const int kEcfTrayPageSize = 25;

/// Bandeja de comprobantes electrónicos.
///
/// Solo lectura: muestra el estado real, el receptor, el importe y la
/// trazabilidad de cada comprobante. La única operación disponible es el
/// DESPACHO SIMULADO del detalle (perfil UAT, empresa habilitada y permiso),
/// que valida la cadena contra el proveedor simulado y nunca concede aceptación
/// fiscal.
class EcfDocumentsPage extends ConsumerStatefulWidget {
  const EcfDocumentsPage({super.key});

  @override
  ConsumerState<EcfDocumentsPage> createState() => _EcfDocumentsPageState();
}

class _EcfDocumentsPageState extends ConsumerState<EcfDocumentsPage> {
  EcfDocumentFilter _filter = EcfDocumentFilter.all;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  /// Páginas siguientes a la primera, acumuladas por "Cargar más".
  List<EcfDocumentSummary> _extra = const <EcfDocumentSummary>[];
  bool _loadingMore = false;
  String? _moreError;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetPagination() {
    _extra = const <EcfDocumentSummary>[];
    _moreError = null;
  }

  Future<void> _refresh() async {
    setState(_resetPagination);
    ref.invalidate(ecfCapabilitiesProvider);
    ref.invalidate(ecfCountersProvider);
    ref.invalidate(ecfDocumentsProvider(_filter));
  }

  void _applyGroup(EcfStatusGroup? group) {
    setState(() {
      _resetPagination();
      _filter = EcfDocumentFilter(
        group: group,
        documentType: _filter.documentType,
        search: _filter.search,
      );
    });
  }

  void _applyDocumentType(String? documentType) {
    setState(() {
      _resetPagination();
      _filter = EcfDocumentFilter(
        group: _filter.group,
        documentType: documentType,
        search: _filter.search,
      );
    });
  }

  /// La búsqueda se aplica con retardo para no consultar en cada pulsación.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() {
        _resetPagination();
        _filter = EcfDocumentFilter(
          group: _filter.group,
          documentType: _filter.documentType,
          search: value.trim().isEmpty ? null : value.trim(),
        );
      });
    });
  }

  Future<void> _loadMore(int loaded) async {
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      final page = await ref
          .read(ecfRepositoryProvider)
          .listDocumentsPage(
            filter: _filter,
            take: kEcfTrayPageSize,
            skip: loaded,
          );
      if (!mounted) return;
      setState(() {
        _extra = <EcfDocumentSummary>[..._extra, ...page.items];
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreError = 'No se pudieron cargar más comprobantes.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capabilities = ref.watch(ecfCapabilitiesProvider);
    final counters = ref.watch(ecfCountersProvider);
    final documents = ref.watch(ecfDocumentsProvider(_filter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facturación electrónica'),
        actions: [
          IconButton(
            tooltip: 'Habilitación DGII',
            onPressed: () => context.go(Routes.ecfDgii),
            icon: const Icon(Icons.verified_outlined),
          ),
          IconButton(
            tooltip: 'Configuración e-CF',
            onPressed: () => context.go(Routes.ecfConfig),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            capabilities.when(
              data: (data) => _CapabilitiesBanner(capabilities: data),
              loading: () => const _LoadingCard(),
              error: (error, _) => _ErrorCard(
                message: 'No se pudo consultar la configuración e-CF.',
                onRetry: () => ref.invalidate(ecfCapabilitiesProvider),
              ),
            ),
            const SizedBox(height: 12),
            counters.when(
              data: (data) => _CountersRow(
                counters: data,
                selected: _filter.group,
                onSelected: _applyGroup,
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            _SearchField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              onCleared: () {
                _searchController.clear();
                _onSearchChanged('');
              },
            ),
            const SizedBox(height: 8),
            _TypeFilter(
              value: _filter.documentType,
              onChanged: _applyDocumentType,
            ),
            const SizedBox(height: 12),
            documents.when(
              data: (page) {
                final items = <EcfDocumentSummary>[...page.items, ..._extra];
                return _DocumentList(
                  items: items,
                  total: page.total,
                  hasMore: page.total > items.length,
                  loadingMore: _loadingMore,
                  moreError: _moreError,
                  onLoadMore: () => _loadMore(items.length),
                  filtered: _filter != EcfDocumentFilter.all,
                  onClearFilters: () {
                    _searchController.clear();
                    _debounce?.cancel();
                    setState(() {
                      _resetPagination();
                      _filter = EcfDocumentFilter.all;
                    });
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _ErrorCard(
                message: 'No se pudieron cargar los comprobantes.',
                onRetry: () => ref.invalidate(ecfDocumentsProvider(_filter)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Los resultados del proveedor no equivalen a la aceptación de la '
              'DGII. Un comprobante observado o con resultado desconocido queda '
              'marcado para revisión humana y nunca se marca como aceptado '
              'automáticamente.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilitiesBanner extends StatelessWidget {
  const _CapabilitiesBanner({required this.capabilities});

  final EcfCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = capabilities.enabled;
    final background = enabled
        ? scheme.surfaceContainerHighest
        : scheme.errorContainer;
    final foreground = enabled ? scheme.onSurface : scheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                enabled ? Icons.verified_outlined : Icons.toggle_off_outlined,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  enabled
                      ? 'e-CF habilitado para esta empresa'
                      : 'e-CF deshabilitado',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            enabled
                ? 'Ambiente ${capabilities.environment} · certificación '
                      '${capabilities.certificationStatus}'
                : 'La facturación electrónica está apagada por defecto. '
                      'Habilítala en Configuración cuando la empresa esté lista.',
            style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
          ),
          const SizedBox(height: 4),
          Text(
            capabilities.emissionPathAvailable
                ? 'Emisión disponible desde la aplicación.'
                : 'La emisión no se realiza desde la aplicación: es un paso '
                      'operativo controlado.',
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

class _CountersRow extends StatelessWidget {
  const _CountersRow({
    required this.counters,
    required this.selected,
    required this.onSelected,
  });

  final EcfCounters counters;
  final EcfStatusGroup? selected;
  final ValueChanged<EcfStatusGroup?> onSelected;

  static const _groups = <EcfStatusGroup>[
    EcfStatusGroup.pending,
    EcfStatusGroup.requiresReview,
    EcfStatusGroup.accepted,
    EcfStatusGroup.rejected,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: Text('Todos (${counters.total})'),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final group in _groups)
          FilterChip(
            avatar: Icon(group.icon, size: 18, color: group.color(scheme)),
            label: Text('${group.label} (${counters.count(group)})'),
            selected: selected == group,
            onSelected: (value) => onSelected(value ? group : null),
          ),
      ],
    );
  }
}

class _TypeFilter extends StatelessWidget {
  const _TypeFilter({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Todos los tipos'),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (final type in const ['E31', 'E32', 'E34'])
          ChoiceChip(
            label: Text(type),
            selected: value == type,
            onSelected: (selected) => onChanged(selected ? type : null),
          ),
      ],
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList({
    required this.items,
    required this.total,
    required this.hasMore,
    required this.loadingMore,
    required this.moreError,
    required this.onLoadMore,
    required this.filtered,
    required this.onClearFilters,
  });

  final List<EcfDocumentSummary> items;
  final int total;
  final bool hasMore;
  final bool loadingMore;
  final String? moreError;
  final VoidCallback onLoadMore;
  final bool filtered;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.inbox_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              filtered
                  ? 'Ningún comprobante coincide con los filtros aplicados.'
                  : 'Todavía no hay comprobantes electrónicos.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            if (filtered) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onClearFilters,
                child: const Text('Quitar filtros'),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            items.length == total
                ? '$total comprobante${total == 1 ? '' : 's'}'
                : 'Mostrando ${items.length} de $total',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final item in items) _DocumentTile(document: item),
        if (moreError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              moreError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: onLoadMore,
                      icon: const Icon(Icons.expand_more),
                      label: Text('Cargar más (${total - items.length})'),
                    ),
            ),
          ),
      ],
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.document});

  final EcfDocumentSummary document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = presentEcfStatus(document.status);

    // En pantallas estrechas la tarjeta muestra menos metadatos: la bandeja se
    // consulta desde el móvil durante la operación del día.
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final amount = formatEcfAmount(document);
    final meta = <String>[
      if (amount != null) amount,
      if (document.createdAt != null) formatEcfDateTime(document.createdAt!),
      if (formatEcfReceiver(document) != null) formatEcfReceiver(document)!,
      if (document.originalEncf != null) 'sobre ${document.originalEncf}',
      if (document.sourceType != null) 'origen ${document.sourceType}'.trim(),
    ];
    final error = document.safeErrorMessage?.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showEcfDocumentDetailSheet(context, document.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: status.color(scheme).withValues(alpha: 0.14),
                child: Icon(status.icon, color: status.color(scheme), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            document.encf == null
                                ? '${document.documentType} · sin e-NCF'
                                : '${document.documentType} · ${document.encf}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 20),
                      ],
                    ),
                    const SizedBox(height: 6),
                    EcfStatusBadge(presentation: status),
                    const SizedBox(height: 6),
                    Text(
                      meta.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: wide ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (error != null && error.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        error,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Distintivo de estado. Usa la etiqueta exacta del estado persistido.
class EcfStatusBadge extends StatelessWidget {
  const EcfStatusBadge({super.key, required this.presentation});

  final EcfStatusPresentation presentation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = presentation.color(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(presentation.icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            presentation.label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onCleared,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar por e-NCF o número interno',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Limpiar búsqueda',
                  icon: const Icon(Icons.clear),
                  onPressed: onCleared,
                ),
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// Importe con su moneda, o `null` si el comprobante no lo tiene registrado.
String? formatEcfAmount(EcfDocumentSummary document) {
  final total = document.total;
  if (total == null || total.isEmpty) return null;
  final currency = document.currency;
  return currency == null || currency.isEmpty ? total : '$total $currency';
}

/// Receptor congelado al preparar, o `null` si no se registró.
String? formatEcfReceiver(EcfDocumentSummary document) {
  final parts = <String>[
    if (document.receiverName?.isNotEmpty == true) document.receiverName!,
    if (document.receiverTaxId?.isNotEmpty == true) document.receiverTaxId!,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

String formatEcfDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ),
        ],
      ),
    );
  }
}

/// Detalle y trazabilidad completa de un comprobante.
Future<void> showEcfDocumentDetailSheet(BuildContext context, String id) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EcfDocumentDetailSheet(documentId: id),
  );
}

class _EcfDocumentDetailSheet extends ConsumerWidget {
  const _EcfDocumentDetailSheet({required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(ecfDocumentDetailProvider(documentId));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controller) => detail.when(
        data: (data) => _DetailBody(detail: data, controller: controller),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se pudo cargar el comprobante.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail, required this.controller});

  final EcfDocumentDetail detail;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = detail.summary;
    final status = presentEcfStatus(summary.status);

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            Icon(status.icon, color: status.color(theme.colorScheme)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${summary.documentType} · ${summary.encf ?? 'sin e-NCF'}',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EcfStatusBadge(presentation: status),
        const SizedBox(height: 8),
        Text(status.description, style: theme.textTheme.bodySmall),
        const Divider(height: 32),
        _DetailRow(label: 'Estado operativo', value: status.operative.label),
        _DetailRow(label: 'Resultado fiscal', value: status.fiscal.label),
        // El valor literal se conserva a la vista para poder contrastarlo con
        // el backend, incluso si esta versión no conoce el estado.
        _DetailRow(label: 'Estado interno', value: summary.status),
        _DetailRow(label: 'Importe', value: formatEcfAmount(summary) ?? '—'),
        if (summary.createdAt != null)
          _DetailRow(
            label: 'Preparado',
            value: formatEcfDateTime(summary.createdAt!),
          ),
        _DetailRow(label: 'Receptor', value: formatEcfReceiver(summary) ?? '—'),
        _DetailRow(
          label: 'Origen',
          value: summary.sourceType == null
              ? '—'
              : '${summary.sourceType} ${summary.sourceId ?? ''}'.trim(),
        ),
        if (detail.originalDocument != null)
          _DetailRow(
            label: 'Comprobante original',
            value:
                '${detail.originalDocument!.documentType} · '
                '${detail.originalDocument!.encf ?? detail.originalDocument!.id}',
          ),
        if (detail.creditReservation != null)
          _DetailRow(
            label: 'Reserva de crédito',
            value:
                '${detail.creditReservation!.state} · '
                '${detail.creditReservation!.amount}',
          ),
        _DetailRow(
          label: 'Evidencias registradas',
          value: '${detail.evidenceReceipts}',
        ),
        if (summary.safeErrorCode != null)
          _DetailRow(
            label: 'Código seguro',
            value:
                '${summary.safeErrorCode}'
                '${summary.safeErrorMessage == null ? '' : ' · ${summary.safeErrorMessage}'}',
          ),
        const Divider(height: 32),
        Text('Historial de estados', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (detail.statusLogs.isEmpty)
          Text(
            'Sin transiciones registradas.',
            style: theme.textTheme.bodySmall,
          ),
        for (final log in detail.statusLogs)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              presentEcfStatus(log.statusAfter).icon,
              size: 20,
              color: presentEcfStatus(log.statusAfter).color(theme.colorScheme),
            ),
            title: Text(
              log.statusBefore == null
                  ? presentEcfStatus(log.statusAfter).label
                  : '${presentEcfStatus(log.statusBefore!).label} → '
                        '${presentEcfStatus(log.statusAfter).label}',
              style: theme.textTheme.bodyMedium,
            ),
            subtitle: Text(
              [
                if (log.reasonCode != null) log.reasonCode!,
                if (log.createdAt != null) _formatDate(log.createdAt!),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (detail.attempts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Intentos de operación', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final attempt in detail.attempts)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.sync_alt, size: 20),
              title: Text(attempt.operation, style: theme.textTheme.bodyMedium),
              subtitle: Text(
                [
                  if (attempt.statusAfter != null)
                    '→ ${presentEcfStatus(attempt.statusAfter!).label}',
                  if (attempt.createdAt != null)
                    _formatDate(attempt.createdAt!),
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        // Validación local: solo aparece en un perfil UAT, con la empresa
        // habilitada, con permiso y en un estado despachable.
        EcfSimulatedDispatchAction(
          documentId: detail.summary.id,
          status: summary.status,
        ),
      ],
    );
  }
}

/// Traduce un estado persistido al grupo funcional, sin reinterpretarlo.
EcfStatusGroup groupOfStatus(String status) {
  switch (status) {
    case 'DGII_ACCEPTED':
      return EcfStatusGroup.accepted;
    case 'DGII_REJECTED':
      return EcfStatusGroup.rejected;
    case 'CANCELLED':
      return EcfStatusGroup.cancelled;
    case 'UNKNOWN_RESULT':
    case 'HUMAN_REVIEW_REQUIRED':
    case 'PROVIDER_REJECTED':
      return EcfStatusGroup.requiresReview;
    default:
      return EcfStatusGroup.pending;
  }
}

String _formatDate(DateTime value) => formatEcfDateTime(value);

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
