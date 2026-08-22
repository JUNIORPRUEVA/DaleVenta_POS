import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/local_file_bytes.dart';
import '../../core/utils/media_file_actions.dart';
import '../../core/utils/simple_xlsx.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/desktop_sales_style.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/sync_status_banner.dart';

import 'application/clientes_controller.dart';
import 'cliente_form_screen.dart';
import 'cliente_model.dart';
import 'cliente_profile_model.dart';
import 'cliente_timeline_model.dart';
import 'data/clientes_repository.dart';
import '../ventas/data/ventas_repository.dart';

bool _shouldUseClientesDesktopLayout(double width) {
  if (width >= kDesktopShellBreakpoint) return true;

  final isDesktopPlatform = switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };

  return isDesktopPlatform && width >= 720;
}

double _clientesInfoColumnWidth(double width) {
  return (width * 0.33).clamp(420.0, 640.0);
}

final _clientActivityBundleProvider = FutureProvider.family
    .autoDispose<_ClientActivityBundle, String>((ref, clientId) async {
      final repo = ref.read(clientesRepositoryProvider);
      final results = await Future.wait<Object>([
        repo.getClientProfile(id: clientId),
        repo.getClientTimeline(id: clientId, take: 8),
      ]);
      return _ClientActivityBundle(
        profile: results[0] as ClienteProfileResponse,
        timeline: results[1] as ClienteTimelineResponse,
      );
    });

enum _ClientesMobileAction { summary, refresh, export, import }

class _ClientActivityBundle {
  const _ClientActivityBundle({required this.profile, required this.timeline});

  final ClienteProfileResponse profile;
  final ClienteTimelineResponse timeline;
}

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key});

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _refreshTimer;
  OverlayEntry? _noticeEntry;
  bool _importingClients = false;
  bool _searchOpen = false;
  String? _selectedClientId;

  @override
  void initState() {
    super.initState();
    // Refresco automático: la página obtiene los clientes por sí sola sin
    // necesidad de pulsar "Actualizar" manualmente.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _autoRefresh(),
    );
  }

  void _autoRefresh() {
    if (!mounted) return;
    final state = ref.read(clientesControllerProvider);
    if (!state.refreshing) {
      ref.read(clientesControllerProvider.notifier).refresh();
    }
  }

  Future<void> _openFilters(ClientesState state) async {
    final initialState = _ClientesFilterState(
      order: state.order,
      correoFilter: state.correoFilter,
      estadoFilter: state.estadoFilter,
      ownerFilter: state.ownerFilter,
    );

    // El filtro se abre como columna fija a la derecha a todo el alto
    // (mismo patrón que el historial de movimientos).
    final next = await showGeneralDialog<_ClientesFilterState>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros de clientes',
      barrierColor: Colors.black.withValues(alpha: 0.26),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: _ClientesFiltersSheet(initialState: initialState),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

    if (next == null || !mounted) return;

    await ref
        .read(clientesControllerProvider.notifier)
        .applyFilters(
          order: next.order,
          correoFilter: next.correoFilter,
          estadoFilter: next.estadoFilter,
          ownerFilter: OwnerFilter.todos,
        );
  }

  @override
  void dispose() {
    _noticeEntry?.remove();
    _noticeEntry = null;
    _refreshTimer?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(clientesControllerProvider.notifier).load(search: value);
    });
  }

  ClienteModel? _resolveSelectedClient(List<ClienteModel> items) {
    if (items.isEmpty) return null;
    final selectedId = (_selectedClientId ?? '').trim();
    if (selectedId.isNotEmpty) {
      for (final client in items) {
        if (client.id == selectedId) return client;
      }
    }
    return items.first;
  }

  Future<void> _showSummary(ClientesState state) async {
    final items = state.items;
    final totalClients = items.length;
    final activeClients = items.where((c) => !c.isDeleted).length;
    final deletedClients = items.where((c) => c.isDeleted).length;
    final withPhone = items.where((c) => c.telefono.trim().isNotEmpty).length;
    final withAddress = items
        .where((c) => (c.direccion ?? '').trim().isNotEmpty)
        .length;

    final totalPurchasedFuture = _loadTotalPurchased();

    if (!mounted) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Resumen de clientes',
      barrierColor: Colors.black.withValues(alpha: 0.32),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _ClientesSummaryDialog(
          totalClients: totalClients,
          activeClients: activeClients,
          deletedClients: deletedClients,
          withPhone: withPhone,
          withAddress: withAddress,
          totalPurchasedFuture: totalPurchasedFuture,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<double> _loadTotalPurchased() async {
    try {
      final now = DateTime.now();
      final sales = await ref
          .read(ventasRepositoryProvider)
          .listInvoices(
            from: DateTime(now.year - 5, now.month, now.day),
            to: now,
            includeDeleted: true,
          );
      return sales.fold<double>(0.0, (sum, sale) => sum + sale.totalSold);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _openCreateClientFlow() async {
    final created = await openClienteFormAdaptive(context);
    if (created == null || !mounted) return;
    setState(() {
      _selectedClientId = created.id;
    });
    await ref.read(clientesControllerProvider.notifier).refresh();
    _showClientNotice('Cliente creado', created.nombre);
  }

  Future<void> _openEditClientFlow(ClienteModel client) async {
    final updated = await openClienteFormAdaptive(
      context,
      clienteId: client.id,
      returnSavedClient: true,
    );
    if (updated == null || !mounted) return;
    setState(() {
      _selectedClientId = updated.id;
    });
    await ref.read(clientesControllerProvider.notifier).refresh();
    _showClientNotice('Cliente actualizado', updated.nombre);
  }

  void _showClientNotice(String title, String message, {bool isError = false}) {
    _noticeEntry?.remove();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('$title. $message')));
      return;
    }

    _noticeEntry = OverlayEntry(
      builder: (context) {
        final top = MediaQuery.paddingOf(context).top + 18;
        return Positioned(
          top: top,
          right: 18,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 360,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isError
                      ? const Color(0xFFFCA5A5)
                      : const Color(0xFFCFE0FF),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isError
                          ? const Color(0xFFFEE2E2)
                          : desktopSalesAccentSoft,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isError
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      color: isError
                          ? const Color(0xFFDC2626)
                          : desktopSalesAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12.5,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    final entry = _noticeEntry!;
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 4), () {
      if (_noticeEntry == entry) {
        _noticeEntry?.remove();
        _noticeEntry = null;
      }
    });
  }

  Future<void> _exportClients() async {
    final clients = ref
        .read(clientesControllerProvider)
        .items
        .where((client) => !client.isDeleted)
        .toList(growable: false);
    if (clients.isEmpty) {
      _showClientNotice(
        'Sin clientes activos',
        'No hay clientes disponibles para exportar.',
      );
      return;
    }

    try {
      final bytes = buildSimpleXlsx([
        SimpleXlsxSheet(
          name: 'Clientes',
          rows: [
            const [
              'Nombre',
              'Teléfono',
              'Correo',
              'Dirección',
              'Ubicación GPS',
            ],
            for (final client in clients)
              [
                client.nombre,
                client.telefono,
                client.correo ?? '',
                client.direccion ?? '',
                client.locationUrl ?? '',
              ],
          ],
        ),
      ]);
      final saved = await saveMediaBytes(
        bytes: bytes,
        fileName: 'clientes_${_clientFileStamp()}.xlsx',
        allowedExtensions: const ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      _showClientNotice(
        saved ? 'Clientes exportados' : 'Exportación cancelada',
        saved
            ? 'Se preparó el archivo con ${clients.length} clientes activos.'
            : 'No se guardó ningún archivo.',
      );
    } catch (error) {
      if (!mounted) return;
      _showClientNotice('No se pudo exportar', '$error', isError: true);
    }
  }

  Future<void> _importClients() async {
    if (_importingClients) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || !mounted) return;

    setState(() => _importingClients = true);
    try {
      final bytes = await _readPickedFileBytes(file);
      if (bytes == null) {
        throw Exception('No se pudo leer el archivo seleccionado.');
      }
      final drafts = _parseClientImportFile(bytes, file.name);
      if (drafts.isEmpty) {
        throw Exception(
          'El archivo no tiene clientes válidos. Nombre y teléfono son obligatorios.',
        );
      }

      var imported = 0;
      var skipped = 0;
      final controller = ref.read(clientesControllerProvider.notifier);
      for (final draft in drafts) {
        try {
          await controller.saveCliente(
            nombre: draft.nombre,
            telefono: draft.telefono,
            correo: draft.correo,
            direccion: draft.direccion,
            locationUrl: draft.locationUrl,
          );
          imported++;
        } catch (_) {
          skipped++;
        }
      }
      await controller.refresh();
      if (!mounted) return;
      _showClientNotice(
        'Importación completada',
        skipped == 0
            ? 'Se importaron $imported clientes en esta empresa.'
            : 'Se importaron $imported clientes y se omitieron $skipped registros.',
      );
    } catch (error) {
      if (!mounted) return;
      _showClientNotice('No se pudo importar', '$error', isError: true);
    } finally {
      if (mounted) setState(() => _importingClients = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;
    final state = ref.watch(clientesControllerProvider);
    final controller = ref.read(clientesControllerProvider.notifier);
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = _shouldUseClientesDesktopLayout(width);
    final selectedClient = _resolveSelectedClient(state.items);
    final activeFilterCount = [
      state.order != ClientesOrder.az,
      state.correoFilter != CorreoFilter.todos,
      state.estadoFilter != EstadoFilter.activos,
      state.ownerFilter != OwnerFilter.todos,
    ].where((active) => active).length;

    return Scaffold(
      backgroundColor: isDesktop ? desktopSalesSurface : AppColors.background,
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      floatingActionButton: !isDesktop
          ? FloatingActionButton(
              onPressed: _openCreateClientFlow,
              tooltip: 'Nuevo cliente',
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,

      appBar: isDesktop
          ? FullTechPageHeader(
              title: 'Clientes',
              actions: [
                _ClientesHeaderActionButton(
                  icon: Icons.person_add_alt_1_rounded,
                  label: 'Nuevo cliente',
                  onPressed: _openCreateClientFlow,
                  prominent: true,
                ),
                const SizedBox(width: 8),
                _ClientesHeaderActionButton(
                  icon: Icons.download_rounded,
                  label: 'Exportar',
                  onPressed: _exportClients,
                ),
                const SizedBox(width: 8),
                _ClientesHeaderActionButton(
                  icon: Icons.upload_file_rounded,
                  label: _importingClients ? 'Importando' : 'Importar',
                  onPressed: _importingClients ? null : _importClients,
                ),
                const SizedBox(width: 8),
                _ClientesHeaderActionButton(
                  icon: Icons.refresh_rounded,
                  label: state.refreshing ? 'Actualizando' : 'Actualizar',
                  onPressed: state.refreshing ? null : controller.refresh,
                ),
                const SizedBox(width: 12),
              ],
            )
          : CustomAppBar(
              title: 'Clientes',
              titleWidget: _searchOpen ? _buildAppBarSearchField() : null,
              actions: [
                IconButton(
                  tooltip: _searchOpen ? 'Cerrar búsqueda' : 'Buscar',
                  onPressed: () => setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _searchCtrl.clear();
                  }),
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                if (!_searchOpen) ...[
                  IconButton(
                    tooltip: 'Filtros',
                    onPressed: () => _openFilters(state),
                    icon: Badge(
                      isLabelVisible: activeFilterCount > 0,
                      label: Text('$activeFilterCount'),
                      child: const Icon(Icons.filter_alt_outlined),
                    ),
                  ),
                  PopupMenuButton<_ClientesMobileAction>(
                    tooltip: 'Más opciones',
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      switch (action) {
                        case _ClientesMobileAction.summary:
                          _showSummary(state);
                          return;
                        case _ClientesMobileAction.refresh:
                          if (!state.refreshing) controller.refresh();
                          return;
                        case _ClientesMobileAction.export:
                          _exportClients();
                          return;
                        case _ClientesMobileAction.import:
                          if (!_importingClients) _importClients();
                          return;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: _ClientesMobileAction.summary,
                        child: _ClientesMobileMenuEntry(
                          icon: Icons.summarize_outlined,
                          label: 'Resumen',
                        ),
                      ),
                      PopupMenuItem(
                        value: _ClientesMobileAction.refresh,
                        enabled: !state.refreshing,
                        child: _ClientesMobileMenuEntry(
                          icon: Icons.refresh_rounded,
                          label: state.refreshing
                              ? 'Actualizando'
                              : 'Actualizar',
                        ),
                      ),
                      const PopupMenuItem(
                        value: _ClientesMobileAction.export,
                        child: _ClientesMobileMenuEntry(
                          icon: Icons.download_rounded,
                          label: 'Exportar clientes',
                        ),
                      ),
                      PopupMenuItem(
                        value: _ClientesMobileAction.import,
                        enabled: !_importingClients,
                        child: _ClientesMobileMenuEntry(
                          icon: Icons.upload_file_rounded,
                          label: _importingClients
                              ? 'Importando'
                              : 'Importar clientes',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              trailing: const SizedBox.shrink(),
              showLogo: false,
              showDepartmentLabel: false,
            ),
      body: SafeArea(
        bottom: false,
        child: isDesktop
            ? DesktopSalesFrame(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _buildClientesMainColumn(
                          state: state,
                          controller: controller,
                          theme: theme,
                          activeFilterCount: activeFilterCount,
                          desktopLayout: true,
                          selectedClient: selectedClient,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: _clientesInfoColumnWidth(width),
                      child: _ClienteFixedInfoColumn(
                        client: selectedClient,
                        totalClients: state.items.length,
                        refreshing: state.refreshing,
                        onNewClient: _openCreateClientFlow,
                      ),
                    ),
                  ],
                ),
              )
            : _buildClientesMainColumn(
                state: state,
                controller: controller,
                theme: theme,
                activeFilterCount: activeFilterCount,
                desktopLayout: false,
                selectedClient: selectedClient,
              ),
      ),
    );
  }

  Widget _buildAppBarSearchField() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: const TextStyle(color: Color(0xFF111827)),
          textInputAction: TextInputAction.search,
          onChanged: _handleSearch,
          decoration: InputDecoration(
            hintText: 'Buscar clientes',
            hintStyle: const TextStyle(color: Color(0xFF8A9AA8)),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide.none,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF8A9AA8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClientesMainColumn({
    required ClientesState state,
    required ClientesController controller,
    required ThemeData theme,
    required int activeFilterCount,
    required bool desktopLayout,
    required ClienteModel? selectedClient,
  }) {
    return Column(
      children: [
        if (desktopLayout)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: _ClientesTopPanel(
              searchController: _searchCtrl,
              activeFilterCount: activeFilterCount,
              onSearchChanged: _handleSearch,
              onOpenFilters: () => _openFilters(state),
            ),
          ),
        SyncStatusBanner(
          visible: state.refreshing,
          label: 'Sincronizando clientes...',
        ),

        if (state.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Material(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: state.items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('No hay clientes disponibles.')),
                          ],
                        )
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            desktopLayout ? 14 : 14,
                            desktopLayout ? 4 : 8,
                            desktopLayout ? 14 : 14,
                            24,
                          ),
                          itemCount: state.items.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: desktopLayout ? 0.48 : 0.35,
                            ),
                          ),
                          itemBuilder: (context, index) {
                            final client = state.items[index];
                            return _ClienteCard(
                              client: client,
                              compact: desktopLayout,
                              selected:
                                  desktopLayout &&
                                  selectedClient?.id == client.id,
                              onTap: desktopLayout
                                  ? () => setState(() {
                                      _selectedClientId = client.id;
                                    })
                                  : () => context.push(
                                      Routes.clienteDetail(client.id),
                                    ),
                              onEdit: () => _openEditClientFlow(client),
                            );
                          },
                        ),
                ),
              ),
              if (state.loading)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ClienteCard extends ConsumerWidget {
  const _ClienteCard({
    required this.client,
    this.compact = false,
    this.selected = false,
    this.onTap,
    this.onEdit,
  });

  final ClienteModel client;
  final bool compact;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final phone = client.telefono.trim();
    final createdAt = client.createdAt == null
        ? null
        : _formatClientDate(client.createdAt!);

    if (compact) {
      return Material(
        color: selected
            ? colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: colorScheme.primary.withValues(alpha: 0.05),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? colorScheme.primary : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    client.nombre.trim().isEmpty
                        ? 'Cliente sin nombre'
                        : client.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                      letterSpacing: -0.08,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: Text(
                    phone.isEmpty ? 'Sin teléfono' : phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 86,
                  child: Text(
                    createdAt ?? 'Sin fecha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (onEdit != null) ...[
                  const SizedBox(width: 6),
                  _ClientRowEditButton(
                    onPressed: onEdit!,
                    tooltip: 'Editar cliente',
                  ),
                ],
                if (client.isDeleted) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Eliminado',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => context.push(Routes.clienteDetail(client.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            client.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              height: 1.05,
                            ),
                          ),
                        ),
                        if (client.isDeleted)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              'Eliminado',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            phone.isEmpty ? 'Sin telefono' : phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (createdAt != null)
                          Text(
                            createdAt,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (onEdit != null) ...[
                _ClientRowEditButton(
                  onPressed: onEdit!,
                  tooltip: 'Editar cliente',
                ),
                const SizedBox(width: 4),
              ],
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientRowEditButton extends StatelessWidget {
  const _ClientRowEditButton({
    required this.onPressed,
    required this.tooltip,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.edit_outlined, size: 15),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      color: const Color(0xFF1957E6),
    );
  }
}

class _ClientesMobileMenuEntry extends StatelessWidget {
  const _ClientesMobileMenuEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF2563EB)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _ClienteFixedInfoColumn extends ConsumerWidget {
  const _ClienteFixedInfoColumn({
    required this.client,
    required this.totalClients,
    required this.refreshing,
    required this.onNewClient,
  });

  final ClienteModel? client;
  final int totalClients;
  final bool refreshing;
  final VoidCallback onNewClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = client;
    final activity = selected == null
        ? null
        : ref.watch(_clientActivityBundleProvider(selected.id));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: desktopSalesPanel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: desktopSalesAccentSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFB8CAFF)),
                    boxShadow: [
                      BoxShadow(
                        color: desktopSalesAccent.withValues(alpha: 0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_search_rounded,
                    color: desktopSalesAccent,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cliente seleccionado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        refreshing
                            ? 'Sincronizando · $totalClients clientes'
                            : '$totalClients clientes visibles',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.44),
          ),
          Expanded(
            child: selected == null
                ? _ClienteInfoEmptyState(onNewClient: onNewClient)
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected.nombre.trim().isEmpty
                              ? 'Cliente sin nombre'
                              : selected.nombre.trim(),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _ClientStatusDot(
                              label: selected.isDeleted
                                  ? 'Eliminado'
                                  : 'Activo',
                              color: selected.isDeleted
                                  ? colorScheme.error
                                  : const Color(0xFF059669),
                            ),
                            if (selected.updatedLocal) ...[
                              const SizedBox(width: 8),
                              _ClientStatusDot(
                                label: 'Local',
                                color: colorScheme.primary,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 28),
                        _ClientInfoLine(
                          icon: Icons.call_outlined,
                          label: 'Teléfono',
                          value: selected.telefono.trim().isEmpty
                              ? 'Sin teléfono'
                              : selected.telefono.trim(),
                        ),
                        if ((selected.taxId ?? '').trim().isNotEmpty)
                          _ClientInfoLine(
                            icon: Icons.badge_outlined,
                            label: 'RNC / Cédula',
                            value: selected.taxId!.trim(),
                          ),
                        if ((selected.direccion ?? '').trim().isNotEmpty)
                          _ClientInfoLine(
                            icon: Icons.place_outlined,
                            label: 'Dirección',
                            value: selected.direccion!.trim(),
                            maxLines: 3,
                          ),
                        _ClientInfoLine(
                          icon: Icons.calendar_today_outlined,
                          label: 'Creado',
                          value: selected.createdAt == null
                              ? 'Sin fecha'
                              : _formatClientDate(selected.createdAt!),
                        ),
                        _ClientInfoLine(
                          icon: Icons.update_rounded,
                          label: 'Actualizado',
                          value: selected.updatedAt == null
                              ? 'Sin fecha'
                              : _formatClientDate(selected.updatedAt!),
                        ),
                        const SizedBox(height: 4),
                        _ClientActivitySection(activity: activity),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ClienteInfoEmptyState extends StatelessWidget {
  const _ClienteInfoEmptyState({required this.onNewClient});

  final VoidCallback onNewClient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_off_outlined,
              size: 36,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Selecciona un cliente',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'La información aparecerá fija en esta columna.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onNewClient,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Nuevo cliente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientActivitySection extends StatelessWidget {
  const _ClientActivitySection({required this.activity});

  final AsyncValue<_ClientActivityBundle>? activity;

  @override
  Widget build(BuildContext context) {
    final value = activity;
    if (value == null) return const SizedBox.shrink();

    return value.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: 10),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (error, stackTrace) => _ClientActivityMessage(
        icon: Icons.info_outline_rounded,
        title: 'Actividad no disponible',
        message: 'No se pudo cargar el resumen del cliente.',
      ),
      data: (bundle) {
        final metrics = bundle.profile.metrics;
        final timeline = bundle.timeline.items;
        final creditCount = metrics.creditSalesCount;
        final creditBalance = metrics.creditBalanceTotal ?? 0;
        final lastItems = timeline.take(5).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClientSectionTitle(
              icon: Icons.insights_rounded,
              label: 'Resumen de actividad',
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.35,
              children: [
                _ClientMetricTile(
                  label: 'Compras',
                  value: '${metrics.salesCount}',
                  helper: 'facturas',
                  icon: Icons.receipt_long_outlined,
                ),
                _ClientMetricTile(
                  label: 'Total comprado',
                  value: formatRdCurrencyAccounting(
                    (metrics.salesTotal ?? 0).toDouble(),
                  ),
                  helper: 'acumulado',
                  icon: Icons.payments_outlined,
                ),
                _ClientMetricTile(
                  label: 'Cotizaciones',
                  value: '${metrics.cotizacionesCount}',
                  helper: formatRdCurrencyAccounting(
                    (metrics.cotizacionesTotal ?? 0).toDouble(),
                  ),
                  icon: Icons.request_quote_outlined,
                ),
                _ClientMetricTile(
                  label: 'Créditos',
                  value: '$creditCount',
                  helper: creditBalance > 0
                      ? '${formatRdCurrencyAccounting(creditBalance.toDouble())} pendiente'
                      : 'sin saldo pendiente',
                  icon: Icons.credit_score_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ClientSectionTitle(
              icon: Icons.history_rounded,
              label: 'Últimos movimientos',
            ),
            const SizedBox(height: 10),
            if (lastItems.isEmpty)
              const _ClientActivityMessage(
                icon: Icons.history_toggle_off_rounded,
                title: 'Sin actividad registrada',
                message:
                    'Este cliente todavía no tiene facturas ni cotizaciones.',
              )
            else
              for (final event in lastItems)
                _ClientTimelineMiniRow(event: event),
          ],
        );
      },
    );
  }
}

class _ClientSectionTitle extends StatelessWidget {
  const _ClientSectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: desktopSalesAccent),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _ClientMetricTile extends StatelessWidget {
  const _ClientMetricTile({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD8E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: desktopSalesAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: desktopSalesMuted,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            helper,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: desktopSalesMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientTimelineMiniRow extends StatelessWidget {
  const _ClientTimelineMiniRow({required this.event});

  final ClienteTimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final amount = event.amount;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E5EC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: desktopSalesAccentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _clientEventIcon(event),
              size: 17,
              color: desktopSalesAccent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _clientEventTitle(event),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    _formatClientDate(event.at),
                    if ((event.status ?? '').trim().isNotEmpty)
                      event.status!.trim(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: desktopSalesMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (amount != null)
            Text(
              formatRdCurrencyAccounting(amount.toDouble()),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: desktopSalesAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _ClientActivityMessage extends StatelessWidget {
  const _ClientActivityMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E5EC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: desktopSalesMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: desktopSalesMuted,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _clientEventLooksLikeCredit(ClienteTimelineEvent event) {
  final haystack = '${event.eventType} ${event.title} ${event.status ?? ''}'
      .toLowerCase();
  return haystack.contains('credit') ||
      haystack.contains('credito') ||
      haystack.contains('crédito');
}

IconData _clientEventIcon(ClienteTimelineEvent event) {
  final type = event.eventType.toLowerCase();
  if (type.contains('cotizacion') || type.contains('quote')) {
    return Icons.request_quote_outlined;
  }
  if (_clientEventLooksLikeCredit(event)) return Icons.credit_score_outlined;
  if (type.contains('service')) return Icons.handyman_outlined;
  return Icons.receipt_long_outlined;
}

String _clientEventTitle(ClienteTimelineEvent event) {
  final title = event.title.trim();
  if (title.isNotEmpty) return title;
  final type = event.eventType.toLowerCase();
  if (type.contains('cotizacion') || type.contains('quote')) {
    return 'Cotización';
  }
  if (_clientEventLooksLikeCredit(event)) return 'Crédito';
  if (type.contains('service')) return 'Servicio';
  return 'Factura';
}

class _ClientInfoLine extends StatelessWidget {
  const _ClientInfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: desktopSalesAccentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCFE0FF)),
            ),
            child: Icon(icon, size: 19, color: desktopSalesAccent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.18,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.16,
                    letterSpacing: -0.08,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientStatusDot extends StatelessWidget {
  const _ClientStatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ClientesHeaderActionButton extends StatelessWidget {
  const _ClientesHeaderActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final style = prominent
        ? FilledButton.styleFrom(
            backgroundColor: desktopSalesAccent,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          )
        : OutlinedButton.styleFrom(
            foregroundColor: desktopSalesAccent,
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFCFE0FF)),
            minimumSize: const Size(0, 42),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
      ],
    );
    return prominent
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _ClientesTopPanel extends StatelessWidget {
  const _ClientesTopPanel({
    required this.searchController,
    required this.activeFilterCount,
    required this.onSearchChanged,
    required this.onOpenFilters,
  });

  final TextEditingController searchController;
  final int activeFilterCount;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: desktopSalesInputDecoration(
              hintText: 'Buscar clientes',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SearchFilterButton(
          tooltip: 'Filtros',
          badgeCount: activeFilterCount,
          onPressed: onOpenFilters,
        ),
      ],
    );
  }
}

String _formatClientDate(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

class _SearchFilterButton extends StatelessWidget {
  const _SearchFilterButton({
    required this.tooltip,
    required this.onPressed,
    this.badgeCount = 0,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final hasFilters = badgeCount > 0;
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: hasFilters,
          label: Text('$badgeCount'),
          child: const Icon(Icons.tune_rounded, size: 20),
        ),
        label: const Text('Filtro'),
        style: OutlinedButton.styleFrom(
          foregroundColor: hasFilters
              ? AppColors.secondary
              : AppColors.textPrimary,
          backgroundColor: hasFilters ? const Color(0xFFEAF1FF) : Colors.white,
          side: const BorderSide(color: AppColors.border),
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _ClientesFilterState {
  const _ClientesFilterState({
    required this.order,
    required this.correoFilter,
    required this.estadoFilter,
    required this.ownerFilter,
  });

  final ClientesOrder order;
  final CorreoFilter correoFilter;
  final EstadoFilter estadoFilter;
  final OwnerFilter ownerFilter;

  _ClientesFilterState copyWith({
    ClientesOrder? order,
    CorreoFilter? correoFilter,
    EstadoFilter? estadoFilter,
    OwnerFilter? ownerFilter,
  }) {
    return _ClientesFilterState(
      order: order ?? this.order,
      correoFilter: correoFilter ?? this.correoFilter,
      estadoFilter: estadoFilter ?? this.estadoFilter,
      ownerFilter: ownerFilter ?? this.ownerFilter,
    );
  }
}

class _ClientesFiltersSheet extends StatefulWidget {
  const _ClientesFiltersSheet({required this.initialState});

  final _ClientesFilterState initialState;

  @override
  State<_ClientesFiltersSheet> createState() => _ClientesFiltersSheetState();
}

class _ClientesFiltersSheetState extends State<_ClientesFiltersSheet> {
  late _ClientesFilterState _draft = widget.initialState;

  void _apply() {
    Navigator.of(context).pop(_draft);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = (media.width * 0.6).clamp(300.0, 430.0);

    return Dismissible(
      key: const ValueKey('clientes-filter-panel'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => Navigator.of(context).pop(),
      child: Material(
        color: Colors.white,
        elevation: 18,
        borderRadius: BorderRadius.zero,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: media.height,
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.filter_alt_rounded,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filtros de clientes',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Orden y estado',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    children: [
                      _FilterSection<ClientesOrder>(
                        title: 'Orden',
                        value: _draft.order,
                        options: const [ClientesOrder.az, ClientesOrder.za],
                        labelBuilder: _clientesOrderLabel,
                        onSelected: (value) {
                          setState(
                            () => _draft = _draft.copyWith(order: value),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _FilterSection<EstadoFilter>(
                        title: 'Estado',
                        value: _draft.estadoFilter,
                        options: const [
                          EstadoFilter.activos,
                          EstadoFilter.eliminados,
                          EstadoFilter.todos,
                        ],
                        labelBuilder: _estadoFilterLabel,
                        onSelected: (value) {
                          setState(
                            () => _draft = _draft.copyWith(estadoFilter: value),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceAlt,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop(
                              const _ClientesFilterState(
                                order: ClientesOrder.az,
                                correoFilter: CorreoFilter.todos,
                                estadoFilter: EstadoFilter.activos,
                                ownerFilter: OwnerFilter.todos,
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: const Text('Limpiar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _apply,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Aplicar'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSection<T> extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.value,
    required this.options,
    required this.labelBuilder,
    required this.onSelected,
  });

  final String title;
  final T value;
  final List<T> options;
  final String Function(T value) labelBuilder;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: [
            for (var index = 0; index < options.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              Material(
                color: optionEquals(options[index], value)
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.25,
                      ),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onSelected(options[index]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          optionEquals(options[index], value)
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 18,
                          color: optionEquals(options[index], value)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            labelBuilder(options[index]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: optionEquals(options[index], value)
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  bool optionEquals(T left, T right) => left == right;
}

String _clientesOrderLabel(ClientesOrder order) {
  switch (order) {
    case ClientesOrder.az:
      return 'Nombre A-Z';
    case ClientesOrder.za:
      return 'Nombre Z-A';
  }
}

String _estadoFilterLabel(EstadoFilter filter) {
  switch (filter) {
    case EstadoFilter.activos:
      return 'Activos';
    case EstadoFilter.eliminados:
      return 'Eliminados';
    case EstadoFilter.todos:
      return 'Todos';
  }
}

String _clientFileStamp() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
}

Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
  final memoryBytes = file.bytes;
  if (memoryBytes != null) return Uint8List.fromList(memoryBytes);
  final path = (file.path ?? '').trim();
  if (path.isEmpty) return null;
  return Uint8List.fromList(await readLocalFileBytes(path));
}

List<_ClientImportDraft> _parseClientImportFile(
  Uint8List bytes,
  String fileName,
) {
  final lowerName = fileName.toLowerCase().trim();
  final rows = lowerName.endsWith('.xlsx')
      ? _readFirstXlsxSheet(bytes)
      : _parseClientCsv(utf8.decode(bytes, allowMalformed: true));
  return _clientDraftsFromRows(rows);
}

List<List<String>> _readFirstXlsxSheet(Uint8List bytes) {
  final sheets = readSimpleXlsx(bytes);
  for (final rows in sheets.values) {
    if (rows.isNotEmpty) return rows;
  }
  return const [];
}

List<List<String>> _parseClientCsv(String text) {
  return const LineSplitter()
      .convert(text)
      .where((line) => line.trim().isNotEmpty)
      .map(_splitCsvLine)
      .toList(growable: false);
}

List<String> _splitCsvLine(String line) {
  final result = <String>[];
  final current = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      final escapedQuote = quoted && i + 1 < line.length && line[i + 1] == '"';
      if (escapedQuote) {
        current.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
      continue;
    }
    if (!quoted && (char == ',' || char == ';' || char == '\t')) {
      result.add(current.toString().trim());
      current.clear();
      continue;
    }
    current.write(char);
  }
  result.add(current.toString().trim());
  return result;
}

List<_ClientImportDraft> _clientDraftsFromRows(List<List<String>> rows) {
  final cleanRows = rows
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .toList(growable: false);
  if (cleanRows.isEmpty) return const [];

  final first = cleanRows.first;
  final hasHeader = _looksLikeClientHeader(first);
  final header = hasHeader ? first : const <String>[];
  final dataRows = hasHeader ? cleanRows.skip(1) : cleanRows;
  final nameIndex = hasHeader
      ? _headerIndex(header, const ['nombre', 'cliente', 'name', 'customer'])
      : 0;
  final phoneIndex = hasHeader
      ? _headerIndex(header, const [
          'telefono',
          'teléfono',
          'phone',
          'celular',
          'whatsapp',
        ])
      : 1;
  final emailIndex = hasHeader
      ? _headerIndex(header, const ['correo', 'email', 'mail'])
      : 2;
  final addressIndex = hasHeader
      ? _headerIndex(header, const ['direccion', 'dirección', 'address'])
      : 3;
  final locationIndex = hasHeader
      ? _headerIndex(header, const [
          'ubicacion',
          'ubicación',
          'gps',
          'location',
          'mapa',
        ])
      : 4;

  final drafts = <_ClientImportDraft>[];
  for (final row in dataRows) {
    final name = _rowCell(row, nameIndex);
    final phone = _rowCell(row, phoneIndex);
    if (name.isEmpty || phone.isEmpty) continue;
    drafts.add(
      _ClientImportDraft(
        nombre: name,
        telefono: phone,
        correo: _emptyToNull(_rowCell(row, emailIndex)),
        direccion: _emptyToNull(_rowCell(row, addressIndex)),
        locationUrl: _emptyToNull(_rowCell(row, locationIndex)),
      ),
    );
  }
  return drafts;
}

bool _looksLikeClientHeader(List<String> row) {
  return row
      .map(_normalizeClientHeader)
      .any(
        (cell) => cell == 'nombre' || cell == 'cliente' || cell == 'telefono',
      );
}

int _headerIndex(List<String> headers, List<String> aliases) {
  final normalizedAliases = aliases.map(_normalizeClientHeader).toSet();
  for (var i = 0; i < headers.length; i++) {
    if (normalizedAliases.contains(_normalizeClientHeader(headers[i]))) {
      return i;
    }
  }
  return -1;
}

String _normalizeClientHeader(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String _rowCell(List<String> row, int index) {
  if (index < 0 || index >= row.length) return '';
  return row[index].trim();
}

String? _emptyToNull(String value) =>
    value.trim().isEmpty ? null : value.trim();

class _ClientImportDraft {
  const _ClientImportDraft({
    required this.nombre,
    required this.telefono,
    this.correo,
    this.direccion,
    this.locationUrl,
  });

  final String nombre;
  final String telefono;
  final String? correo;
  final String? direccion;
  final String? locationUrl;
}

class _ClientesSummaryDialog extends StatelessWidget {
  const _ClientesSummaryDialog({
    required this.totalClients,
    required this.activeClients,
    required this.deletedClients,
    required this.withPhone,
    required this.withAddress,
    required this.totalPurchasedFuture,
  });

  final int totalClients;
  final int activeClients;
  final int deletedClients;
  final int withPhone;
  final int withAddress;
  final Future<double> totalPurchasedFuture;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final compact = media.width < 720;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 28,
        vertical: 24,
      ),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.summarize_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Resumen de clientes',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Información general de la lista',
                          style: TextStyle(
                            color: Color(0xFFDCEBFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                children: [
                  _ClientesSummaryMetric(
                    icon: Icons.people_outline_rounded,
                    label: 'Total de clientes',
                    value: '$totalClients',
                    accent: AppColors.secondary,
                  ),
                  FutureBuilder<double>(
                    future: totalPurchasedFuture,
                    builder: (context, snapshot) {
                      final value = snapshot.hasData ? snapshot.data! : 0.0;
                      return _ClientesSummaryMetric(
                        icon: Icons.payments_outlined,
                        label: 'Monto total comprado',
                        value:
                            snapshot.connectionState == ConnectionState.waiting
                            ? 'Calculando...'
                            : formatRdCurrencyAccounting(value),
                        accent: const Color(0xFF059669),
                      );
                    },
                  ),
                  _ClientesSummaryMetric(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Clientes activos',
                    value: '$activeClients',
                    accent: const Color(0xFF15803D),
                  ),
                  _ClientesSummaryMetric(
                    icon: Icons.delete_outline_rounded,
                    label: 'Clientes eliminados',
                    value: '$deletedClients',
                    accent: const Color(0xFFB45309),
                  ),
                  _ClientesSummaryMetric(
                    icon: Icons.phone_outlined,
                    label: 'Con teléfono',
                    value: '$withPhone',
                    accent: const Color(0xFF7C3AED),
                  ),
                  _ClientesSummaryMetric(
                    icon: Icons.place_outlined,
                    label: 'Con dirección',
                    value: '$withAddress',
                    accent: const Color(0xFFDB2777),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Entendido'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientesSummaryMetric extends StatelessWidget {
  const _ClientesSummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
