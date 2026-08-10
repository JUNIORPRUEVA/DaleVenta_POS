import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/desktop_sales_style.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/sync_status_banner.dart';

import 'application/clientes_controller.dart';
import 'cliente_form_screen.dart';
import 'cliente_model.dart';
import 'data/clientes_repository.dart';
import '../service_orders/service_order_models.dart';
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

class ClientesScreen extends ConsumerStatefulWidget {
  const ClientesScreen({super.key});

  @override
  ConsumerState<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends ConsumerState<ClientesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  Timer? _refreshTimer;
  bool _purgingAllDebug = false;
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

  Future<void> _purgeAllDebug() async {
    final confirmed = await confirmDebugAdminPurge(
      context,
      moduleLabel: 'clientes',
      impactLabel: 'todos los clientes y sus datos relacionados',
    );
    if (!confirmed || !mounted) return;

    setState(() => _purgingAllDebug = true);
    try {
      final deleted = await ref
          .read(clientesControllerProvider.notifier)
          .purgeAllDebug();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Se limpiaron $deleted clientes.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        setState(() => _purgingAllDebug = false);
      }
    }
  }

  Future<void> _showSummary(ClientesState state) async {
    final items = state.items;
    final totalClients = items.length;
    final activeClients = items.where((c) => !c.isDeleted).length;
    final deletedClients = items.where((c) => c.isDeleted).length;
    final withEmail = items
        .where((c) => (c.correo ?? '').trim().isNotEmpty)
        .length;
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
          withEmail: withEmail,
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
  }

  Future<void> _handleTopAction(_ClientesTopAction action) async {
    switch (action) {
      case _ClientesTopAction.newClient:
        await _openCreateClientFlow();
        break;
      case _ClientesTopAction.refresh:
        final state = ref.read(clientesControllerProvider);
        if (!state.refreshing) {
          await ref.read(clientesControllerProvider.notifier).refresh();
        }
        break;
      case _ClientesTopAction.clearFilters:
        await ref
            .read(clientesControllerProvider.notifier)
            .applyFilters(
              order: ClientesOrder.az,
              correoFilter: CorreoFilter.todos,
              estadoFilter: EstadoFilter.todos,
              ownerFilter: OwnerFilter.todos,
            );
        break;
      case _ClientesTopAction.purgeDebug:
        if (!_purgingAllDebug) {
          await _purgeAllDebug();
        }
        break;
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
      state.estadoFilter != EstadoFilter.todos,
      state.ownerFilter != OwnerFilter.todos,
    ].where((active) => active).length;

    return Scaffold(
      backgroundColor: isDesktop ? desktopSalesSurface : AppColors.background,
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      floatingActionButton: !isDesktop
          ? FloatingActionButton(
              onPressed: () => _showSummary(state),
              tooltip: 'Resumen',
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.summarize_rounded),
            )
          : null,

      appBar: isDesktop
          ? FullTechPageHeader(
              title: 'Clientes',
              actions: [
                _ClientsHeaderBadge(
                  icon: Icons.people_alt_outlined,
                  label: 'Clientes',
                  value: '${state.items.length}',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: state.refreshing ? 'Actualizando...' : 'Actualizar',
                  onPressed: state.refreshing
                      ? null
                      : () => controller.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 6),
                PopupMenuButton<_ClientesTopAction>(
                  tooltip: 'Opciones',
                  onSelected: _handleTopAction,
                  itemBuilder: (context) => [
                    _topMenuItem(
                      context,
                      value: _ClientesTopAction.newClient,
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Nuevo cliente',
                    ),
                    _topMenuItem(
                      context,
                      value: _ClientesTopAction.refresh,
                      icon: Icons.refresh_rounded,
                      label: state.refreshing
                          ? 'Actualizando...'
                          : 'Actualizar',
                      enabled: !state.refreshing,
                    ),
                    if (activeFilterCount > 0)
                      _topMenuItem(
                        context,
                        value: _ClientesTopAction.clearFilters,
                        icon: Icons.filter_alt_off_rounded,
                        label: 'Limpiar filtros',
                      ),
                    if (canUseDebugAdminAction(currentUser))
                      _topMenuItem(
                        context,
                        value: _ClientesTopAction.purgeDebug,
                        icon: Icons.delete_sweep_rounded,
                        label: _purgingAllDebug
                            ? 'Limpiando tabla...'
                            : 'Limpiar tabla (debug)',
                        enabled: !_purgingAllDebug,
                      ),
                  ],
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFCFE0FF)),
                    ),
                    child: const Icon(
                      Icons.more_vert_rounded,
                      color: Color(0xFF1957E6),
                    ),
                  ),
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
                    icon: const Icon(Icons.filter_alt_outlined),
                  ),
                  IconButton(
                    tooltip: 'Actualizar',
                    onPressed: () {
                      if (!state.refreshing) controller.refresh();
                    },
                    icon: const Icon(Icons.refresh_rounded),
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
                        onOpenDetail: selectedClient == null
                            ? null
                            : () => context.push(
                                Routes.clienteDetail(selectedClient.id),
                              ),
                        onCreateService: selectedClient == null
                            ? null
                            : () => context.push(
                                Routes.serviceOrderCreate,
                                extra: ServiceOrderCreateArgs(
                                  initialClientId: selectedClient.id,
                                ),
                              ),
                        onNewClient: _openCreateClientFlow,
                        onOpenMap: () => context.push(Routes.clientesMapa),
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
  });

  final ClienteModel client;
  final bool compact;
  final bool selected;
  final VoidCallback? onTap;

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

class _ClienteFixedInfoColumn extends StatelessWidget {
  const _ClienteFixedInfoColumn({
    required this.client,
    required this.totalClients,
    required this.refreshing,
    required this.onOpenDetail,
    required this.onCreateService,
    required this.onNewClient,
    required this.onOpenMap,
  });

  final ClienteModel? client;
  final int totalClients;
  final bool refreshing;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onCreateService;
  final VoidCallback onNewClient;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = client;

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
                        _ClientInfoLine(
                          icon: Icons.email_outlined,
                          label: 'Correo',
                          value: (selected.correo ?? '').trim().isEmpty
                              ? 'Sin correo'
                              : selected.correo!.trim(),
                        ),
                        _ClientInfoLine(
                          icon: Icons.place_outlined,
                          label: 'Dirección',
                          value: (selected.direccion ?? '').trim().isEmpty
                              ? 'Sin dirección registrada'
                              : selected.direccion!.trim(),
                          maxLines: 3,
                        ),
                        _ClientInfoLine(
                          icon: Icons.map_outlined,
                          label: 'Ubicación',
                          value: (selected.locationUrl ?? '').trim().isEmpty
                              ? 'Sin enlace GPS'
                              : 'GPS disponible',
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
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ClientColumnAction(
                  icon: Icons.open_in_new_rounded,
                  label: 'Abrir perfil completo',
                  onPressed: onOpenDetail,
                  prominent: true,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ClientColumnAction(
                        icon: Icons.add_business_rounded,
                        label: 'Orden',
                        onPressed: onCreateService,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ClientColumnAction(
                        icon: Icons.person_add_alt_1_rounded,
                        label: 'Nuevo',
                        onPressed: onNewClient,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ClientColumnAction(
                  icon: Icons.map_rounded,
                  label: 'Ver mapa de clientes',
                  onPressed: onOpenMap,
                ),
              ],
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

class _ClientColumnAction extends StatelessWidget {
  const _ClientColumnAction({
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
    if (prominent) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}

enum _ClientesTopAction { newClient, refresh, clearFilters, purgeDebug }

class _ClientsHeaderBadge extends StatelessWidget {
  const _ClientsHeaderBadge({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 116, minHeight: 46),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFCFE0FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF1957E6).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: const Color(0xFF1957E6), size: 16),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1957E6).withValues(alpha: 0.80),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

PopupMenuItem<_ClientesTopAction> _topMenuItem(
  BuildContext context, {
  required _ClientesTopAction value,
  required IconData icon,
  required String label,
  bool enabled = true,
}) {
  final theme = Theme.of(context);
  return PopupMenuItem<_ClientesTopAction>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
      ],
    ),
  );
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
                              'Orden, correo y estado',
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
                      _FilterSection<CorreoFilter>(
                        title: 'Correo',
                        value: _draft.correoFilter,
                        options: const [
                          CorreoFilter.todos,
                          CorreoFilter.conCorreo,
                          CorreoFilter.sinCorreo,
                        ],
                        labelBuilder: _correoFilterLabel,
                        onSelected: (value) {
                          setState(
                            () => _draft = _draft.copyWith(correoFilter: value),
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
                                estadoFilter: EstadoFilter.todos,
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

String _correoFilterLabel(CorreoFilter filter) {
  switch (filter) {
    case CorreoFilter.todos:
      return 'Todos';
    case CorreoFilter.conCorreo:
      return 'Con correo';
    case CorreoFilter.sinCorreo:
      return 'Sin correo';
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

class _ClientesSummaryDialog extends StatelessWidget {
  const _ClientesSummaryDialog({
    required this.totalClients,
    required this.activeClients,
    required this.deletedClients,
    required this.withEmail,
    required this.withPhone,
    required this.withAddress,
    required this.totalPurchasedFuture,
  });

  final int totalClients;
  final int activeClients;
  final int deletedClients;
  final int withEmail;
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
                    icon: Icons.email_outlined,
                    label: 'Con correo',
                    value: '$withEmail',
                    accent: const Color(0xFF0E7490),
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
