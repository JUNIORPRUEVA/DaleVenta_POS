import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/realtime/operations_realtime_service.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../clientes/cliente_model.dart';
import '../clientes/client_location_utils.dart';
import 'application/service_orders_list_controller.dart';
import 'create_service_order_screen.dart';
import 'data/service_orders_api.dart';
import 'service_order_models.dart';
import 'service_order_schedule_formatter.dart';
import 'widgets/client_location_card.dart';
import 'widgets/service_order_quick_actions_modal.dart';
import 'widgets/service_order_status_confirmation_dialog.dart';

bool _shouldUseOperationsDesktopLayout(double width) {
  if (width >= kDesktopShellBreakpoint) {
    return true;
  }

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

double _operationsDesktopSidebarWidth(double width) {
  if (width >= 1320) return 584; // Doble del ancho anterior (292 * 2)
  if (width >= 980) return 536; // Doble del ancho anterior (268 * 2)
  return 488; // Doble del ancho anterior (244 * 2)
}

class ServiceOrdersListScreen extends ConsumerStatefulWidget {
  const ServiceOrdersListScreen({super.key});

  @override
  ConsumerState<ServiceOrdersListScreen> createState() =>
      _ServiceOrdersListScreenState();
}

class _ServiceOrdersListScreenState
    extends ConsumerState<ServiceOrdersListScreen> {
  ServiceOrdersFilter _filter = const ServiceOrdersFilter.mainDefault();
  final TextEditingController _collapsedQuickSearchCtrl =
      TextEditingController();
  final Set<String> _busyOrderIds = <String>{};
  final Set<String> _creatingFromOrderIds = <String>{};
  bool _purgingAllDebug = false;
  bool _showRightPanel = true;
  ProviderSubscription<AuthState>? _authStateSubscription;
  StreamSubscription<OperationsRealtimeMessage>?
  _operationsRealtimeSubscription;

  @override
  void initState() {
    super.initState();
    _authStateSubscription = ref.listenManual<AuthState>(authStateProvider, (
      previous,
      next,
    ) {
      if (previous?.user?.id == next.user?.id) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _collapsedQuickSearchCtrl.clear();
        setState(() {
          _filter = const ServiceOrdersFilter.mainDefault();
          _busyOrderIds.clear();
          _creatingFromOrderIds.clear();
        });
      });
    });
    _operationsRealtimeSubscription = ref
        .read(operationsRealtimeServiceProvider)
        .stream
        .listen(_handleRealtimeMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(serviceOrdersListControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _authStateSubscription?.close();
    _operationsRealtimeSubscription?.cancel();
    _collapsedQuickSearchCtrl.dispose();
    super.dispose();
  }

  void _handleRealtimeMessage(OperationsRealtimeMessage message) {
    if (!mounted) return;
    final controller = ref.read(serviceOrdersListControllerProvider.notifier);
    if (message.type == 'service.deleted') {
      unawaited(controller.refresh());
      return;
    }

    final payload = message.service;
    if (payload == null) {
      unawaited(controller.refresh());
      return;
    }

    try {
      controller.upsertOrder(ServiceOrderModel.fromJson(payload));
    } catch (_) {
      unawaited(controller.refresh());
    }
  }

  Future<void> _purgeAllDebug() async {
    final confirmed = await confirmDebugAdminPurge(
      context,
      moduleLabel: 'operaciones',
      impactLabel: 'todas las órdenes de servicio visibles en este módulo',
    );
    if (!confirmed || !mounted) return;

    setState(() => _purgingAllDebug = true);
    try {
      final deleted = await ref
          .read(serviceOrdersListControllerProvider.notifier)
          .purgeAllDebug();
      if (!mounted) return;
      AppFeedback.showInfo(
        context,
        'Se limpiaron $deleted órdenes de servicio.',
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : '$e';
      AppFeedback.showError(context, message);
    } finally {
      if (mounted) {
        setState(() => _purgingAllDebug = false);
      }
    }
  }

  Future<void> _openFiltersSheet({
    required List<_FilterUserOption> availableCreators,
    required List<_FilterUserOption> availableTechnicians,
  }) async {
    final next = await showModalBottomSheet<ServiceOrdersFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _FiltersSheet(
          initialFilter: _filter,
          availableCreators: availableCreators,
          availableTechnicians: availableTechnicians,
        );
      },
    );
    if (next == null || !mounted) {
      return;
    }
    setState(() {
      _filter = next;
    });
  }

  Future<void> _openControlPanelDialog({
    required int activeCount,
    required bool refreshing,
    required List<_FilterUserOption> availableCreators,
    required List<_FilterUserOption> availableTechnicians,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Panel de operaciones',
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final maxWidth = screenSize.width >= 1180
            ? 860.0
            : screenSize.width >= 760
            ? 700.0
            : screenSize.width - 24;
        final maxHeight = screenSize.height * 0.78;

        return SafeArea(
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> handleOpenFilters() async {
                await _openFiltersSheet(
                  availableCreators: availableCreators,
                  availableTechnicians: availableTechnicians,
                );
                if (!dialogContext.mounted) return;
                setDialogState(() {});
              }

              void updateFilter(ServiceOrdersFilter nextFilter) {
                setState(() {
                  _filter = nextFilter;
                });
                setDialogState(() {});
              }

              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 18,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: SingleChildScrollView(
                        child: _OperationsControlPanel(
                          filter: _filter,
                          activeCount: activeCount,
                          refreshing: refreshing,
                          searchController: _collapsedQuickSearchCtrl,
                          onSearchChanged: (_) {
                            setState(() {});
                            setDialogState(() {});
                          },
                          onClearSearch: () {
                            _collapsedQuickSearchCtrl.clear();
                            setState(() {});
                            setDialogState(() {});
                          },
                          onOpenFilters: handleOpenFilters,
                          onCollapse: () => Navigator.of(dialogContext).pop(),
                          collapseIcon: Icons.close_rounded,
                          collapseTooltip: 'Cerrar panel',
                          onReset: _filter.hasActiveFilters
                              ? () => updateFilter(
                                  const ServiceOrdersFilter.mainDefault(),
                                )
                              : null,
                          onToggleStatus: (status) {
                            final nextStatuses = {..._filter.statuses};
                            if (nextStatuses.contains(status)) {
                              nextStatuses.remove(status);
                            } else {
                              nextStatuses.add(status);
                            }
                            updateFilter(
                              _filter.copyWith(statuses: nextStatuses),
                            );
                          },
                          onToggleServiceType: (serviceType) {
                            final nextTypes = {..._filter.serviceTypes};
                            if (nextTypes.contains(serviceType)) {
                              nextTypes.remove(serviceType);
                            } else {
                              nextTypes.add(serviceType);
                            }
                            updateFilter(
                              _filter.copyWith(serviceTypes: nextTypes),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceOrdersListControllerProvider);
    final controller = ref.read(serviceOrdersListControllerProvider.notifier);
    final currentUser = ref.watch(authStateProvider).user;
    final canManageStatusAsRole =
        currentUser?.appRole.isAdmin == true ||
        currentUser?.appRole.isTechnician == true;
    final isAdmin = currentUser?.appRole.isAdmin ?? false;
    final currentUserId = currentUser?.id ?? '';
    final supportConversationUri = _buildAssistantConversationUri(
      state.usersById,
    );
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = _shouldUseOperationsDesktopLayout(width);
    final visibleOrders = _applyCollapsedQuickSearch(
      orders: _filter.apply(state.items),
      clientsById: state.clientsById,
      usersById: state.usersById,
    );
    final availableCreators = _buildFilterUserOptions(
      orders: state.items,
      usersById: state.usersById,
      userIdSelector: (order) => order.createdById,
    );
    final availableTechnicians = _buildFilterUserOptions(
      orders: state.items,
      usersById: state.usersById,
      userIdSelector: (order) => order.assignedToId,
    );
    final contentMaxWidth = isDesktop ? 1120.0 : double.infinity;
    final canShowPurgeAction = canUseDebugAdminAction(currentUser);
    final gpsReadyCount = visibleOrders.where((order) {
      final client = order.client ?? state.clientsById[order.clientId];
      final preview = parseClientLocationPreview(client?.locationUrl);
      return buildClientNavigationUri(preview, client?.locationUrl) != null;
    }).length;
    final scheduledCount = visibleOrders
        .where((order) => order.scheduledFor != null)
        .length;
    final pendingCount = visibleOrders
        .where((order) => order.status == ServiceOrderStatus.pendiente)
        .length;
    final inProgressCount = visibleOrders
        .where((order) => order.status == ServiceOrderStatus.enProceso)
        .length;
    final pausedCount = visibleOrders
        .where((order) => order.status == ServiceOrderStatus.enPausa)
        .length;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      floatingActionButton: _CreateOrderFab(onPressed: _createOrder),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: FullTechPageHeader(
        title: 'Operaciones',
        actions: [
          _PriorityMapButton(
            onPressed: () => context.push(Routes.clientesMapa),
          ),
          PopupMenuButton<_OperationsOverflowAction>(
            tooltip: 'Más opciones',
            enabled: !state.refreshing || canShowPurgeAction,
            onSelected: (action) async {
              switch (action) {
                case _OperationsOverflowAction.sync:
                  await controller.refresh();
                case _OperationsOverflowAction.purge:
                  await _purgeAllDebug();
              }
            },
            itemBuilder: (menuContext) {
              final colorScheme = Theme.of(menuContext).colorScheme;
              return [
                PopupMenuItem<_OperationsOverflowAction>(
                  value: _OperationsOverflowAction.sync,
                  enabled: !state.refreshing,
                  child: Row(
                    children: [
                      if (state.refreshing)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.1,
                            color: colorScheme.primary,
                          ),
                        )
                      else
                        const Icon(Icons.sync_rounded, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        state.refreshing ? 'Sincronizando...' : 'Sincronizar',
                      ),
                    ],
                  ),
                ),
                if (canShowPurgeAction)
                  PopupMenuItem<_OperationsOverflowAction>(
                    value: _OperationsOverflowAction.purge,
                    enabled: !_purgingAllDebug,
                    child: Row(
                      children: [
                        if (_purgingAllDebug)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.1,
                              color: colorScheme.error,
                            ),
                          )
                        else
                          Icon(
                            Icons.delete_sweep_rounded,
                            size: 18,
                            color: colorScheme.error,
                          ),
                        const SizedBox(width: 10),
                        Text(
                          _purgingAllDebug
                              ? 'Eliminando datos...'
                              : 'Eliminar todo',
                        ),
                      ],
                    ),
                  ),
              ];
            },
            icon: const Icon(Icons.more_vert_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
      ),
      body: isDesktop
          ? Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildOrdersRefreshContent(
                        state: state,
                        controller: controller,
                        currentUser: currentUser,
                        canManageStatusAsRole: canManageStatusAsRole,
                        isAdmin: isAdmin,
                        currentUserId: currentUserId,
                        supportConversationUri: supportConversationUri,
                        visibleOrders: visibleOrders,
                        contentMaxWidth: contentMaxWidth,
                        desktopLayout: true,
                        availableCreators: availableCreators,
                        availableTechnicians: availableTechnicians,
                        pendingCount: pendingCount,
                        inProgressCount: inProgressCount,
                        pausedCount: pausedCount,
                        gpsReadyCount: gpsReadyCount,
                        scheduledCount: scheduledCount,
                      ),
                    ),
                    if (_showRightPanel)
                      SizedBox(
                        width: _operationsDesktopSidebarWidth(width),
                        child: _DesktopOperationsFilterSidebar(
                          filter: _filter,
                          activeCount: visibleOrders.length,
                          refreshing: state.refreshing,
                          searchController: _collapsedQuickSearchCtrl,
                          availableCreators: availableCreators,
                          availableTechnicians: availableTechnicians,
                          visibleOrders: visibleOrders,
                          onSearchChanged: (_) => setState(() {}),
                          onClearSearch: () {
                            _collapsedQuickSearchCtrl.clear();
                            setState(() {});
                          },
                          onReset: () => setState(() {
                            _collapsedQuickSearchCtrl.clear();
                            _filter = const ServiceOrdersFilter.mainDefault();
                          }),
                          onFilterChanged: (next) => setState(() {
                            _filter = next;
                          }),
                          onPickCustomRange: _pickDesktopCustomRange,
                        ),
                      ),
                  ],
                ),
                if (_showRightPanel)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 14, right: 6),
                        child: _SidebarToggleButton(
                          icon: Icons.chevron_right,
                          tooltip: 'Ocultar panel de filtros',
                          onPressed: () =>
                              setState(() => _showRightPanel = false),
                        ),
                      ),
                    ),
                  ),
                if (!_showRightPanel)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Align(
                      alignment: Alignment.center,
                      child: _SidebarToggleButton(
                        icon: Icons.chevron_left,
                        tooltip: 'Mostrar panel de filtros',
                        onPressed: () => setState(() => _showRightPanel = true),
                      ),
                    ),
                  ),
              ],
            )
          : _buildOrdersRefreshContent(
              state: state,
              controller: controller,
              currentUser: currentUser,
              canManageStatusAsRole: canManageStatusAsRole,
              isAdmin: isAdmin,
              currentUserId: currentUserId,
              supportConversationUri: supportConversationUri,
              visibleOrders: visibleOrders,
              contentMaxWidth: contentMaxWidth,
              desktopLayout: false,
              availableCreators: availableCreators,
              availableTechnicians: availableTechnicians,
              pendingCount: pendingCount,
              inProgressCount: inProgressCount,
              pausedCount: pausedCount,
              gpsReadyCount: gpsReadyCount,
              scheduledCount: scheduledCount,
            ),
    );
  }

  Widget _buildOrdersRefreshContent({
    required ServiceOrdersListState state,
    required ServiceOrdersListController controller,
    required UserModel? currentUser,
    required bool canManageStatusAsRole,
    required bool isAdmin,
    required String currentUserId,
    required Uri? supportConversationUri,
    required List<ServiceOrderModel> visibleOrders,
    required double contentMaxWidth,
    required bool desktopLayout,
    required List<_FilterUserOption> availableCreators,
    required List<_FilterUserOption> availableTechnicians,
    required int pendingCount,
    required int inProgressCount,
    required int pausedCount,
    required int gpsReadyCount,
    required int scheduledCount,
  }) {
    final header = Center(
      key: const ValueKey('operations-header'),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.only(bottom: desktopLayout ? 10 : 8),
          child: desktopLayout
              ? _DesktopOperationsOverviewPanel(
                  filter: _filter,
                  activeCount: visibleOrders.length,
                  pendingCount: pendingCount,
                  inProgressCount: inProgressCount,
                  pausedCount: pausedCount,
                  gpsReadyCount: gpsReadyCount,
                  scheduledCount: scheduledCount,
                  refreshing: state.refreshing,
                )
              : Align(
                  alignment: Alignment.centerRight,
                  child: _CollapsedOperationsPanelToggle(
                    activeCount: visibleOrders.length,
                    hasActiveFilters: _filter.hasActiveFilters,
                    searchController: _collapsedQuickSearchCtrl,
                    onSearchChanged: (_) {
                      setState(() {});
                    },
                    onClearSearch: () {
                      _collapsedQuickSearchCtrl.clear();
                      setState(() {});
                    },
                    onOpenFilters: () {
                      _openFiltersSheet(
                        availableCreators: availableCreators,
                        availableTechnicians: availableTechnicians,
                      );
                    },
                    onTap: () {
                      _openControlPanelDialog(
                        activeCount: visibleOrders.length,
                        refreshing: state.refreshing,
                        availableCreators: availableCreators,
                        availableTechnicians: availableTechnicians,
                      );
                    },
                  ),
                ),
        ),
      ),
    );

    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: state.error != null && state.items.isEmpty && !state.refreshing
          ? ListView(
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 30,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 10),
                        Text(state.error!, textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: state.refreshing ? null : controller.retry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : visibleOrders.isEmpty
          ? ListView(
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              addSemanticIndexes: false,
              padding: EdgeInsets.fromLTRB(
                desktopLayout ? 18 : 12,
                desktopLayout ? 12 : 8,
                desktopLayout ? 14 : 12,
                88,
              ),
              children: [
                header,
                Center(
                  key: const ValueKey('operations-empty-state'),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMaxWidth),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 28),
                      child: _EmptyOrdersState(),
                    ),
                  ),
                ),
              ],
            )
          : Padding(
              padding: EdgeInsets.fromLTRB(
                desktopLayout ? 18 : 12,
                desktopLayout ? 12 : 8,
                desktopLayout ? 14 : 12,
                0,
              ),
              child: Column(
                children: [
                  header,
                  Expanded(
                    child: ListView.builder(
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      addSemanticIndexes: false,
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: visibleOrders.length,
                      itemBuilder: (context, index) {
                        final order = visibleOrders[index];
                        final canChangeOrderStatus =
                            canManageStatusAsRole ||
                            currentUserId == order.createdById;
                        final client =
                            order.client ?? state.clientsById[order.clientId];
                        final assignedToId = (order.assignedToId ?? '').trim();
                        final technicianName = assignedToId.isEmpty
                            ? ''
                            : (state.usersById[assignedToId]?.nombreCompleto ??
                                  assignedToId);
                        final sellerConversationUri = _buildWhatsAppUri(
                          state.usersById[order.createdById]?.telefono ?? '',
                        );
                        return Center(
                          key: ValueKey('service-order-${order.id}'),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: contentMaxWidth,
                            ),
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: desktopLayout ? 2 : 8,
                              ),
                              child: _ServiceOrderListCard(
                                order: order,
                                client: client,
                                clientName:
                                    client?.nombre ??
                                    'Cliente ${order.clientId}',
                                creatorName:
                                    state
                                        .usersById[order.createdById]
                                        ?.nombreCompleto ??
                                    order.createdById,
                                technicianName: technicianName,
                                sellerConversationUri: sellerConversationUri,
                                supportConversationUri: supportConversationUri,
                                statusBusy: _busyOrderIds.contains(order.id),
                                isTechnician:
                                    currentUser?.appRole.isTechnician ?? false,
                                canPromoteStatus: canManageStatusAsRole,
                                onChangeStatus: canChangeOrderStatus
                                    ? (status) =>
                                          _changeOrderStatus(order, status)
                                    : null,
                                creatingNewOrder: _creatingFromOrderIds
                                    .contains(order.id),
                                onCreateNewOrder: order.isCloneSourceAllowed
                                    ? () => _createOrderFromSource(order)
                                    : null,
                                onEdit:
                                    (isAdmin ||
                                        currentUserId == order.createdById)
                                    ? () => _editOrder(order)
                                    : null,
                                onDelete: isAdmin
                                    ? () => _deleteOrder(order)
                                    : null,
                                onTap: () async {
                                  final updated = await context.push<bool>(
                                    Routes.serviceOrderById(order.id),
                                  );
                                  if (updated == true) {
                                    await controller.refresh();
                                  }
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<DateTimeRange?> _pickDesktopCustomRange() async {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _filter.customRange,
      helpText: 'Selecciona el rango',
    );
  }

  Future<void> _editOrder(ServiceOrderModel order) async {
    final updated = await openCreateServiceOrderAdaptive(
      context,
      args: ServiceOrderCreateArgs(editSource: order),
    );
    if (updated == true) {
      await ref.read(serviceOrdersListControllerProvider.notifier).refresh();
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Orden actualizada');
    }
  }

  Future<void> _createOrderFromSource(ServiceOrderModel order) async {
    if (_creatingFromOrderIds.contains(order.id)) {
      return;
    }

    setState(() {
      _creatingFromOrderIds.add(order.id);
    });

    try {
      final created = await openCreateServiceOrderAdaptive(
        context,
        args: ServiceOrderCreateArgs(cloneSource: order),
      );
      if (created == true) {
        await ref.read(serviceOrdersListControllerProvider.notifier).refresh();
        if (!mounted) return;
        await AppFeedback.showInfo(context, 'Nueva orden creada');
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingFromOrderIds.remove(order.id);
        });
      }
    }
  }

  Future<void> _createOrder() async {
    final created = await openCreateServiceOrderAdaptive(context);
    if (created == true) {
      await ref.read(serviceOrdersListControllerProvider.notifier).refresh();
      if (!mounted) return;
      await AppFeedback.showInfo(
        context,
        'Lista actualizada con la nueva orden',
      );
    }
  }

  Future<void> _deleteOrder(ServiceOrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar orden'),
          content: Text(
            'Esta acción eliminará la orden de ${order.category.label.toLowerCase()} para este cliente. No se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busyOrderIds.add(order.id);
    });

    try {
      await ref
          .read(serviceOrdersListControllerProvider.notifier)
          .deleteOrder(order.id);
      if (!mounted) return;
      await AppFeedback.showInfo(context, 'Orden eliminada');
    } catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error is ApiException ? error.message : 'No se pudo eliminar la orden',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busyOrderIds.remove(order.id);
        });
      }
    }
  }

  Future<void> _changeOrderStatus(
    ServiceOrderModel order,
    ServiceOrderStatus status,
  ) async {
    if (_busyOrderIds.contains(order.id) || status == order.status) {
      return;
    }

    try {
      final didUpdate = await showServiceOrderStatusConfirmationDialog(
        context: context,
        status: status,
        initialScheduledAt: order.scheduledFor,
        onConfirm: (scheduledAt) async {
          final previousOrder = order;
          setState(() {
            _busyOrderIds.add(order.id);
          });
          ref
              .read(serviceOrdersListControllerProvider.notifier)
              .replaceOrderStatus(
                orderId: order.id,
                status: status,
                scheduledFor: scheduledAt ?? order.scheduledFor,
              );

          try {
            final updated = await ref
                .read(serviceOrdersApiProvider)
                .updateStatus(order.id, status, scheduledAt: scheduledAt);
            ref
                .read(serviceOrdersListControllerProvider.notifier)
                .upsertOrder(updated);
          } catch (error) {
            ref
                .read(serviceOrdersListControllerProvider.notifier)
                .upsertOrder(previousOrder);
            rethrow;
          } finally {
            if (mounted) {
              setState(() {
                _busyOrderIds.remove(order.id);
              });
            }
          }
        },
      );

      if (didUpdate != true || !mounted) {
        return;
      }

      await AppFeedback.showInfo(context, 'Estado actualizado');
    } catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error is ApiException
            ? error.message
            : 'No se pudo actualizar el estado',
      );
    }
  }

  List<ServiceOrderModel> _applyCollapsedQuickSearch({
    required List<ServiceOrderModel> orders,
    required Map<String, ClienteModel> clientsById,
    required Map<String, UserModel> usersById,
  }) {
    final query = _normalizeCollapsedQuickSearch(
      _collapsedQuickSearchCtrl.text,
    );
    if (query.isEmpty) {
      return orders;
    }

    return orders
        .where((order) {
          final client = order.client ?? clientsById[order.clientId];
          final creatorName =
              usersById[order.createdById]?.nombreCompleto ?? '';
          final technicianName = order.assignedToId == null
              ? ''
              : (usersById[order.assignedToId!]?.nombreCompleto ?? '');
          final searchable = _normalizeCollapsedQuickSearch(
            [
              order.id,
              order.clientId,
              order.quotationId ?? '',
              order.category.label,
              order.serviceType.label,
              order.status.label,
              client?.nombre ?? '',
              client?.telefono ?? '',
              creatorName,
              technicianName,
              order.technicalNote ?? '',
              order.extraRequirements ?? '',
            ].join(' '),
          );
          return searchable.contains(query);
        })
        .toList(growable: false);
  }

  String _normalizeCollapsedQuickSearch(String value) {
    return value.toLowerCase().trim();
  }
}

enum ServiceOrdersDatePreset {
  all,
  today,
  yesterday,
  thisWeek,
  currentPayPeriod,
  previousPayPeriod,
  custom,
}

enum ServiceOrdersCompletionFilter { any, finalizadas, noFinalizadas }

extension ServiceOrdersCompletionFilterX on ServiceOrdersCompletionFilter {
  String get label {
    switch (this) {
      case ServiceOrdersCompletionFilter.any:
        return 'Todas';
      case ServiceOrdersCompletionFilter.finalizadas:
        return 'Finalizadas';
      case ServiceOrdersCompletionFilter.noFinalizadas:
        return 'No finalizadas';
    }
  }

  IconData get icon {
    switch (this) {
      case ServiceOrdersCompletionFilter.any:
        return Icons.tune_rounded;
      case ServiceOrdersCompletionFilter.finalizadas:
        return Icons.verified_rounded;
      case ServiceOrdersCompletionFilter.noFinalizadas:
        return Icons.pending_actions_rounded;
    }
  }
}

class ServiceOrdersFilter {
  const ServiceOrdersFilter({
    required this.datePreset,
    this.completionFilter = ServiceOrdersCompletionFilter.any,
    this.statuses = const <ServiceOrderStatus>{},
    this.serviceTypes = const <ServiceOrderType>{},
    this.creatorIds = const <String>{},
    this.technicianIds = const <String>{},
    this.customRange,
  });

  const ServiceOrdersFilter.today()
    : datePreset = ServiceOrdersDatePreset.today,
      completionFilter = ServiceOrdersCompletionFilter.any,
      statuses = const <ServiceOrderStatus>{},
      serviceTypes = const <ServiceOrderType>{},
      creatorIds = const <String>{},
      technicianIds = const <String>{},
      customRange = null;

  const ServiceOrdersFilter.mainDefault()
    : datePreset = ServiceOrdersDatePreset.all,
      completionFilter = ServiceOrdersCompletionFilter.any,
      statuses = const <ServiceOrderStatus>{
        ServiceOrderStatus.pendiente,
        ServiceOrderStatus.enProceso,
        ServiceOrderStatus.enPausa,
      },
      serviceTypes = const <ServiceOrderType>{},
      creatorIds = const <String>{},
      technicianIds = const <String>{},
      customRange = null;

  final ServiceOrdersDatePreset datePreset;
  final ServiceOrdersCompletionFilter completionFilter;
  final Set<ServiceOrderStatus> statuses;
  final Set<ServiceOrderType> serviceTypes;
  final Set<String> creatorIds;
  final Set<String> technicianIds;
  final DateTimeRange? customRange;

  bool get isMainDefault {
    return datePreset == ServiceOrdersDatePreset.all &&
        completionFilter == ServiceOrdersCompletionFilter.any &&
        serviceTypes.isEmpty &&
        creatorIds.isEmpty &&
        technicianIds.isEmpty &&
        statuses.length == 3 &&
        statuses.contains(ServiceOrderStatus.pendiente) &&
        statuses.contains(ServiceOrderStatus.enProceso) &&
        statuses.contains(ServiceOrderStatus.enPausa);
  }

  ServiceOrdersFilter copyWith({
    ServiceOrdersDatePreset? datePreset,
    ServiceOrdersCompletionFilter? completionFilter,
    Set<ServiceOrderStatus>? statuses,
    Set<ServiceOrderType>? serviceTypes,
    Set<String>? creatorIds,
    Set<String>? technicianIds,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
  }) {
    return ServiceOrdersFilter(
      datePreset: datePreset ?? this.datePreset,
      completionFilter: completionFilter ?? this.completionFilter,
      statuses: statuses ?? this.statuses,
      serviceTypes: serviceTypes ?? this.serviceTypes,
      creatorIds: creatorIds ?? this.creatorIds,
      technicianIds: technicianIds ?? this.technicianIds,
      customRange: clearCustomRange ? null : (customRange ?? this.customRange),
    );
  }

  bool get hasActiveFilters {
    return !isMainDefault;
  }

  int get selectionCount {
    var total = 0;
    if (datePreset != ServiceOrdersDatePreset.all) {
      total += 1;
    }
    if (completionFilter != ServiceOrdersCompletionFilter.any) {
      total += 1;
    }
    total += statuses.length;
    total += serviceTypes.length;
    total += creatorIds.length;
    total += technicianIds.length;
    return total;
  }

  String get summaryLabel {
    switch (datePreset) {
      case ServiceOrdersDatePreset.all:
        return 'Órdenes activas';
      case ServiceOrdersDatePreset.today:
        return 'Hoy';
      case ServiceOrdersDatePreset.yesterday:
        return 'Ayer';
      case ServiceOrdersDatePreset.thisWeek:
        return 'Esta semana';
      case ServiceOrdersDatePreset.currentPayPeriod:
        return 'Quincena actual';
      case ServiceOrdersDatePreset.previousPayPeriod:
        return 'Quincena pasada';
      case ServiceOrdersDatePreset.custom:
        if (customRange == null) return 'Personalizado';
        final formatter = DateFormat('dd MMM', 'es_DO');
        return '${formatter.format(customRange!.start)} - ${formatter.format(customRange!.end)}';
    }
  }

  List<String> get activeChips {
    final chips = <String>[summaryLabel];
    if (completionFilter != ServiceOrdersCompletionFilter.any) {
      chips.add(completionFilter.label);
    }
    chips.addAll(statuses.map((status) => status.label));
    chips.addAll(serviceTypes.map((serviceType) => serviceType.label));
    if (creatorIds.isNotEmpty) {
      chips.add(
        creatorIds.length == 1 ? '1 creador' : '${creatorIds.length} creadores',
      );
    }
    if (technicianIds.isNotEmpty) {
      chips.add(
        technicianIds.length == 1
            ? '1 técnico'
            : '${technicianIds.length} técnicos',
      );
    }
    return chips;
  }

  List<String> get insightChips {
    final chips = <String>[];
    if (completionFilter != ServiceOrdersCompletionFilter.any) {
      chips.add(completionFilter.label);
    }
    if (creatorIds.isNotEmpty) {
      chips.add(
        creatorIds.length == 1 ? '1 creador' : '${creatorIds.length} creadores',
      );
    }
    if (technicianIds.isNotEmpty) {
      chips.add(
        technicianIds.length == 1
            ? '1 técnico'
            : '${technicianIds.length} técnicos',
      );
    }
    return chips;
  }

  List<ServiceOrderModel> apply(List<ServiceOrderModel> source) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = todayStart;
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Calcular quincenas: 15-29 y 30-14 (del mes siguiente)
    DateTime payPeriodStart, payPeriodEnd;
    if (now.day >= 15 && now.day <= 29) {
      // Primera quincena (15-29)
      payPeriodStart = DateTime(now.year, now.month, 15);
      payPeriodEnd = DateTime(now.year, now.month, 30);
    } else if (now.day >= 30) {
      // Segunda quincena (30-14 del siguiente mes)
      payPeriodStart = DateTime(now.year, now.month, 30);
      final nextMonth = now.month == 12 ? 1 : now.month + 1;
      final nextYear = now.month == 12 ? now.year + 1 : now.year;
      payPeriodEnd = DateTime(nextYear, nextMonth, 15);
    } else {
      // Primeros 14 días: segunda quincena del mes anterior
      final prevMonth = now.month == 1 ? 12 : now.month - 1;
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      payPeriodStart = DateTime(prevYear, prevMonth, 30);
      payPeriodEnd = DateTime(now.year, now.month, 15);
    }

    // Quincena pasada
    DateTime prevPayPeriodStart, prevPayPeriodEnd;
    if (payPeriodStart.day == 15) {
      // La quincena actual es 15-29, la pasada es 30-14
      prevPayPeriodStart = DateTime(
        now.year,
        now.month,
        30,
      ).subtract(Duration(days: DateTime(now.year, now.month, 30).day - 1));
      prevPayPeriodStart = DateTime(
        now.year,
        now.month - (now.month > 1 ? 1 : 12),
        now.month > 1 ? 30 : 30,
      );
      prevPayPeriodEnd = payPeriodStart;
    } else {
      // La quincena actual es 30-14, la pasada es 15-29
      prevPayPeriodStart = DateTime(now.year, now.month, 15);
      prevPayPeriodEnd = payPeriodStart;
    }

    final customStart = customRange == null
        ? null
        : DateTime(
            customRange!.start.year,
            customRange!.start.month,
            customRange!.start.day,
          );
    final customEnd = customRange == null
        ? null
        : DateTime(
            customRange!.end.year,
            customRange!.end.month,
            customRange!.end.day,
          ).add(const Duration(days: 1));

    return source
        .where((order) {
          final activityAt = (order.lastStatusChangedAt ?? order.createdAt)
              .toLocal();
          final matchesDate = switch (datePreset) {
            ServiceOrdersDatePreset.all => true,
            ServiceOrdersDatePreset.today =>
              !activityAt.isBefore(todayStart) && activityAt.isBefore(todayEnd),
            ServiceOrdersDatePreset.yesterday =>
              !activityAt.isBefore(yesterdayStart) &&
                  activityAt.isBefore(yesterdayEnd),
            ServiceOrdersDatePreset.thisWeek =>
              !activityAt.isBefore(weekStart) && activityAt.isBefore(weekEnd),
            ServiceOrdersDatePreset.currentPayPeriod =>
              !activityAt.isBefore(payPeriodStart) &&
                  activityAt.isBefore(payPeriodEnd),
            ServiceOrdersDatePreset.previousPayPeriod =>
              !activityAt.isBefore(prevPayPeriodStart) &&
                  activityAt.isBefore(prevPayPeriodEnd),
            ServiceOrdersDatePreset.custom =>
              customStart != null &&
                  customEnd != null &&
                  !activityAt.isBefore(customStart) &&
                  activityAt.isBefore(customEnd),
          };

          if (!matchesDate) {
            return false;
          }
          final matchesCompletion = switch (completionFilter) {
            ServiceOrdersCompletionFilter.any => true,
            ServiceOrdersCompletionFilter.finalizadas =>
              order.status == ServiceOrderStatus.finalizado,
            ServiceOrdersCompletionFilter.noFinalizadas =>
              order.status != ServiceOrderStatus.finalizado,
          };
          if (!matchesCompletion) {
            return false;
          }
          if (statuses.isNotEmpty && !statuses.contains(order.status)) {
            return false;
          }
          if (serviceTypes.isNotEmpty &&
              !serviceTypes.contains(order.serviceType)) {
            return false;
          }
          if (creatorIds.isNotEmpty &&
              !creatorIds.contains(order.createdById)) {
            return false;
          }
          final assignedToId = order.assignedToId?.trim();
          if (technicianIds.isNotEmpty &&
              (assignedToId == null || !technicianIds.contains(assignedToId))) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }
}

class _FilterUserOption {
  const _FilterUserOption({
    required this.id,
    required this.label,
    required this.role,
  });

  final String id;
  final String label;
  final AppRole role;

  String get roleLabel {
    switch (role) {
      case AppRole.admin:
        return 'Administrador';
      case AppRole.cajero:
        return 'Cajero';
      case AppRole.asistente:
        return 'Asistente';
      case AppRole.vendedor:
        return 'Vendedor';
      case AppRole.marketing:
        return 'Marketing';
      case AppRole.tecnico:
        return 'Técnico';
      case AppRole.unknown:
        return 'Usuario';
    }
  }

  String get initials {
    final parts = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'FT';
    }
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

List<_FilterUserOption> _buildFilterUserOptions({
  required List<ServiceOrderModel> orders,
  required Map<String, UserModel> usersById,
  required String? Function(ServiceOrderModel order) userIdSelector,
}) {
  final ids = <String>{};
  for (final order in orders) {
    final userId = userIdSelector(order)?.trim() ?? '';
    if (userId.isNotEmpty) {
      ids.add(userId);
    }
  }

  final options = ids
      .map((id) {
        final user = usersById[id];
        final fallbackLabel = id.length <= 8
            ? 'Usuario $id'
            : 'Usuario ${id.substring(0, 8)}';
        return _FilterUserOption(
          id: id,
          label: (user?.nombreCompleto ?? '').trim().isEmpty
              ? fallbackLabel
              : user!.nombreCompleto.trim(),
          role: user?.appRole ?? AppRole.unknown,
        );
      })
      .toList(growable: false);

  options.sort(
    (left, right) =>
        left.label.toLowerCase().compareTo(right.label.toLowerCase()),
  );
  return options;
}

enum _OperationsOverflowAction { sync, purge }

class _SidebarToggleButton extends StatelessWidget {
  const _SidebarToggleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.78),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _PriorityMapButton extends StatelessWidget {
  const _PriorityMapButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: 'Mapa de clientes',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(Icons.map_rounded, size: 21),
            ),
          ),
        ),
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({
    required this.initialFilter,
    required this.availableCreators,
    required this.availableTechnicians,
  });

  final ServiceOrdersFilter initialFilter;
  final List<_FilterUserOption> availableCreators;
  final List<_FilterUserOption> availableTechnicians;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late Set<ServiceOrderStatus> _statuses;
  late Set<ServiceOrderType> _serviceTypes;
  late ServiceOrdersDatePreset _datePreset;
  late ServiceOrdersCompletionFilter _completionFilter;
  late Set<String> _creatorIds;
  late Set<String> _technicianIds;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _statuses = {...widget.initialFilter.statuses};
    _serviceTypes = {...widget.initialFilter.serviceTypes};
    _completionFilter = widget.initialFilter.completionFilter;
    _creatorIds = {...widget.initialFilter.creatorIds};
    _technicianIds = {...widget.initialFilter.technicianIds};
    _datePreset = widget.initialFilter.datePreset;
    _customRange = widget.initialFilter.customRange;
  }

  int get _selectedCount {
    return ServiceOrdersFilter(
      datePreset: _datePreset,
      completionFilter: _completionFilter,
      statuses: _statuses,
      serviceTypes: _serviceTypes,
      creatorIds: _creatorIds,
      technicianIds: _technicianIds,
      customRange: _customRange,
    ).selectionCount;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colorScheme.surface, colorScheme.surfaceContainerLowest],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompactHeader(
                selectedCount: _selectedCount,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 10),
              _CompactSection(
                title: 'Estado',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrderStatus.values
                      .map((status) {
                        final selected = _statuses.contains(status);
                        return FilterChip(
                          selected: selected,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          label: Text(status.label),
                          selectedColor: status.color.withValues(alpha: 0.12),
                          side: BorderSide(
                            color: selected
                                ? status.color.withValues(alpha: 0.35)
                                : theme.colorScheme.outlineVariant,
                          ),
                          labelStyle: TextStyle(
                            color: selected ? status.color : null,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          onSelected: (_) {
                            setState(() {
                              if (selected) {
                                _statuses.remove(status);
                              } else {
                                _statuses.add(status);
                              }
                            });
                          },
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 10),
              _CompactSection(
                title: 'Servicio',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ServiceOrderType.values
                      .map((serviceType) {
                        final selected = _serviceTypes.contains(serviceType);
                        return FilterChip(
                          selected: selected,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          label: Text(serviceType.label),
                          onSelected: (_) {
                            setState(() {
                              if (selected) {
                                _serviceTypes.remove(serviceType);
                              } else {
                                _serviceTypes.add(serviceType);
                              }
                            });
                          },
                        );
                      })
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 10),
              _CompactSection(
                title: 'Fecha',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ChoiceFilterTile(
                      label: 'Todas',
                      icon: Icons.all_inbox_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.all,
                      compact: true,
                      onTap: () {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.all;
                        });
                      },
                    ),
                    _ChoiceFilterTile(
                      label: 'Hoy',
                      icon: Icons.today_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.today,
                      compact: true,
                      onTap: () {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.today;
                        });
                      },
                    ),
                    _ChoiceFilterTile(
                      label: 'Semana',
                      icon: Icons.date_range_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.thisWeek,
                      compact: true,
                      onTap: () {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.thisWeek;
                        });
                      },
                    ),
                    _ChoiceFilterTile(
                      label: 'Rango',
                      icon: Icons.edit_calendar_rounded,
                      selected: _datePreset == ServiceOrdersDatePreset.custom,
                      compact: true,
                      onTap: () async {
                        setState(() {
                          _datePreset = ServiceOrdersDatePreset.custom;
                        });
                        await _pickCustomRange();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SummarySelectorTile(
                      label: 'Creador',
                      summary: _selectionSummary(
                        selectedIds: _creatorIds,
                        options: widget.availableCreators,
                      ),
                      icon: Icons.person_search_rounded,
                      accent: colorScheme.primary,
                      onTap: () async {
                        final next = await _pickUserOptions(
                          title: 'Filtrar por creador',
                          options: widget.availableCreators,
                          selectedIds: _creatorIds,
                          accent: colorScheme.primary,
                        );
                        if (next == null || !mounted) {
                          return;
                        }
                        setState(() {
                          _creatorIds = next;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummarySelectorTile(
                      label: 'Técnico',
                      summary: _selectionSummary(
                        selectedIds: _technicianIds,
                        options: widget.availableTechnicians,
                      ),
                      icon: Icons.engineering_rounded,
                      accent: const Color(0xFF0F766E),
                      onTap: () async {
                        final next = await _pickUserOptions(
                          title: 'Filtrar por técnico',
                          options: widget.availableTechnicians,
                          selectedIds: _technicianIds,
                          accent: const Color(0xFF0F766E),
                        );
                        if (next == null || !mounted) {
                          return;
                        }
                        setState(() {
                          _technicianIds = next;
                        });
                      },
                    ),
                  ),
                ],
              ),
              if (_datePreset == ServiceOrdersDatePreset.custom) ...[
                const SizedBox(height: 10),
                _CustomDateRangeBanner(
                  range: _customRange,
                  compact: true,
                  onTap: _pickCustomRange,
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(const ServiceOrdersFilter.mainDefault());
                      },
                      child: const Text('Restablecer'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final effectivePreset =
                            _datePreset == ServiceOrdersDatePreset.custom &&
                                _customRange == null
                            ? ServiceOrdersDatePreset.all
                            : _datePreset;
                        Navigator.of(context).pop(
                          ServiceOrdersFilter(
                            datePreset: effectivePreset,
                            completionFilter: _completionFilter,
                            statuses: _statuses,
                            serviceTypes: _serviceTypes,
                            creatorIds: _creatorIds,
                            technicianIds: _technicianIds,
                            customRange:
                                effectivePreset ==
                                    ServiceOrdersDatePreset.custom
                                ? _customRange
                                : null,
                          ),
                        );
                      },
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
      helpText: 'Selecciona el rango',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _customRange = picked;
      _datePreset = ServiceOrdersDatePreset.custom;
    });
  }

  String _selectionSummary({
    required Set<String> selectedIds,
    required List<_FilterUserOption> options,
  }) {
    if (selectedIds.isEmpty) {
      return 'Todos';
    }
    if (selectedIds.length == 1) {
      for (final option in options) {
        if (selectedIds.contains(option.id)) {
          return option.label;
        }
      }
    }
    return '${selectedIds.length} seleccionados';
  }

  Future<Set<String>?> _pickUserOptions({
    required String title,
    required List<_FilterUserOption> options,
    required Set<String> selectedIds,
    required Color accent,
  }) async {
    return showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _UserSelectionSheet(
        title: title,
        options: options,
        selectedIds: selectedIds,
        accent: accent,
      ),
    );
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.selectedCount, required this.onClose});

  final int selectedCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary.withValues(alpha: 0.12),
            colorScheme.tertiary.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Filtros',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  selectedCount == 0 ? 'Base' : '$selectedCount activos',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactSection extends StatelessWidget {
  const _CompactSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _ChoiceFilterTile extends StatelessWidget {
  const _ChoiceFilterTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isCompact = compact;
    return InkWell(
      borderRadius: BorderRadius.circular(isCompact ? 999 : 18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 11 : 14,
          vertical: isCompact ? 7 : 12,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: isCompact ? 0.08 : 0.1)
              : isCompact
              ? Colors.transparent
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(isCompact ? 999 : 18),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: isCompact ? 0.30 : 0.36)
                : colorScheme.outlineVariant.withValues(
                    alpha: isCompact ? 0.9 : 1,
                  ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isCompact ? 14 : 18,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: isCompact ? 5 : 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: isCompact ? 12.2 : null,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySelectorTile extends StatelessWidget {
  const _SummarySelectorTile({
    required this.label,
    required this.summary,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String summary;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _UserSelectionSheet extends StatefulWidget {
  const _UserSelectionSheet({
    required this.title,
    required this.options,
    required this.selectedIds,
    required this.accent,
  });

  final String title;
  final List<_FilterUserOption> options;
  final Set<String> selectedIds;
  final Color accent;

  @override
  State<_UserSelectionSheet> createState() => _UserSelectionSheetState();
}

class _UserSelectionSheetState extends State<_UserSelectionSheet> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = {...widget.selectedIds};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedIds.clear();
                    });
                  },
                  child: const Text('Limpiar'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: widget.options
                      .map(
                        (option) => _IdentityFilterChip(
                          option: option,
                          selected: _selectedIds.contains(option.id),
                          accent: widget.accent,
                          compact: true,
                          onTap: () {
                            setState(() {
                              if (_selectedIds.contains(option.id)) {
                                _selectedIds.remove(option.id);
                              } else {
                                _selectedIds.add(option.id);
                              }
                            });
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(_selectedIds),
                    child: Text(
                      _selectedIds.isEmpty ? 'Aplicar todos' : 'Aplicar',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityFilterChip extends StatelessWidget {
  const _IdentityFilterChip({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.compact = false,
  });

  final _FilterUserOption option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: compact ? 180 : 220,
        padding: EdgeInsets.all(compact ? 10 : 12),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.1)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.4)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: compact ? 16 : 18,
              backgroundColor: accent.withValues(alpha: selected ? 0.22 : 0.12),
              child: Text(
                option.initials,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 12 : null,
                ),
              ),
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: selected ? accent : colorScheme.onSurface,
                      fontSize: compact ? 13 : null,
                    ),
                  ),
                  SizedBox(height: compact ? 1 : 2),
                  Text(
                    option.roleLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: compact ? 11 : null,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

class _CustomDateRangeBanner extends StatelessWidget {
  const _CustomDateRangeBanner({
    required this.range,
    required this.onTap,
    this.compact = false,
  });

  final DateTimeRange? range;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final label = range == null
        ? 'Selecciona un rango'
        : '${DateFormat('dd/MM/yyyy').format(range!.start)} - ${DateFormat('dd/MM/yyyy').format(range!.end)}';

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(compact ? 12 : 14),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range_rounded, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : null,
                ),
              ),
            ),
            TextButton(onPressed: onTap, child: const Text('Cambiar')),
          ],
        ),
      ),
    );
  }
}

class _OperationsControlPanel extends StatelessWidget {
  const _OperationsControlPanel({
    required this.filter,
    required this.activeCount,
    required this.refreshing,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onOpenFilters,
    required this.onCollapse,
    required this.onToggleStatus,
    required this.onToggleServiceType,
    required this.onReset,
    this.collapseIcon = Icons.keyboard_arrow_up_rounded,
    this.collapseTooltip = 'Ocultar panel',
  });

  final ServiceOrdersFilter filter;
  final int activeCount;
  final bool refreshing;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback? onCollapse;
  final ValueChanged<ServiceOrderStatus> onToggleStatus;
  final ValueChanged<ServiceOrderType> onToggleServiceType;
  final VoidCallback? onReset;
  final IconData collapseIcon;
  final String collapseTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = _shouldUseOperationsDesktopLayout(
      MediaQuery.sizeOf(context).width,
    );
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE d MMM', 'es_DO').format(now);
    final timeLabel = DateFormat('h:mm a', 'es_DO').format(now);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.surface, colorScheme.surfaceContainerLowest],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _PanelMetaPill(
                          icon: Icons.dashboard_customize_rounded,
                          text: filter.summaryLabel,
                          accent: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        _PanelMetaPill(
                          icon: Icons.calendar_today_outlined,
                          text: _capitalize(dateLabel),
                        ),
                        const SizedBox(width: 6),
                        _PanelMetaPill(
                          icon: Icons.schedule_rounded,
                          text: timeLabel,
                        ),
                        const SizedBox(width: 6),
                        _PanelMetaPill(
                          icon: Icons.layers_outlined,
                          text: '$activeCount activas',
                        ),
                        if (refreshing) ...[
                          const SizedBox(width: 6),
                          _PanelMetaPill(
                            icon: Icons.sync_rounded,
                            text: 'Sincronizando',
                            accent: colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (onReset != null)
                  IconButton(
                    tooltip: 'Limpiar filtros',
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    onPressed: onReset,
                    icon: Icon(
                      Icons.restart_alt_rounded,
                      color: colorScheme.onSurfaceVariant,
                      size: 19,
                    ),
                  ),
                if (onCollapse != null)
                  IconButton(
                    tooltip: collapseTooltip,
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    onPressed: onCollapse,
                    icon: Icon(
                      collapseIcon,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _OperationsQuickSearchField(
              controller: searchController,
              onChanged: onSearchChanged,
              onClear: onClearSearch,
              onOpenFilters: onOpenFilters,
              hasActiveFilters: filter.hasActiveFilters,
              hintText: 'Buscar por cliente, orden o técnico',
            ),
            const SizedBox(height: 8),
            _CompactFilterLine<ServiceOrderStatus>(
              label: '',
              items: ServiceOrderStatus.values,
              isSelected: filter.statuses.contains,
              onToggle: onToggleStatus,
              labelBuilder: (status) => status.label,
              colorBuilder: (status) => status.color,
              centered: isDesktop,
            ),
            const SizedBox(height: 6),
            _CompactFilterLine<ServiceOrderType>(
              label: '',
              items: ServiceOrderType.values,
              isSelected: filter.serviceTypes.contains,
              onToggle: onToggleServiceType,
              labelBuilder: (serviceType) => serviceType.label,
              centered: isDesktop,
            ),
            if (filter.insightChips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filter.insightChips
                    .map((chip) => _FilterInsightBadge(label: chip))
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CollapsedOperationsPanelToggle extends StatelessWidget {
  const _CollapsedOperationsPanelToggle({
    required this.activeCount,
    required this.hasActiveFilters,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onOpenFilters,
    required this.onTap,
  });

  final int activeCount;
  final bool hasActiveFilters;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final preferredSearchWidth = screenWidth >= 900
        ? 340.0
        : screenWidth >= 600
        ? 280.0
        : 220.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: preferredSearchWidth),
                  child: _OperationsQuickSearchField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    onClear: onClearSearch,
                    onOpenFilters: onOpenFilters,
                    hasActiveFilters: hasActiveFilters,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.78),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withValues(alpha: 0.025),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.dashboard_customize_outlined,
                        size: 15,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Panel',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.1,
                            ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: hasActiveFilters
                              ? colorScheme.primary.withValues(alpha: 0.10)
                              : colorScheme.surfaceContainerHighest.withValues(
                                  alpha: 0.45,
                                ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasActiveFilters
                                  ? Icons.filter_alt_outlined
                                  : Icons.layers_outlined,
                              size: 11,
                              color: hasActiveFilters
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasActiveFilters ? 'Filtros' : '$activeCount',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: hasActiveFilters
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DesktopOperationsFilterSidebar extends StatefulWidget {
  const _DesktopOperationsFilterSidebar({
    required this.filter,
    required this.activeCount,
    required this.refreshing,
    required this.searchController,
    required this.availableCreators,
    required this.availableTechnicians,
    required this.visibleOrders,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onReset,
    required this.onFilterChanged,
    required this.onPickCustomRange,
  });

  final ServiceOrdersFilter filter;
  final int activeCount;
  final bool refreshing;
  final TextEditingController searchController;
  final List<_FilterUserOption> availableCreators;
  final List<_FilterUserOption> availableTechnicians;
  final List<ServiceOrderModel> visibleOrders;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onReset;
  final ValueChanged<ServiceOrdersFilter> onFilterChanged;
  final Future<DateTimeRange?> Function() onPickCustomRange;

  @override
  State<_DesktopOperationsFilterSidebar> createState() =>
      _DesktopOperationsFilterSidebarState();
}

class _DesktopOperationsFilterSidebarState
    extends State<_DesktopOperationsFilterSidebar> {
  final ScrollController _scrollController = ScrollController();

  ServiceOrdersFilter get filter => widget.filter;
  int get activeCount => widget.activeCount;
  bool get refreshing => widget.refreshing;
  TextEditingController get searchController => widget.searchController;
  List<_FilterUserOption> get availableCreators => widget.availableCreators;
  List<_FilterUserOption> get availableTechnicians =>
      widget.availableTechnicians;
  ValueChanged<String> get onSearchChanged => widget.onSearchChanged;
  VoidCallback get onClearSearch => widget.onClearSearch;
  VoidCallback get onReset => widget.onReset;
  ValueChanged<ServiceOrdersFilter> get onFilterChanged =>
      widget.onFilterChanged;
  Future<DateTimeRange?> Function() get onPickCustomRange =>
      widget.onPickCustomRange;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleStatus(ServiceOrderStatus status) {
    final next = {...filter.statuses};
    if (next.contains(status)) {
      next.remove(status);
    } else {
      next.add(status);
    }
    onFilterChanged(filter.copyWith(statuses: next));
  }

  void _toggleServiceType(ServiceOrderType serviceType) {
    final next = {...filter.serviceTypes};
    if (next.contains(serviceType)) {
      next.remove(serviceType);
    } else {
      next.add(serviceType);
    }
    onFilterChanged(filter.copyWith(serviceTypes: next));
  }

  void _toggleCreator(String id) {
    final next = {...filter.creatorIds};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onFilterChanged(filter.copyWith(creatorIds: next));
  }

  void _toggleTechnician(String id) {
    final next = {...filter.technicianIds};
    if (next.contains(id)) {
      next.remove(id);
    } else {
      next.add(id);
    }
    onFilterChanged(filter.copyWith(technicianIds: next));
  }

  Future<void> _selectDatePreset(ServiceOrdersDatePreset preset) async {
    if (preset != ServiceOrdersDatePreset.custom) {
      onFilterChanged(
        filter.copyWith(datePreset: preset, clearCustomRange: true),
      );
      return;
    }
    final range = await onPickCustomRange();
    if (range == null) return;
    onFilterChanged(
      filter.copyWith(
        datePreset: ServiceOrdersDatePreset.custom,
        customRange: range,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canReset =
        filter.hasActiveFilters || searchController.text.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.78),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(-6, 0),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colorScheme.primary, colorScheme.tertiary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.tune_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Filtros de operaciones',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              refreshing
                                  ? 'Sincronizando · $activeCount visibles'
                                  : '$activeCount órdenes visibles',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _OperationsQuickSearchField(
                          controller: searchController,
                          onChanged: onSearchChanged,
                          onClear: onClearSearch,
                          onOpenFilters: null,
                          hasActiveFilters: filter.hasActiveFilters,
                          hintText: 'Buscar orden, cliente, técnico',
                        ),
                      ),
                      const SizedBox(width: 10),
                      _DesktopDatePresetButton(
                        selectedPreset: filter.datePreset,
                        onSelected: _selectDatePreset,
                      ),
                    ],
                  ),
                  if (filter.datePreset == ServiceOrdersDatePreset.custom)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      child: _CustomDateRangeBanner(
                        range: filter.customRange,
                        compact: true,
                        onTap: () =>
                            _selectDatePreset(ServiceOrdersDatePreset.custom),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PrimaryScrollController(
                controller: _scrollController,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    primary: true,
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SidebarFilterSection(
                                title: 'Estado',
                                child: Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: ServiceOrderStatus.values
                                      .map(
                                        (status) => _CompactFilterChip(
                                          label: status.label,
                                          selected: filter.statuses.contains(
                                            status,
                                          ),
                                          accent: status.color,
                                          onTap: () => _toggleStatus(status),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                              _SidebarFilterSection(
                                title: 'Servicio',
                                child: Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: ServiceOrderType.values
                                      .map(
                                        (serviceType) => _CompactFilterChip(
                                          label: serviceType.label,
                                          selected: filter.serviceTypes
                                              .contains(serviceType),
                                          onTap: () =>
                                              _toggleServiceType(serviceType),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              ),
                              _SidebarFilterSection(
                                title: 'Usuarios / vendedores',
                                badge: '${availableCreators.length}',
                                child: availableCreators.isEmpty
                                    ? const _SidebarEmptyFilterText(
                                        text: 'No hay usuarios disponibles',
                                      )
                                    : _SidebarIdentityGrid(
                                        options: availableCreators,
                                        selectedIds: filter.creatorIds,
                                        accent: colorScheme.primary,
                                        onTap: _toggleCreator,
                                      ),
                              ),
                              _SidebarFilterSection(
                                title: 'Técnicos',
                                badge: '${availableTechnicians.length}',
                                child: availableTechnicians.isEmpty
                                    ? const _SidebarEmptyFilterText(
                                        text: 'No hay técnicos asignados',
                                      )
                                    : _SidebarIdentityGrid(
                                        options: availableTechnicians,
                                        selectedIds: filter.technicianIds,
                                        accent: const Color(0xFF0F766E),
                                        onTap: _toggleTechnician,
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _OperationsAdminTotalsPanel(
                                visibleOrders: widget.visibleOrders,
                                colorScheme: colorScheme,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: canReset ? onReset : null,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('Restablecer filtros'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDatePresetButton extends StatelessWidget {
  const _DesktopDatePresetButton({
    required this.selectedPreset,
    required this.onSelected,
  });

  final ServiceOrdersDatePreset selectedPreset;
  final ValueChanged<ServiceOrdersDatePreset> onSelected;

  String get _label {
    switch (selectedPreset) {
      case ServiceOrdersDatePreset.today:
        return 'Hoy';
      case ServiceOrdersDatePreset.yesterday:
        return 'Ayer';
      case ServiceOrdersDatePreset.thisWeek:
        return 'Semana';
      case ServiceOrdersDatePreset.currentPayPeriod:
        return 'Quincena actual';
      case ServiceOrdersDatePreset.previousPayPeriod:
        return 'Quincena pasada';
      case ServiceOrdersDatePreset.custom:
        return 'Rango';
      case ServiceOrdersDatePreset.all:
        return 'Todas';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return PopupMenuButton<ServiceOrdersDatePreset>(
      tooltip: 'Seleccionar fecha',
      onSelected: onSelected,
      itemBuilder: (context) => [
        const PopupMenuItem<ServiceOrdersDatePreset>(
          value: ServiceOrdersDatePreset.today,
          child: Text('Hoy'),
        ),
        const PopupMenuItem<ServiceOrdersDatePreset>(
          value: ServiceOrdersDatePreset.yesterday,
          child: Text('Ayer'),
        ),
        const PopupMenuItem<ServiceOrdersDatePreset>(
          value: ServiceOrdersDatePreset.thisWeek,
          child: Text('Semana'),
        ),
        const PopupMenuItem<ServiceOrdersDatePreset>(
          value: ServiceOrdersDatePreset.currentPayPeriod,
          child: Text('Quincena actual'),
        ),
        const PopupMenuItem<ServiceOrdersDatePreset>(
          value: ServiceOrdersDatePreset.previousPayPeriod,
          child: Text('Quincena pasada'),
        ),
        const PopupMenuItem<ServiceOrdersDatePreset>(
          value: ServiceOrdersDatePreset.custom,
          child: Text('Rango'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'Fecha · $_label',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarFilterSection extends StatelessWidget {
  const _SidebarFilterSection({
    required this.title,
    required this.child,
    this.badge,
  });

  final String title;
  final Widget child;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if ((badge ?? '').trim().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}

class _SidebarIdentityGrid extends StatelessWidget {
  const _SidebarIdentityGrid({
    required this.options,
    required this.selectedIds,
    required this.accent,
    required this.onTap,
  });

  final List<_FilterUserOption> options;
  final Set<String> selectedIds;
  final Color accent;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final itemWidth = maxWidth >= 220 ? (maxWidth - 8) / 2 : maxWidth;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map(
                (option) => SizedBox(
                  width: itemWidth,
                  child: _SidebarIdentityOption(
                    option: option,
                    selected: selectedIds.contains(option.id),
                    accent: accent,
                    onTap: () => onTap(option.id),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _SidebarIdentityOption extends StatelessWidget {
  const _SidebarIdentityOption({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final _FilterUserOption option;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.09)
                : colorScheme.surfaceContainerLowest.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.38)
                  : colorScheme.outlineVariant.withValues(alpha: 0.86),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: selected ? 0.18 : 0.10),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  option.initials,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: selected ? accent : colorScheme.onSurface,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      option.roleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: selected ? 1 : 0,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarEmptyFilterText extends StatelessWidget {
  const _SidebarEmptyFilterText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _OperationsQuickSearchField extends StatelessWidget {
  const _OperationsQuickSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onOpenFilters,
    required this.hasActiveFilters,
    this.hintText = 'Buscar',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback? onOpenFilters;
  final bool hasActiveFilters;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasSearchText = controller.text.trim().isNotEmpty;
    final inputTextStyle = theme.textTheme.labelMedium?.copyWith(
      fontSize: 11.8,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.05,
      height: 1,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasActiveFilters
                ? colorScheme.primary.withValues(alpha: 0.44)
                : colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.014),
              blurRadius: 5,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 15,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.92),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  textInputAction: TextInputAction.search,
                  style: inputTextStyle,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hintText,
                    hintStyle: inputTextStyle?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasSearchText)
                    _SearchFieldIconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: onClear,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (hasSearchText) const SizedBox(width: 2),
                  if (onOpenFilters != null) ...[
                    Container(
                      width: 1,
                      height: 12,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.38),
                    ),
                    const SizedBox(width: 4),
                    _SearchFieldIconButton(
                      tooltip: 'Filtros',
                      onPressed: onOpenFilters,
                      size: 30,
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            Icons.filter_alt_outlined,
                            size: 17,
                            color: hasActiveFilters
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          if (hasActiveFilters)
                            Positioned(
                              right: -1,
                              top: -1,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchFieldIconButton extends StatelessWidget {
  const _SearchFieldIconButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
    this.size = 22,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        splashRadius: 13,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: icon,
      ),
    );

    if (onPressed == null) {
      return IgnorePointer(child: button);
    }
    return button;
  }
}

class _FilterInsightBadge extends StatelessWidget {
  const _FilterInsightBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

class _CompactFilterLine<T> extends StatelessWidget {
  const _CompactFilterLine({
    required this.label,
    required this.items,
    required this.isSelected,
    required this.onToggle,
    required this.labelBuilder,
    this.centered = false,
    this.colorBuilder,
  });

  final String label;
  final List<T> items;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onToggle;
  final String Function(T value) labelBuilder;
  final bool centered;
  final Color Function(T value)? colorBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasLabel = label.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (hasLabel)
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        if (hasLabel) const SizedBox(width: 2),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final chips = items
                  .map((item) {
                    final selected = isSelected(item);
                    final accent = colorBuilder?.call(item);
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _CompactFilterChip(
                        label: labelBuilder(item),
                        selected: selected,
                        accent: accent,
                        onTap: () => onToggle(item),
                      ),
                    );
                  })
                  .toList(growable: false);

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: centered
                        ? MainAxisAlignment.center
                        : MainAxisAlignment.start,
                    children: chips,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  const _CompactFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final baseColor = accent ?? Colors.white;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? baseColor.withValues(alpha: accent == null ? 0.12 : 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? baseColor.withValues(alpha: accent == null ? 0.36 : 0.48)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected
                ? (accent ?? Theme.of(context).colorScheme.primary)
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _CreateOrderFab extends StatelessWidget {
  const _CreateOrderFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Agregar orden de servicio',
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.12),
                colorScheme.primary,
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.30),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 62,
              height: 62,
              child: Center(
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.add_business_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopOperationsOverviewPanel extends StatelessWidget {
  const _DesktopOperationsOverviewPanel({
    required this.filter,
    required this.activeCount,
    required this.pendingCount,
    required this.inProgressCount,
    required this.pausedCount,
    required this.gpsReadyCount,
    required this.scheduledCount,
    required this.refreshing,
  });

  final ServiceOrdersFilter filter;
  final int activeCount;
  final int pendingCount;
  final int inProgressCount;
  final int pausedCount;
  final int gpsReadyCount;
  final int scheduledCount;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final dateLabel = DateFormat('EEE d MMM · h:mm a', 'es_DO').format(now);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PanelMetaPill(icon: Icons.dashboard_outlined, text: 'Resumen'),
            _PanelMetaPill(
              icon: Icons.tune_rounded,
              text: filter.summaryLabel,
              accent: colorScheme.primary,
            ),
            _PanelMetaPill(
              icon: Icons.calendar_month_rounded,
              text: _capitalize(dateLabel),
            ),
            _PanelMetaPill(
              icon: Icons.layers_outlined,
              text: '$activeCount activas',
            ),
            _PanelMetaPill(
              icon: Icons.pending_actions_rounded,
              text: '$pendingCount pendientes',
              accent: const Color(0xFFD97706),
            ),
            _PanelMetaPill(
              icon: Icons.construction_rounded,
              text: '$inProgressCount en proceso',
              accent: const Color(0xFF0F6CBD),
            ),
            _PanelMetaPill(
              icon: Icons.pause_circle_outline_rounded,
              text: '$pausedCount en pausa',
              accent: const Color(0xFFB7791F),
            ),
            _PanelMetaPill(
              icon: Icons.location_on_outlined,
              text: '$gpsReadyCount con GPS',
              accent: const Color(0xFF047857),
            ),
            _PanelMetaPill(
              icon: Icons.event_available_rounded,
              text: '$scheduledCount agendadas',
              accent: const Color(0xFF7C3AED),
            ),
            if (refreshing)
              _PanelMetaPill(
                icon: Icons.sync_rounded,
                text: 'Sincronizando',
                accent: colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceOrderListCard extends StatelessWidget {
  const _ServiceOrderListCard({
    required this.order,
    required this.client,
    required this.clientName,
    required this.creatorName,
    required this.technicianName,
    required this.sellerConversationUri,
    required this.supportConversationUri,
    required this.onTap,
    required this.statusBusy,
    required this.creatingNewOrder,
    required this.isTechnician,
    required this.canPromoteStatus,
    this.onCreateNewOrder,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
  });

  final ServiceOrderModel order;
  final ClienteModel? client;
  final String clientName;
  final String creatorName;
  final String technicianName;
  final Uri? sellerConversationUri;
  final Uri? supportConversationUri;
  final VoidCallback onTap;
  final bool statusBusy;
  final bool creatingNewOrder;
  final bool isTechnician;
  final bool canPromoteStatus;
  final VoidCallback? onCreateNewOrder;
  final ValueChanged<ServiceOrderStatus>? onChangeStatus;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = _shouldUseOperationsDesktopLayout(
      MediaQuery.sizeOf(context).width,
    );
    final locationUrl = client?.locationUrl;
    final locationPreview = parseClientLocationPreview(locationUrl);
    final locationUri = buildClientNavigationUri(locationPreview, locationUrl);
    final serviceAt = order.scheduledFor?.toLocal();
    final lastStatusAt = (order.lastStatusChangedAt ?? order.updatedAt)
        .toLocal();
    final topLineText = serviceAt == null
        ? 'Sin fecha programada'
        : formatServiceScheduledDateTime(serviceAt);
    final lastStatusLineText = formatLastStatusMoment(
      statusLabel: order.status.label,
      changedAt: lastStatusAt,
    );
    final serviceBucket = resolveServiceScheduleDayBucket(serviceAt);
    final priorityStyle = _resolveServiceTypePriorityStyle(order.serviceType);
    final creatorDisplayName = creatorName.trim();
    final creatorFirstName = _extractFirstName(creatorDisplayName);
    final hasCreatorName = creatorDisplayName.isNotEmpty;
    final clientDisplayName = clientName.trim();
    final clientPhone = (client?.telefono ?? '').trim();
    final serviceCityLabel = _extractServiceCity(
      address: client?.direccion,
      locationUrl: client?.locationUrl,
    );
    final callUri = _buildPhoneUri(clientPhone);
    final whatsappUri = _buildWhatsAppUri(clientPhone);
    final technicianActionConfig = ServiceOrderQuickActionsConfig(
      clientCallUri: callUri,
      clientWhatsAppUri: whatsappUri,
      locationUri: locationUri,
      sellerConversationUri: sellerConversationUri,
      supportConversationUri: supportConversationUri,
    );

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ThinServiceScheduleLine(
            label: topLineText,
            bucket: serviceBucket,
            compact: false,
            trailing: _AnimatedServiceOrderStatusBadge(
              status: order.status,
              compact: true,
            ),
          ),
          _DesktopServiceOrderLine(
            order: order,
            clientDisplayName: clientDisplayName,
            clientPhone: clientPhone,
            creatorFirstName: creatorFirstName,
            hasCreatorName: hasCreatorName,
            technicianName: technicianName,
            lastStatusLabel: lastStatusLineText,
            locationUri: locationUri,
            callUri: callUri,
            whatsappUri: whatsappUri,
            priorityStyle: priorityStyle,
            technicianActionConfig: technicianActionConfig,
            statusBusy: statusBusy,
            creatingNewOrder: creatingNewOrder,
            isTechnician: isTechnician,
            canPromoteStatus: canPromoteStatus,
            onTap: onTap,
            onChangeStatus: onChangeStatus,
            onCreateNewOrder: onCreateNewOrder,
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThinServiceScheduleLine(
          label: topLineText,
          bucket: serviceBucket,
          compact: true,
          trailing: _AnimatedServiceOrderStatusBadge(
            status: order.status,
            compact: true,
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  priorityStyle.backgroundTint.withValues(alpha: 0.36),
                  theme.colorScheme.surface,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.022),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: priorityStyle.borderColor.withValues(alpha: 0.48),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 3,
                          height: 26,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: priorityStyle.edgeColor.withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              if (technicianName.trim().isNotEmpty) ...[
                                Expanded(
                                  child: Text(
                                    'Técnico: ${technicianName.trim()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      fontSize: 11,
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      height: 1,
                                    ),
                                  ),
                                ),
                                if (hasCreatorName) ...[
                                  const SizedBox(width: 6),
                                  RichText(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: 'V. ',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                fontSize: 10,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w500,
                                                height: 1,
                                              ),
                                        ),
                                        TextSpan(
                                          text: creatorFirstName.toUpperCase(),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                fontSize: 10,
                                                color:
                                                    theme.colorScheme.primary,
                                                fontWeight: FontWeight.w800,
                                                height: 1,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ] else if (hasCreatorName)
                                Expanded(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.storefront_outlined,
                                        size: 11,
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.85),
                                      ),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: 'Vendido por ',
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontSize: 11,
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      height: 1,
                                                    ),
                                              ),
                                              TextSpan(
                                                text: creatorFirstName
                                                    .toUpperCase(),
                                                style: theme
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontSize: 11,
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      height: 1,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Último estado: $lastStatusLineText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Transform.translate(
                                offset: const Offset(0, -1),
                                child: Text(
                                  clientDisplayName.isEmpty
                                      ? 'Cliente sin nombre'
                                      : clientDisplayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.1,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${order.serviceType.label} - ${order.category.label}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            letterSpacing: 0.12,
                                            height: 1,
                                          ),
                                    ),
                                  ),
                                  if (serviceCityLabel != null) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      serviceCityLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w700,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                            letterSpacing: 0.28,
                                            height: 1,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _MobileOrderActionsButton(
                          order: order,
                          statusBusy: statusBusy,
                          creatingNewOrder: creatingNewOrder,
                          canPromoteStatus: canPromoteStatus,
                          isTechnician: isTechnician,
                          callUri: callUri,
                          whatsappUri: whatsappUri,
                          locationUri: locationUri,
                          technicianActionConfig: technicianActionConfig,
                          onCreateNewOrder: onCreateNewOrder,
                          onChangeStatus: onChangeStatus,
                          onEdit: onEdit,
                          onDelete: onDelete,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopServiceOrderLine extends ConsumerWidget {
  const _DesktopServiceOrderLine({
    required this.order,
    required this.clientDisplayName,
    required this.clientPhone,
    required this.creatorFirstName,
    required this.hasCreatorName,
    required this.technicianName,
    required this.lastStatusLabel,
    required this.locationUri,
    required this.callUri,
    required this.whatsappUri,
    required this.priorityStyle,
    required this.technicianActionConfig,
    required this.statusBusy,
    required this.creatingNewOrder,
    required this.isTechnician,
    required this.canPromoteStatus,
    required this.onTap,
    this.onChangeStatus,
    this.onCreateNewOrder,
    this.onEdit,
    this.onDelete,
  });

  final ServiceOrderModel order;
  final String clientDisplayName;
  final String clientPhone;
  final String creatorFirstName;
  final bool hasCreatorName;
  final String technicianName;
  final String lastStatusLabel;
  final Uri? locationUri;
  final Uri? callUri;
  final Uri? whatsappUri;
  final _ServiceTypePriorityStyle priorityStyle;
  final ServiceOrderQuickActionsConfig technicianActionConfig;
  final bool statusBusy;
  final bool creatingNewOrder;
  final bool isTechnician;
  final bool canPromoteStatus;
  final VoidCallback onTap;
  final ValueChanged<ServiceOrderStatus>? onChangeStatus;
  final VoidCallback? onCreateNewOrder;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final assignedLabel = technicianName.trim();
    final detailSummary = _firstMeaningfulText(
      order.extraRequirements,
      order.technicalNote,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: priorityStyle.backgroundTint.withValues(alpha: 0.26),
        child: Ink(
          height: 84,
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              priorityStyle.backgroundTint.withValues(alpha: 0.16),
              colorScheme.surface,
            ),
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.74),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(width: 4, color: priorityStyle.edgeColor),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${_compactOrderId(order.id)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Último: $lastStatusLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 9.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: _DesktopLineTextBlock(
                  title: clientDisplayName.isEmpty
                      ? 'Cliente sin nombre'
                      : clientDisplayName,
                  subtitle: detailSummary ?? clientPhone,
                  icon: Icons.business_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: _DesktopLineTextBlock(
                  title: '${order.serviceType.label} · ${order.category.label}',
                  subtitle: detailSummary ?? clientPhone,
                  icon: Icons.construction_rounded,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: _DesktopLineTextBlock(
                  title: assignedLabel.isEmpty
                      ? 'Sin técnico asignado'
                      : 'Técnico: $assignedLabel',
                  subtitle: hasCreatorName
                      ? 'V. ${creatorFirstName.toUpperCase()}'
                      : '',
                  icon: Icons.engineering_rounded,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (callUri != null)
                    _ContactIconButton(
                      icon: Icons.call_outlined,
                      tooltip: 'Llamar cliente',
                      onTap: () => safeOpenUrl(context, callUri!),
                      size: 30,
                    ),
                  if (whatsappUri != null) ...[
                    const SizedBox(width: 5),
                    _ContactIconButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      tooltip: 'WhatsApp cliente',
                      onTap: () => safeOpenWhatsApp(context, whatsappUri!),
                      size: 30,
                    ),
                  ],
                  if (locationUri != null) ...[
                    const SizedBox(width: 5),
                    _ContactIconButton(
                      icon: Icons.location_searching_rounded,
                      tooltip: 'Abrir GPS',
                      onTap: () => safeOpenUrl(context, locationUri!),
                      size: 30,
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 8),
              if (onChangeStatus != null)
                _InlineStatusButton(
                  order: order,
                  busy: statusBusy,
                  isTechnician: isTechnician,
                  canPromoteStatus: canPromoteStatus,
                  onSelected: onChangeStatus!,
                ),
              if (onCreateNewOrder != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Crear nueva orden desde esta',
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: creatingNewOrder ? null : onCreateNewOrder,
                    icon: creatingNewOrder
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                  ),
                ),
              ],
              if (isTechnician) ...[
                const SizedBox(width: 6),
                _TechnicianQuickActionButton(
                  order: order,
                  actionConfig: technicianActionConfig,
                ),
              ] else if (onEdit != null) ...[
                const SizedBox(width: 4),
                _OrderActionsMenu(
                  busy: statusBusy,
                  onEdit: onEdit!,
                  onDelete: onDelete,
                ),
              ],
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopLineTextBlock extends StatelessWidget {
  const _DesktopLineTextBlock({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 15, color: colorScheme.primary),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.08,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle.isEmpty ? '' : subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceTypePriorityStyle {
  const _ServiceTypePriorityStyle({
    required this.edgeColor,
    required this.borderColor,
    required this.backgroundTint,
  });

  final Color edgeColor;
  final Color borderColor;
  final Color backgroundTint;
}

class _ServiceScheduleVisualStyle {
  const _ServiceScheduleVisualStyle({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

_ServiceScheduleVisualStyle _serviceScheduleVisualStyle(
  ServiceScheduleDayBucket bucket,
) {
  switch (bucket) {
    case ServiceScheduleDayBucket.unscheduled:
      return const _ServiceScheduleVisualStyle(
        background: Color(0xFFF4F6F8),
        border: Color(0xFFD5DCE3),
        foreground: Color(0xFF4C6072),
      );
    case ServiceScheduleDayBucket.today:
      return const _ServiceScheduleVisualStyle(
        background: Color(0xFFE8F3FF),
        border: Color(0xFF8CB9E8),
        foreground: Color(0xFF0F4E8A),
      );
    case ServiceScheduleDayBucket.overdue:
      return const _ServiceScheduleVisualStyle(
        background: Color(0xFFFFF1F0),
        border: Color(0xFFF2B8B5),
        foreground: Color(0xFF9F2D2A),
      );
    case ServiceScheduleDayBucket.tomorrow:
    case ServiceScheduleDayBucket.future:
      return const _ServiceScheduleVisualStyle(
        background: Color(0xFFEFF6FF),
        border: Color(0xFFB2C8E7),
        foreground: Color(0xFF1E4F87),
      );
    case ServiceScheduleDayBucket.yesterday:
    case ServiceScheduleDayBucket.past:
      return const _ServiceScheduleVisualStyle(
        background: Color(0xFFFFF8E6),
        border: Color(0xFFE8CF91),
        foreground: Color(0xFF8A5B00),
      );
  }
}

class _ThinServiceScheduleLine extends StatelessWidget {
  const _ThinServiceScheduleLine({
    required this.label,
    required this.bucket,
    required this.compact,
    this.trailing,
  });

  final String label;
  final ServiceScheduleDayBucket bucket;
  final bool compact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = _serviceScheduleVisualStyle(bucket);
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 2 : 6, 0, compact ? 2 : 6, 2),
      child: Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            size: compact ? 10 : 11,
            color: style.foreground.withValues(alpha: 0.72),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Servicio: $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: compact ? 8.7 : 9.2,
                height: 1,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.05,
                color: style.foreground.withValues(alpha: 0.72),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

_ServiceTypePriorityStyle _resolveServiceTypePriorityStyle(
  ServiceOrderType type,
) {
  switch (type) {
    case ServiceOrderType.instalacion:
      return const _ServiceTypePriorityStyle(
        edgeColor: Color(0xFFD97706),
        borderColor: Color(0xFFE7B15D),
        backgroundTint: Color(0xFFFFF4DB),
      );
    case ServiceOrderType.mantenimiento:
      return const _ServiceTypePriorityStyle(
        edgeColor: Color(0xFF1F8A5B),
        borderColor: Color(0xFF78C79E),
        backgroundTint: Color(0xFFEAF8F0),
      );
    case ServiceOrderType.levantamiento:
    case ServiceOrderType.garantia:
      return const _ServiceTypePriorityStyle(
        edgeColor: Color(0xFF8A94A6),
        borderColor: Color(0xFFD4DAE3),
        backgroundTint: Color(0xFFF6F8FB),
      );
  }
}

String? _extractServiceCity({String? address, String? locationUrl}) {
  final normalizedAddress = (address ?? '').trim();
  final candidates = <String>[
    if (normalizedAddress.isNotEmpty)
      ...normalizedAddress.split(RegExp(r'[,;|\-]')),
    if ((locationUrl ?? '').trim().isNotEmpty)
      ...Uri.decodeFull(locationUrl!.trim()).split(RegExp(r'[/,;|\-]')),
  ];

  const knownCities = <String>[
    'higuey',
    'higüey',
    'bavaro',
    'bávaro',
    'punta cana',
    'veron',
    'verón',
    'la romana',
    'santo domingo',
    'santiago',
    'san pedro de macoris',
    'san pedro de macorís',
    'bonao',
    'moca',
    'salvaleon de higuey',
    'salvaleón de higüey',
  ];

  for (final raw in candidates) {
    final chunk = raw.trim();
    if (chunk.isEmpty) continue;
    final lowered = chunk.toLowerCase();
    for (final city in knownCities) {
      if (lowered.contains(city)) {
        return city.toUpperCase().replaceAll('Ü', 'U');
      }
    }
  }

  if (normalizedAddress.isNotEmpty) {
    final parts = normalizedAddress
        .split(RegExp(r'[,;|]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isNotEmpty) {
      return parts.last.toUpperCase();
    }
  }

  return null;
}

class _MobileOrderActionsButton extends ConsumerStatefulWidget {
  const _MobileOrderActionsButton({
    required this.order,
    required this.statusBusy,
    required this.creatingNewOrder,
    required this.canPromoteStatus,
    required this.isTechnician,
    required this.callUri,
    required this.whatsappUri,
    required this.locationUri,
    required this.technicianActionConfig,
    this.onCreateNewOrder,
    this.onChangeStatus,
    this.onEdit,
    this.onDelete,
  });

  final ServiceOrderModel order;
  final bool statusBusy;
  final bool creatingNewOrder;
  final bool canPromoteStatus;
  final bool isTechnician;
  final Uri? callUri;
  final Uri? whatsappUri;
  final Uri? locationUri;
  final ServiceOrderQuickActionsConfig technicianActionConfig;
  final VoidCallback? onCreateNewOrder;
  final ValueChanged<ServiceOrderStatus>? onChangeStatus;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_MobileOrderActionsButton> createState() =>
      _MobileOrderActionsButtonState();
}

class _MobileOrderActionsButtonState
    extends ConsumerState<_MobileOrderActionsButton> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isTechnician = widget.isTechnician;
    final buttonBg = isTechnician
        ? Colors.white
        : Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.035),
            scheme.surface,
          );
    final buttonFg = isTechnician ? const Color(0xFF111827) : scheme.primary;
    final buttonBorder = isTechnician
        ? const Color(0xFFD8E3EE)
        : Color.alphaBlend(scheme.primary.withValues(alpha: 0.24), buttonBg);
    final buttonShadow = isTechnician
        ? const Color(0x2A8FA9C0)
        : scheme.primary.withValues(alpha: 0.12);
    final buttonKey = GlobalKey();
    return FilledButton.tonal(
      key: buttonKey,
      onPressed: () {
        if (widget.isTechnician) {
          showServiceOrderQuickActionsModal(
            context: context,
            ref: ref,
            orderId: widget.order.id,
            order: widget.order,
            presentation: ServiceOrderQuickActionsPresentation.mobileRightPanel,
            actionConfig: widget.technicianActionConfig,
            onOrderUpdated: () {
              ref.read(serviceOrdersListControllerProvider.notifier).refresh();
            },
          );
          return;
        }
        _showActionsMenu(context, ref, buttonKey);
      },
      style: FilledButton.styleFrom(
        minimumSize: const Size(108, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        elevation: isTechnician ? 5 : 1.6,
        shadowColor: buttonShadow,
        backgroundColor: buttonBg,
        foregroundColor: buttonFg,
        overlayColor: buttonFg.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: buttonBorder, width: 1),
        ),
        surfaceTintColor: isTechnician ? Colors.white : null,
      ),
      child: Text(
        widget.isTechnician ? 'Gestionar' : 'Acciones',
        style: theme.textTheme.labelLarge?.copyWith(
          fontSize: 12.6,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.08,
        ),
      ),
    );
  }

  Future<void> _showActionsMenu(
    BuildContext context,
    WidgetRef ref,
    GlobalKey buttonKey,
  ) async {
    final selected = await showMenu<_OrderMenuAction>(
      context: context,
      position: _menuPositionFromButton(context, buttonKey),
      items: [
        if (widget.onChangeStatus != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.changeStatus,
            child: _OrderMenuRow(
              icon: Icons.sync_alt_rounded,
              label: 'Cambiar estado',
              trailing: Icons.chevron_right_rounded,
            ),
          ),
        if (widget.onCreateNewOrder != null)
          PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.newOrder,
            enabled: !widget.creatingNewOrder,
            child: _OrderMenuRow(
              icon: Icons.add_circle_outline_rounded,
              label: widget.creatingNewOrder ? 'Creando...' : 'Nueva orden',
            ),
          ),
        if (widget.callUri != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.call,
            child: _OrderMenuRow(icon: Icons.call_outlined, label: 'Llamar'),
          ),
        if (widget.whatsappUri != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.whatsapp,
            child: _OrderMenuRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'WhatsApp cliente',
            ),
          ),
        if (widget.locationUri != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.location,
            child: _OrderMenuRow(
              icon: Icons.location_searching_rounded,
              label: 'Abrir GPS',
            ),
          ),
        if (widget.onEdit != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.edit,
            child: _OrderMenuRow(
              icon: Icons.edit_outlined,
              label: 'Editar orden',
            ),
          ),
        if (widget.onDelete != null)
          const PopupMenuItem<_OrderMenuAction>(
            value: _OrderMenuAction.delete,
            child: _OrderMenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Eliminar orden',
            ),
          ),
      ],
    );

    if (selected == null || !context.mounted) {
      return;
    }

    switch (selected) {
      case _OrderMenuAction.changeStatus:
        if (widget.onChangeStatus == null) return;
        final status = await _showStatusSubmenu(context, buttonKey);
        if (status == null || !context.mounted) return;
        widget.onChangeStatus!.call(status);
      case _OrderMenuAction.newOrder:
        widget.onCreateNewOrder?.call();
      case _OrderMenuAction.call:
        if (widget.callUri == null) return;
        await safeOpenUrl(context, widget.callUri!);
      case _OrderMenuAction.whatsapp:
        if (widget.whatsappUri == null) return;
        await safeOpenWhatsApp(context, widget.whatsappUri!);
      case _OrderMenuAction.location:
        if (widget.locationUri == null) return;
        await safeOpenUrl(context, widget.locationUri!);
      case _OrderMenuAction.edit:
        widget.onEdit?.call();
      case _OrderMenuAction.delete:
        widget.onDelete?.call();
    }
  }

  Future<ServiceOrderStatus?> _showStatusSubmenu(
    BuildContext context,
    GlobalKey buttonKey,
  ) {
    return showMenu<ServiceOrderStatus>(
      context: context,
      position: _menuPositionFromButton(context, buttonKey, dx: 128),
      items: ServiceOrderStatus.values
          .map(
            (status) => PopupMenuItem<ServiceOrderStatus>(
              value: status,
              enabled: !widget.statusBusy && status != widget.order.status,
              child: _OrderMenuRow(
                icon: status == widget.order.status
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                label: status.label,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  RelativeRect _menuPositionFromButton(
    BuildContext context,
    GlobalKey buttonKey, {
    double dx = 0,
  }) {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonBox =
        buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }
    final offset = buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final left = offset.dx + dx;
    final top = offset.dy + buttonBox.size.height + 4;
    final right = overlayBox.size.width - (offset.dx + buttonBox.size.width);
    final bottom = overlayBox.size.height - top;
    return RelativeRect.fromLTRB(left, top, right, bottom);
  }
}

enum _OrderMenuAction {
  changeStatus,
  newOrder,
  call,
  whatsapp,
  location,
  edit,
  delete,
}

class _OrderMenuRow extends StatelessWidget {
  const _OrderMenuRow({required this.icon, required this.label, this.trailing});

  final IconData icon;
  final String label;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, color: foreground, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null)
          Icon(trailing, size: 16, color: colorScheme.onSurfaceVariant),
      ],
    );
  }
}

String _compactOrderId(String rawId) {
  final normalized = rawId.trim();
  if (normalized.length <= 8) return normalized;
  return normalized.substring(0, 8).toUpperCase();
}

String _extractFirstName(String rawName) {
  final normalized = rawName.trim();
  if (normalized.isEmpty) return '';
  return normalized.split(RegExp(r'\s+')).first.trim();
}

String? _firstMeaningfulText(String? primary, String? secondary) {
  final candidates = [primary, secondary];
  for (final candidate in candidates) {
    final value = (candidate ?? '').trim();
    if (value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

class _PanelMetaPill extends StatelessWidget {
  const _PanelMetaPill({required this.icon, required this.text, this.accent});

  final IconData icon;
  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveAccent = accent ?? colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent == null
            ? colorScheme.surfaceContainerLowest
            : effectiveAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: effectiveAccent.withValues(
            alpha: accent == null ? 0.12 : 0.18,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: effectiveAccent),
          const SizedBox(width: 5),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: effectiveAccent,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _OperationsAdminTotalsPanel extends StatelessWidget {
  const _OperationsAdminTotalsPanel({
    required this.visibleOrders,
    required this.colorScheme,
  });

  final List<ServiceOrderModel> visibleOrders;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Calcular totales
    final totalQuotations = visibleOrders
        .where(
          (order) => order.quotationId != null && order.quotationId!.isNotEmpty,
        )
        .length;
    final totalServices = visibleOrders.length;

    // Nota: Si el modelo tiene campos de monto, estos debería calcularse aquí
    // Por ahora mostramos placeholders que pueden actualizarse
    const totalAmount = 0.0; // Placeholder
    const totalUtility = 0.0; // Placeholder

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.tertiary, colorScheme.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.assessment_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Totales',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Resumen de operaciones',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: 56,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  colors: [colorScheme.primary, colorScheme.secondary],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TotalRowItem(
                  label: 'Cotizaciones',
                  value: '$totalQuotations',
                  icon: Icons.description_outlined,
                  accent: colorScheme.primary,
                ),
                const SizedBox(height: 12),
                _TotalRowItem(
                  label: 'Servicios',
                  value: '$totalServices',
                  icon: Icons.handyman_outlined,
                  accent: colorScheme.secondary,
                ),
                const SizedBox(height: 12),
                _TotalRowItem(
                  label: 'Monto Total',
                  value: totalAmount == 0.0
                      ? '---'
                      : '\$${totalAmount.toStringAsFixed(2)}',
                  icon: Icons.attach_money_rounded,
                  accent: const Color(0xFF10B981),
                ),
                const SizedBox(height: 12),
                _TotalRowItem(
                  label: 'Utilidad',
                  value: totalUtility == 0.0
                      ? '---'
                      : '\$${totalUtility.toStringAsFixed(2)}',
                  icon: Icons.trending_up_rounded,
                  accent: const Color(0xFF8B5CF6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRowItem extends StatelessWidget {
  const _TotalRowItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ContactIconButton extends StatelessWidget {
  const _ContactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: onTap == null
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                : colorScheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: onTap == null
                  ? colorScheme.outlineVariant.withValues(alpha: 0.35)
                  : colorScheme.primary.withValues(alpha: 0.16),
            ),
          ),
          child: Icon(
            icon,
            size: size <= 30 ? 15 : 18,
            color: onTap == null
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
                : colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

Uri? _buildPhoneUri(String rawPhone) {
  final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }
  return Uri.parse('tel:$digits');
}

Uri? _buildWhatsAppUri(String rawPhone) {
  var digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }
  if (digits.length == 10) {
    digits = '1$digits';
  }
  return Uri.parse('https://wa.me/$digits');
}

class _InlineStatusButton extends StatelessWidget {
  const _InlineStatusButton({
    required this.order,
    required this.busy,
    required this.isTechnician,
    required this.canPromoteStatus,
    required this.onSelected,
  });

  final ServiceOrderModel order;
  final bool busy;
  final bool isTechnician;
  final bool canPromoteStatus;
  final ValueChanged<ServiceOrderStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    final nextStatuses = canPromoteStatus
        ? order.status.nextStatusesForRole(canFinalizeDirectly: true)
        : order.status.allowedNextStatuses
              .where((status) => status == ServiceOrderStatus.cancelado)
              .toList(growable: false);
    final statuses = [order.status, ...nextStatuses]
        .fold<List<ServiceOrderStatus>>(<ServiceOrderStatus>[], (acc, item) {
          if (!acc.contains(item)) acc.add(item);
          return acc;
        });
    final buttonKey = GlobalKey();
    final useDesktopStatusDropdown =
        !isTechnician && defaultTargetPlatform == TargetPlatform.windows;

    return InkWell(
      key: buttonKey,
      borderRadius: BorderRadius.circular(999),
      onTap: busy
          ? null
          : () async {
              ServiceOrderStatus? selected;
              if (useDesktopStatusDropdown) {
                selected = await _showDesktopStatusMenu(
                  context,
                  buttonKey,
                  statuses,
                );
              } else {
                selected = await showModalBottomSheet<ServiceOrderStatus>(
                  context: context,
                  showDragHandle: true,
                  builder: (sheetContext) {
                    final theme = Theme.of(sheetContext);
                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cambiar estado',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Selecciona el estado actual de la orden.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ...statuses.map(
                              (status) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _InlineStatusSheetOption(
                                  status: status,
                                  isCurrent: status == order.status,
                                  onTap: () =>
                                      Navigator.pop(sheetContext, status),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              }

              if (selected == null || selected == order.status) {
                return;
              }
              onSelected(selected);
            },
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.55),
                ),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sync_alt_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Estado',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<ServiceOrderStatus?> _showDesktopStatusMenu(
    BuildContext context,
    GlobalKey buttonKey,
    List<ServiceOrderStatus> statuses,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return showMenu<ServiceOrderStatus>(
      context: context,
      position: _desktopStatusMenuPosition(context, buttonKey),
      elevation: 6,
      color: colorScheme.surface,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 236),
      items: statuses
          .map(
            (status) => PopupMenuItem<ServiceOrderStatus>(
              value: status,
              enabled: status != order.status,
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: status.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (status == order.status)
                    Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  RelativeRect _desktopStatusMenuPosition(BuildContext context, GlobalKey key) {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final buttonBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox == null) {
      return const RelativeRect.fromLTRB(0, 0, 0, 0);
    }

    final buttonOffset = buttonBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final left = buttonOffset.dx;
    final top = buttonOffset.dy + buttonBox.size.height + 4;
    final right =
        overlayBox.size.width - (buttonOffset.dx + buttonBox.size.width);
    final bottom = overlayBox.size.height - top;
    return RelativeRect.fromLTRB(left, top, right, bottom);
  }
}

class _InlineStatusSheetOption extends StatelessWidget {
  const _InlineStatusSheetOption({
    required this.status,
    required this.isCurrent,
    required this.onTap,
  });

  final ServiceOrderStatus status;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? status.color.withValues(alpha: 0.45)
                : colorScheme.outlineVariant,
          ),
          color: isCurrent
              ? status.color.withValues(alpha: 0.1)
              : colorScheme.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: status.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isCurrent)
              Icon(Icons.check_circle_rounded, size: 18, color: status.color),
          ],
        ),
      ),
    );
  }
}

class _OrderActionsMenu extends StatelessWidget {
  const _OrderActionsMenu({
    required this.busy,
    required this.onEdit,
    this.onDelete,
  });

  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: !busy,
      tooltip: 'Acciones de la orden',
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.edit_outlined),
            title: Text('Editar'),
          ),
        ),
        if (onDelete != null)
          const PopupMenuItem<String>(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline),
              title: Text('Eliminar'),
            ),
          ),
      ],
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.more_vert_rounded),
    );
  }
}

class _AnimatedServiceOrderStatusBadge extends StatefulWidget {
  const _AnimatedServiceOrderStatusBadge({
    required this.status,
    this.compact = false,
  });

  final ServiceOrderStatus status;
  final bool compact;

  @override
  State<_AnimatedServiceOrderStatusBadge> createState() =>
      _AnimatedServiceOrderStatusBadgeState();
}

class _AnimatedServiceOrderStatusBadgeState
    extends State<_AnimatedServiceOrderStatusBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late _StatusMotionStyle _motionStyle;

  @override
  void initState() {
    super.initState();
    _motionStyle = _StatusMotionStyle.forStatus(widget.status);
    _controller = AnimationController(
      vsync: this,
      duration: _motionStyle.duration,
    )..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _AnimatedServiceOrderStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status) return;
    _motionStyle = _StatusMotionStyle.forStatus(widget.status);
    _controller
      ..duration = _motionStyle.duration
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = widget.status;
    final style = _motionStyle;
    final compact = widget.compact;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = Curves.easeInOutCubic.transform(_controller.value);
        final dotColor = Color.lerp(style.dotStart, style.dotEnd, pulse)!;
        final dotScale =
            style.minScale + (style.maxScale - style.minScale) * pulse;
        final glowAlpha =
            style.minGlow + (style.maxGlow - style.minGlow) * pulse;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              status.color.withValues(alpha: 0.08 + (pulse * 0.04)),
              theme.colorScheme.surface,
            ),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: status.color.withValues(alpha: 0.22 + (pulse * 0.14)),
            ),
            boxShadow: [
              BoxShadow(
                color: dotColor.withValues(alpha: glowAlpha),
                blurRadius: compact
                    ? style.glowRadius * 0.45
                    : style.glowRadius,
                spreadRadius: compact
                    ? style.spreadRadius * pulse * 0.35
                    : style.spreadRadius * pulse,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 8 : 13,
              vertical: compact ? 4 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: compact ? 12 : 18,
                  height: compact ? 12 : 18,
                  child: Center(
                    child: Transform.scale(
                      scale: dotScale,
                      child: Container(
                        width: compact ? 6 : 10,
                        height: compact ? 6 : 10,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: dotColor.withValues(alpha: 0.42),
                              blurRadius: compact ? 4 : 9,
                              spreadRadius: compact ? 0.4 : 1.2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 5 : 8),
                Text(
                  status.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: status.color,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 10.2 : 14.5,
                    letterSpacing: compact ? 0.05 : 0.2,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusMotionStyle {
  const _StatusMotionStyle({
    required this.dotStart,
    required this.dotEnd,
    required this.duration,
    required this.minScale,
    required this.maxScale,
    required this.minGlow,
    required this.maxGlow,
    required this.glowRadius,
    required this.spreadRadius,
  });

  final Color dotStart;
  final Color dotEnd;
  final Duration duration;
  final double minScale;
  final double maxScale;
  final double minGlow;
  final double maxGlow;
  final double glowRadius;
  final double spreadRadius;

  factory _StatusMotionStyle.forStatus(ServiceOrderStatus status) {
    switch (status) {
      case ServiceOrderStatus.pendiente:
        return const _StatusMotionStyle(
          dotStart: Color(0xFFFFB020),
          dotEnd: Color(0xFFFF6B00),
          duration: Duration(milliseconds: 840),
          minScale: 0.82,
          maxScale: 1.3,
          minGlow: 0.16,
          maxGlow: 0.34,
          glowRadius: 15,
          spreadRadius: 1.8,
        );
      case ServiceOrderStatus.enProceso:
        return const _StatusMotionStyle(
          dotStart: Color(0xFF1D5D9B),
          dotEnd: Color(0xFF22D3EE),
          duration: Duration(milliseconds: 620),
          minScale: 0.9,
          maxScale: 1.18,
          minGlow: 0.18,
          maxGlow: 0.42,
          glowRadius: 18,
          spreadRadius: 2.1,
        );
      case ServiceOrderStatus.enPausa:
        return const _StatusMotionStyle(
          dotStart: Color(0xFFEAB308),
          dotEnd: Color(0xFFB7791F),
          duration: Duration(milliseconds: 1150),
          minScale: 0.84,
          maxScale: 1.08,
          minGlow: 0.12,
          maxGlow: 0.24,
          glowRadius: 12,
          spreadRadius: 1.1,
        );
      case ServiceOrderStatus.pospuesta:
        return const _StatusMotionStyle(
          dotStart: Color(0xFF9CA3AF),
          dotEnd: Color(0xFF8A6D3B),
          duration: Duration(milliseconds: 1320),
          minScale: 0.78,
          maxScale: 1.04,
          minGlow: 0.10,
          maxGlow: 0.22,
          glowRadius: 11,
          spreadRadius: 0.9,
        );
      case ServiceOrderStatus.finalizado:
        return const _StatusMotionStyle(
          dotStart: Color(0xFF2E8B57),
          dotEnd: Color(0xFF34D399),
          duration: Duration(milliseconds: 980),
          minScale: 0.86,
          maxScale: 1.14,
          minGlow: 0.14,
          maxGlow: 0.30,
          glowRadius: 14,
          spreadRadius: 1.4,
        );
      case ServiceOrderStatus.cancelado:
        return const _StatusMotionStyle(
          dotStart: Color(0xFFB3261E),
          dotEnd: Color(0xFFEF4444),
          duration: Duration(milliseconds: 780),
          minScale: 0.82,
          maxScale: 1.18,
          minGlow: 0.12,
          maxGlow: 0.30,
          glowRadius: 13,
          spreadRadius: 1.3,
        );
    }
  }
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 30,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'No hay órdenes para los filtros actuales',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Prueba otro estado, categoría o rango de fecha para ver más resultados.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Botón de "Mini Prompt" (3 puntos) para técnicos.
/// Solo visible para usuarios con rol técnico.
class _TechnicianQuickActionButton extends ConsumerWidget {
  const _TechnicianQuickActionButton({
    required this.order,
    required this.actionConfig,
  });

  final ServiceOrderModel order;
  final ServiceOrderQuickActionsConfig actionConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 5,
        shadowColor: const Color(0x2A8FA9C0),
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFD8E3EE)),
        ),
      ),
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: const Text(
        'Gestionar',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () async {
        await showServiceOrderQuickActionsModal(
          context: context,
          ref: ref,
          orderId: order.id,
          order: order,
          presentation: ServiceOrderQuickActionsPresentation.mobileRightPanel,
          actionConfig: actionConfig,
          onOrderUpdated: () {
            // Refresh the list when order is updated
            final controller = ref.read(
              serviceOrdersListControllerProvider.notifier,
            );
            controller.refresh();
          },
        );
      },
    );
  }
}

Uri? _buildAssistantConversationUri(Map<String, UserModel> usersById) {
  for (final user in usersById.values) {
    if (user.appRole == AppRole.asistente && user.telefono.trim().isNotEmpty) {
      return _buildWhatsAppUri(user.telefono);
    }
  }
  return null;
}
