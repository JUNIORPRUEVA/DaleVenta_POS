import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/cache/fulltech_map_tile_cache.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../service_orders/application/service_orders_list_controller.dart';
import '../service_orders/service_order_models.dart';
import 'application/clientes_controller.dart';
import 'client_location_utils.dart';
import 'cliente_model.dart';

class ClientesMapScreen extends ConsumerStatefulWidget {
  const ClientesMapScreen({super.key});

  @override
  ConsumerState<ClientesMapScreen> createState() => _ClientesMapScreenState();
}

class _ClientesMapScreenState extends ConsumerState<ClientesMapScreen> {
  Map<String, ClientLocationPreview> _locationsByClientId = const {};
  bool _resolvingLocations = false;
  String _locationSignature = '';
  String _tileWarmSignature = '';
  String? _selectedSellerId;
  _MapOrderScope _selectedOrderScope = _MapOrderScope.all;
  _MapDatePreset _selectedDatePreset = _MapDatePreset.all;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final clientsState = ref.read(clientesControllerProvider);
    final ordersState = ref.read(serviceOrdersListControllerProvider);
    final pending = <Future<void>>[];

    if (clientsState.items.isEmpty && !clientsState.loading) {
      pending.add(ref.read(clientesControllerProvider.notifier).refresh());
    }
    if (ordersState.items.isEmpty && !ordersState.loading) {
      pending.add(
        ref.read(serviceOrdersListControllerProvider.notifier).refresh(),
      );
    }

    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
    if (!mounted) return;
    await _resolveLocations(force: true);
  }

  Future<void> _resolveLocations({bool force = false}) async {
    final clients = ref.read(clientesControllerProvider).items;
    final signature = clients
        .map(
          (client) =>
              '${client.id}|${client.locationUrl ?? ''}|${client.latitude ?? ''}|${client.longitude ?? ''}',
        )
        .join('||');

    if (!force && signature == _locationSignature) return;

    setState(() => _resolvingLocations = true);
    final dio = ref.read(dioProvider);

    try {
      final entries = await Future.wait(
        clients.map((client) async {
          if (client.latitude != null &&
              client.longitude != null &&
              client.latitude!.isFinite &&
              client.longitude!.isFinite) {
            return MapEntry(
              client.id,
              ClientLocationPreview(
                latitude: client.latitude,
                longitude: client.longitude,
                resolvedUrl: client.locationUrl,
              ),
            );
          }

          final preview = await resolveClientLocationPreview(
            client.locationUrl,
            dio: dio,
          );
          return MapEntry(client.id, preview);
        }),
      );

      if (!mounted) return;
      setState(() {
        _locationSignature = signature;
        _locationsByClientId = {
          for (final entry in entries)
            if (entry.value.hasCoordinates) entry.key: entry.value,
        };
      });
    } finally {
      if (mounted) {
        setState(() => _resolvingLocations = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientsState = ref.watch(clientesControllerProvider);
    final ordersState = ref.watch(serviceOrdersListControllerProvider);
    final sellerFilters = _buildSellerFilters(
      orders: ordersState.items,
      usersById: ordersState.usersById,
    );
    final filteredOrders = _applyOrderFilters(ordersState.items);
    final hasActiveFilters =
        _selectedSellerId != null ||
        _selectedOrderScope != _MapOrderScope.all ||
        _selectedDatePreset != _MapDatePreset.all ||
        _dateFrom != null ||
        _dateTo != null;

    final nextSignature = clientsState.items
        .map(
          (client) =>
              '${client.id}|${client.locationUrl ?? ''}|${client.latitude ?? ''}|${client.longitude ?? ''}',
        )
        .join('||');
    if (!_resolvingLocations && nextSignature != _locationSignature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _resolveLocations();
        }
      });
    }

    final items = _buildMapItems(
      clients: clientsState.items,
      orders: filteredOrders,
      usersById: ordersState.usersById,
      locationsByClientId: _locationsByClientId,
      includeClientsWithoutOrders: !hasActiveFilters,
    );
    final summary = _MapSummary.fromItems(items);
    final nextTileWarmSignature = _buildTileWarmSignature(items);
    if (items.isNotEmpty && nextTileWarmSignature != _tileWarmSignature) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_warmInitialTileCache(items));
        }
      });
    }

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFEAF6FB)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: clientsState.loading && clientsState.items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _FullscreenMapSurface(
                      items: items,
                      summary: summary,
                      selectedSellerId: _selectedSellerId,
                      selectedOrderScope: _selectedOrderScope,
                      selectedDatePreset: _selectedDatePreset,
                      dateFrom: _dateFrom,
                      dateTo: _dateTo,
                      sellerFilters: sellerFilters,
                      hasActiveFilters: hasActiveFilters,
                      isResolvingLocations:
                          _resolvingLocations ||
                          clientsState.refreshing ||
                          ordersState.refreshing,
                      onSelectedSellerChanged: (nextSellerId) {
                        setState(() {
                          _selectedSellerId = nextSellerId;
                        });
                      },
                      onSelectedOrderScopeChanged: (nextScope) {
                        setState(() {
                          _selectedOrderScope = nextScope;
                        });
                      },
                      onDatePresetChanged: (nextPreset) {
                        setState(() {
                          _selectedDatePreset = nextPreset;
                          final now = DateTime.now();
                          final end = DateTime(
                            now.year,
                            now.month,
                            now.day,
                            23,
                            59,
                            59,
                            999,
                          );
                          switch (nextPreset) {
                            case _MapDatePreset.all:
                              _dateFrom = null;
                              _dateTo = null;
                            case _MapDatePreset.today:
                              _dateFrom = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              );
                              _dateTo = end;
                            case _MapDatePreset.last7Days:
                              final start = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              ).subtract(const Duration(days: 6));
                              _dateFrom = start;
                              _dateTo = end;
                            case _MapDatePreset.last30Days:
                              final start = DateTime(
                                now.year,
                                now.month,
                                now.day,
                              ).subtract(const Duration(days: 29));
                              _dateFrom = start;
                              _dateTo = end;
                            case _MapDatePreset.custom:
                              _dateFrom ??= DateTime(
                                now.year,
                                now.month,
                                now.day,
                              ).subtract(const Duration(days: 7));
                              _dateTo ??= end;
                          }
                        });
                      },
                      onPickDateFrom: () => _pickDateFrom(context),
                      onPickDateTo: () => _pickDateTo(context),
                      onClearFilters: () {
                        setState(() {
                          _selectedSellerId = null;
                          _selectedOrderScope = _MapOrderScope.all;
                          _selectedDatePreset = _MapDatePreset.all;
                          _dateFrom = null;
                          _dateTo = null;
                        });
                      },
                      onClientTap: _openClient,
                    ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FloatingMapButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Volver',
                      onPressed: _goBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          _buildTopLabel(summary),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w300,
                                color: Colors.white.withValues(alpha: 0.88),
                                letterSpacing: 0.25,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openClient(String clientId) {
    context.push(Routes.clienteDetail(clientId));
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go(Routes.serviceOrders);
  }

  Future<void> _warmInitialTileCache(List<_ClientMapItem> items) async {
    _tileWarmSignature = _buildTileWarmSignature(items);
    await FulltechMapTileCacheManager.warmTileUrls(
      _buildInitialTileUrls(items),
    );
  }

  List<ServiceOrderModel> _applyOrderFilters(List<ServiceOrderModel> orders) {
    var filtered = orders.where((order) {
      if (_selectedSellerId == null) return true;
      return order.createdById.trim() == _selectedSellerId;
    });

    filtered = filtered.where((order) {
      switch (_selectedOrderScope) {
        case _MapOrderScope.all:
          return true;
        case _MapOrderScope.completed:
          return order.status == ServiceOrderStatus.finalizado;
        case _MapOrderScope.inProgress:
          return order.status == ServiceOrderStatus.enProceso;
        case _MapOrderScope.pending:
          return order.status == ServiceOrderStatus.pendiente;
      }
    });

    filtered = filtered.where((order) {
      final at = _orderDateForFilter(order);
      if (at == null) return false;

      if (_dateFrom != null && at.isBefore(_dateFrom!)) {
        return false;
      }
      if (_dateTo != null && at.isAfter(_dateTo!)) {
        return false;
      }
      return true;
    });

    return filtered.toList(growable: false);
  }

  DateTime? _orderDateForFilter(ServiceOrderModel order) {
    return order.finalizedAt ?? order.scheduledFor ?? order.createdAt;
  }

  Future<void> _pickDateFrom(BuildContext context) async {
    final now = DateTime.now();
    final initial = _dateFrom ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2022),
      lastDate: DateTime(now.year + 1),
      helpText: 'Fecha desde',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _selectedDatePreset = _MapDatePreset.custom;
      _dateFrom = DateTime(picked.year, picked.month, picked.day);
      if (_dateTo != null && _dateTo!.isBefore(_dateFrom!)) {
        _dateTo = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
          999,
        );
      }
    });
  }

  Future<void> _pickDateTo(BuildContext context) async {
    final now = DateTime.now();
    final seed = _dateTo ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: seed,
      firstDate: DateTime(2022),
      lastDate: DateTime(now.year + 1),
      helpText: 'Fecha hasta',
    );
    if (!mounted || picked == null) return;
    final end = DateTime(
      picked.year,
      picked.month,
      picked.day,
      23,
      59,
      59,
      999,
    );
    setState(() {
      _selectedDatePreset = _MapDatePreset.custom;
      _dateTo = end;
      if (_dateFrom != null && _dateFrom!.isAfter(_dateTo!)) {
        _dateFrom = DateTime(picked.year, picked.month, picked.day);
      }
    });
  }
}

String _buildTopLabel(_MapSummary summary) {
  if (summary.total == 0) return 'Sin ubicaciones disponibles';
  if (summary.inProgress > 0) {
    return '${summary.total} ubicaciones · ${summary.inProgress} en proceso';
  }
  return '${summary.total} ubicaciones activas';
}

List<_ClientMapItem> _buildMapItems({
  required List<ClienteModel> clients,
  required List<ServiceOrderModel> orders,
  required Map<String, UserModel> usersById,
  required Map<String, ClientLocationPreview> locationsByClientId,
  bool includeClientsWithoutOrders = true,
}) {
  final ordersByClientId = <String, List<ServiceOrderModel>>{};
  for (final order in orders) {
    ordersByClientId
        .putIfAbsent(order.clientId, () => <ServiceOrderModel>[])
        .add(order);
  }

  final items = <_ClientMapItem>[];
  for (final client in clients) {
    final preview = locationsByClientId[client.id];
    if (preview == null || !preview.hasCoordinates) continue;
    final clientOrders =
        ordersByClientId[client.id] ?? const <ServiceOrderModel>[];
    if (!includeClientsWithoutOrders && clientOrders.isEmpty) {
      continue;
    }
    final sellerName = _resolveSellerName(
      orders: clientOrders,
      usersById: usersById,
    );
    items.add(
      _ClientMapItem(
        client: client,
        location: LatLng(preview.latitude!, preview.longitude!),
        state: _ClientServiceState.fromOrders(clientOrders),
        sellerName: sellerName,
      ),
    );
  }

  items.sort((left, right) {
    final byPriority = left.state.priority.compareTo(right.state.priority);
    if (byPriority != 0) return byPriority;
    return left.client.nombre.toLowerCase().compareTo(
      right.client.nombre.toLowerCase(),
    );
  });

  return items;
}

String? _resolveSellerName({
  required List<ServiceOrderModel> orders,
  required Map<String, UserModel> usersById,
}) {
  if (orders.isEmpty) return null;

  final finalizedOrders = orders
      .where((order) => order.status == ServiceOrderStatus.finalizado)
      .toList(growable: false);

  ServiceOrderModel pickMostRecent(
    ServiceOrderModel current,
    ServiceOrderModel next,
  ) {
    final currentAt = current.finalizedAt ?? current.updatedAt;
    final nextAt = next.finalizedAt ?? next.updatedAt;
    return nextAt.isAfter(currentAt) ? next : current;
  }

  if (finalizedOrders.isEmpty) return null;

  final selected = finalizedOrders.reduce(pickMostRecent);
  final sellerId = selected.createdById.trim();
  if (sellerId.isEmpty) return null;

  final sellerName = (usersById[sellerId]?.nombreCompleto ?? sellerId).trim();
  if (sellerName.isEmpty) return null;
  return _extractFirstName(sellerName);
}

String _extractFirstName(String fullName) {
  final tokens = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (tokens.isEmpty) return fullName.trim();
  return tokens.first.trim();
}

List<_SellerFilterOption> _buildSellerFilters({
  required List<ServiceOrderModel> orders,
  required Map<String, UserModel> usersById,
}) {
  final countsBySellerId = <String, int>{};
  for (final order in orders) {
    final sellerId = order.createdById.trim();
    if (sellerId.isEmpty) continue;
    countsBySellerId.update(sellerId, (count) => count + 1, ifAbsent: () => 1);
  }

  final options =
      countsBySellerId.entries
          .map((entry) {
            final userName = (usersById[entry.key]?.nombreCompleto ?? entry.key)
                .trim();
            final shortName = userName.isEmpty
                ? entry.key
                : _extractFirstName(userName);
            return _SellerFilterOption(
              sellerId: entry.key,
              sellerLabel: shortName,
              orderCount: entry.value,
            );
          })
          .toList(growable: false)
        ..sort(
          (a, b) => a.sellerLabel.toLowerCase().compareTo(
            b.sellerLabel.toLowerCase(),
          ),
        );

  return options;
}

class _FullscreenMapSurface extends StatelessWidget {
  const _FullscreenMapSurface({
    required this.items,
    required this.summary,
    required this.selectedSellerId,
    required this.selectedOrderScope,
    required this.selectedDatePreset,
    required this.dateFrom,
    required this.dateTo,
    required this.sellerFilters,
    required this.hasActiveFilters,
    required this.isResolvingLocations,
    required this.onSelectedSellerChanged,
    required this.onSelectedOrderScopeChanged,
    required this.onDatePresetChanged,
    required this.onPickDateFrom,
    required this.onPickDateTo,
    required this.onClearFilters,
    required this.onClientTap,
  });

  final List<_ClientMapItem> items;
  final _MapSummary summary;
  final String? selectedSellerId;
  final _MapOrderScope selectedOrderScope;
  final _MapDatePreset selectedDatePreset;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<_SellerFilterOption> sellerFilters;
  final bool hasActiveFilters;
  final bool isResolvingLocations;
  final ValueChanged<String?> onSelectedSellerChanged;
  final ValueChanged<_MapOrderScope> onSelectedOrderScopeChanged;
  final ValueChanged<_MapDatePreset> onDatePresetChanged;
  final VoidCallback onPickDateFrom;
  final VoidCallback onPickDateTo;
  final VoidCallback onClearFilters;
  final ValueChanged<String> onClientTap;

  @override
  Widget build(BuildContext context) {
    final viewport = _buildPreferredViewport(items);

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: SizedBox.expand(
            child: _InteractiveClientMap(
              items: items,
              viewport: viewport,
              onClientTap: onClientTap,
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 92,
          bottom: 18,
          child: _MapLegendCard(summary: summary),
        ),
        Positioned(
          right: 16,
          top: 56,
          child: _MapFiltersFloatingButton(
            selectedSellerId: selectedSellerId,
            selectedOrderScope: selectedOrderScope,
            selectedDatePreset: selectedDatePreset,
            dateFrom: dateFrom,
            dateTo: dateTo,
            sellerFilters: sellerFilters,
            hasActiveFilters: hasActiveFilters,
            onSelectedSellerChanged: onSelectedSellerChanged,
            onSelectedOrderScopeChanged: onSelectedOrderScopeChanged,
            onDatePresetChanged: onDatePresetChanged,
            onPickDateFrom: onPickDateFrom,
            onPickDateTo: onPickDateTo,
            onClearFilters: onClearFilters,
          ),
        ),
        if (summary.total == 0)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.26),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'No hay puntos para mostrar',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (isResolvingLocations)
          const Positioned(
            right: 25,
            top: 106,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ),
      ],
    );
  }
}

class _InteractiveClientMap extends StatefulWidget {
  const _InteractiveClientMap({
    required this.items,
    required this.viewport,
    required this.onClientTap,
  });

  final List<_ClientMapItem> items;
  final _MapViewport viewport;
  final ValueChanged<String> onClientTap;

  @override
  State<_InteractiveClientMap> createState() => _InteractiveClientMapState();
}

class _InteractiveClientMapState extends State<_InteractiveClientMap> {
  late final MapController _mapController;
  late double _currentZoom;
  _MapVisualStyle _style = _MapVisualStyle.street;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentZoom = widget.viewport.zoom;
  }

  @override
  void didUpdateWidget(covariant _InteractiveClientMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewport.center != widget.viewport.center ||
        oldWidget.viewport.zoom != widget.viewport.zoom) {
      _currentZoom = widget.viewport.zoom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(widget.viewport.center, widget.viewport.zoom);
      });
    }
  }

  void _zoomBy(double delta) {
    final nextZoom = (_currentZoom + delta).clamp(4.0, 18.5);
    _mapController.move(_mapController.camera.center, nextZoom);
    setState(() => _currentZoom = nextZoom);
  }

  void _toggleStyle() {
    setState(() {
      _style = _style == _MapVisualStyle.street
          ? _MapVisualStyle.earth
          : _MapVisualStyle.street;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showLabels = _currentZoom >= 12.8 || widget.items.length <= 3;

    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.viewport.center,
            initialZoom: widget.viewport.zoom,
            onPositionChanged: (position, _) {
              final zoom = position.zoom;
              if (zoom == null || zoom == _currentZoom) return;
              setState(() => _currentZoom = zoom);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _style.urlTemplate,
              userAgentPackageName: 'com.fulltech.app',
              tileProvider: _CachedMapTileProvider(),
              panBuffer: 2,
            ),
            if (_style == _MapVisualStyle.earth)
              TileLayer(
                urlTemplate:
                    'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                userAgentPackageName: 'com.fulltech.app',
                tileProvider: _CachedMapTileProvider(),
                panBuffer: 1,
              ),
            MarkerLayer(
              markers: [
                for (final item in widget.items)
                  Marker(
                    point: item.location,
                    width: showLabels ? 132 : 64,
                    height: showLabels ? 132 : 70,
                    child: _MapMarker(
                      item: item,
                      onTap: widget.onClientTap,
                      showLabel: showLabels,
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 112,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapStyleToggleButton(style: _style, onTap: _toggleStyle),
              const SizedBox(height: 10),
              _MapZoomControls(
                onZoomIn: () => _zoomBy(1),
                onZoomOut: () => _zoomBy(-1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _MapVisualStyle { street, earth }

extension on _MapVisualStyle {
  String get urlTemplate {
    switch (this) {
      case _MapVisualStyle.street:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case _MapVisualStyle.earth:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  String get label {
    switch (this) {
      case _MapVisualStyle.street:
        return 'Mapa';
      case _MapVisualStyle.earth:
        return 'Satélite';
    }
  }

  String get helperLabel {
    switch (this) {
      case _MapVisualStyle.street:
        return 'Calles';
      case _MapVisualStyle.earth:
        return 'Casas y terreno';
    }
  }

  IconData get icon {
    switch (this) {
      case _MapVisualStyle.street:
        return Icons.map_rounded;
      case _MapVisualStyle.earth:
        return Icons.public_rounded;
    }
  }
}

class _MapStyleToggleButton extends StatelessWidget {
  const _MapStyleToggleButton({required this.style, required this.onTap});

  final _MapVisualStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cambiar entre vista mapa y satélite',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.30),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(style.icon, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    style.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                style.helperLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapZoomButton(
            icon: Icons.add_rounded,
            tooltip: 'Acercar',
            onTap: onZoomIn,
          ),
          Container(
            width: 34,
            height: 1,
            color: Colors.white.withValues(alpha: 0.14),
          ),
          _MapZoomButton(
            icon: Icons.remove_rounded,
            tooltip: 'Alejar',
            onTap: onZoomOut,
          ),
        ],
      ),
    );
  }
}

class _MapZoomButton extends StatelessWidget {
  const _MapZoomButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _MapMarker extends StatelessWidget {
  const _MapMarker({
    required this.item,
    required this.onTap,
    required this.showLabel,
  });

  final _ClientMapItem item;
  final ValueChanged<String> onTap;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(item.client.id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabel && (item.sellerName?.isNotEmpty ?? false))
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 84),
              child: Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'v.por ${item.sellerName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 8,
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.84),
                    letterSpacing: 0.08,
                  ),
                ),
              ),
            ),
          if (showLabel)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1A0F172A),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Text(
                  item.client.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 48,
            height: 54,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 8,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: item.state.color.withValues(alpha: 0.35),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: item.state.color.withValues(alpha: 0.32),
                          blurRadius: 18,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
                Icon(
                  Icons.location_on_rounded,
                  size: 44,
                  color: Colors.white,
                  shadows: const [
                    Shadow(
                      color: Color(0x330F172A),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                Icon(
                  Icons.location_on_rounded,
                  size: 39,
                  color: item.state.color,
                ),
                Positioned(
                  top: 10,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: item.state.color,
                        shape: BoxShape.circle,
                      ),
                    ),
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

class _MapLegendCard extends StatelessWidget {
  const _MapLegendCard({required this.summary});

  final _MapSummary summary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.90),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.place_rounded,
                  size: 15,
                  color: const Color(0xFF0F172A).withValues(alpha: 0.78),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${summary.total} clientes con ubicación',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _LegendChip(
                  color: const Color(0xFFF59E0B),
                  label: 'Proceso ${summary.inProgress}',
                ),
                _LegendChip(
                  color: const Color(0xFFDC2626),
                  label: 'Sin servicio ${summary.noService}',
                ),
                _LegendChip(
                  color: const Color(0xFF15803D),
                  label: 'Atendidos ${summary.serviced}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingMapButton extends StatelessWidget {
  const _FloatingMapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: Ink(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

class _MapFiltersFloatingButton extends StatelessWidget {
  const _MapFiltersFloatingButton({
    required this.selectedSellerId,
    required this.selectedOrderScope,
    required this.selectedDatePreset,
    required this.dateFrom,
    required this.dateTo,
    required this.sellerFilters,
    required this.hasActiveFilters,
    required this.onSelectedSellerChanged,
    required this.onSelectedOrderScopeChanged,
    required this.onDatePresetChanged,
    required this.onPickDateFrom,
    required this.onPickDateTo,
    required this.onClearFilters,
  });

  final String? selectedSellerId;
  final _MapOrderScope selectedOrderScope;
  final _MapDatePreset selectedDatePreset;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<_SellerFilterOption> sellerFilters;
  final bool hasActiveFilters;
  final ValueChanged<String?> onSelectedSellerChanged;
  final ValueChanged<_MapOrderScope> onSelectedOrderScopeChanged;
  final ValueChanged<_MapDatePreset> onDatePresetChanged;
  final VoidCallback onPickDateFrom;
  final VoidCallback onPickDateTo;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Filtrar por vendedor, fecha y estado',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Ink(
          width: 94,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 14,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      color: Colors.white.withValues(alpha: 0.95),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Filtros',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasActiveFilters)
                const Positioned(right: 7, top: 7, child: _ActiveFilterDot()),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Filtros de mapa',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.sizeOf(dialogContext).width;
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 56, right: 16, left: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.min(320, screenWidth - 32),
                ),
                child: _MapFiltersPanel(
                  selectedSellerId: selectedSellerId,
                  selectedOrderScope: selectedOrderScope,
                  selectedDatePreset: selectedDatePreset,
                  dateFrom: dateFrom,
                  dateTo: dateTo,
                  sellerFilters: sellerFilters,
                  hasActiveFilters: hasActiveFilters,
                  onSelectedSellerChanged: onSelectedSellerChanged,
                  onSelectedOrderScopeChanged: onSelectedOrderScopeChanged,
                  onDatePresetChanged: onDatePresetChanged,
                  onPickDateFrom: onPickDateFrom,
                  onPickDateTo: onPickDateTo,
                  onClearFilters: onClearFilters,
                ),
              ),
            ),
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
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _MapFiltersPanel extends StatelessWidget {
  const _MapFiltersPanel({
    required this.selectedSellerId,
    required this.selectedOrderScope,
    required this.selectedDatePreset,
    required this.dateFrom,
    required this.dateTo,
    required this.sellerFilters,
    required this.hasActiveFilters,
    required this.onSelectedSellerChanged,
    required this.onSelectedOrderScopeChanged,
    required this.onDatePresetChanged,
    required this.onPickDateFrom,
    required this.onPickDateTo,
    required this.onClearFilters,
  });

  final String? selectedSellerId;
  final _MapOrderScope selectedOrderScope;
  final _MapDatePreset selectedDatePreset;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<_SellerFilterOption> sellerFilters;
  final bool hasActiveFilters;
  final ValueChanged<String?> onSelectedSellerChanged;
  final ValueChanged<_MapOrderScope> onSelectedOrderScopeChanged;
  final ValueChanged<_MapDatePreset> onDatePresetChanged;
  final VoidCallback onPickDateFrom;
  final VoidCallback onPickDateTo;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final sellerValue = selectedSellerId ?? '__all__';

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2A0F172A),
              blurRadius: 28,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.tune_rounded,
                  size: 16,
                  color: Color(0xFF0F172A),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Filtros del mapa',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (hasActiveFilters)
                  TextButton(
                    onPressed: onClearFilters,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: sellerValue,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Vendedor',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '__all__',
                  child: Text('Todos'),
                ),
                for (final option in sellerFilters)
                  DropdownMenuItem<String>(
                    value: option.sellerId,
                    child: Text('${option.sellerLabel} (${option.orderCount})'),
                  ),
              ],
              onChanged: (value) {
                onSelectedSellerChanged(value == '__all__' ? null : value);
              },
            ),
            const SizedBox(height: 10),
            Text(
              'Estado',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final scope in _MapOrderScope.values)
                  ChoiceChip(
                    label: Text(scope.label),
                    selected: scope == selectedOrderScope,
                    onSelected: (_) => onSelectedOrderScopeChanged(scope),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Fecha',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in _MapDatePreset.values)
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: preset == selectedDatePreset,
                    onSelected: (_) => onDatePresetChanged(preset),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickDateFrom,
                    icon: const Icon(Icons.event_available_rounded, size: 16),
                    label: Text(
                      dateFrom == null
                          ? 'Desde'
                          : 'Desde ${_fmtDate(dateFrom!)}',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(34),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickDateTo,
                    icon: const Icon(Icons.event_busy_rounded, size: 16),
                    label: Text(
                      dateTo == null ? 'Hasta' : 'Hasta ${_fmtDate(dateTo!)}',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(34),
                      visualDensity: VisualDensity.compact,
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

String _fmtDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

class _ActiveFilterDot extends StatelessWidget {
  const _ActiveFilterDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFF22C55E),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CachedMapTileProvider extends TileProvider {
  _CachedMapTileProvider();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _CachedMapTileImageProvider(
      url,
      headers: headers.isEmpty ? null : headers,
    );
  }
}

@immutable
class _CachedMapTileImageProvider
    extends ImageProvider<_CachedMapTileImageProvider> {
  const _CachedMapTileImageProvider(this.url, {this.headers});

  final String url;
  final Map<String, String>? headers;

  @override
  Future<_CachedMapTileImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_CachedMapTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedMapTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Tile URL', url),
      ],
    );
  }

  Future<Codec> _loadAsync(ImageDecoderCallback decode) async {
    try {
      final bytes = await _readAndValidateBytes();
      return decode(await ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      await FulltechMapTileCacheManager.removeFile(url);
      try {
        final bytes = await _readAndValidateBytes();
        return decode(await ImmutableBuffer.fromUint8List(bytes));
      } catch (_) {
        return decode(
          await ImmutableBuffer.fromUint8List(_transparentTileBytes),
        );
      }
    }
  }

  Future<Uint8List> _readAndValidateBytes() async {
    final bytes = await FulltechMapTileCacheManager.getTileBytes(
      url,
      headers: headers ?? const <String, String>{},
    );
    if (!_looksLikeImage(bytes)) {
      throw const FormatException('Tile payload is not a supported image');
    }
    return bytes;
  }

  bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 12) return false;

    final isPng =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    if (isPng) return true;

    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    if (isJpeg) return true;

    final isGif =
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38;
    if (isGif) return true;

    final isWebP =
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isWebP;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _CachedMapTileImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}

final Uint8List _transparentTileBytes = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

class _ClientMapItem {
  const _ClientMapItem({
    required this.client,
    required this.location,
    required this.state,
    required this.sellerName,
  });

  final ClienteModel client;
  final LatLng location;
  final _ClientServiceState state;
  final String? sellerName;
}

class _SellerFilterOption {
  const _SellerFilterOption({
    required this.sellerId,
    required this.sellerLabel,
    required this.orderCount,
  });

  final String sellerId;
  final String sellerLabel;
  final int orderCount;
}

enum _MapOrderScope { all, completed, inProgress, pending }

extension on _MapOrderScope {
  String get label {
    switch (this) {
      case _MapOrderScope.all:
        return 'Todos';
      case _MapOrderScope.completed:
        return 'Finalizados';
      case _MapOrderScope.inProgress:
        return 'En proceso';
      case _MapOrderScope.pending:
        return 'Pendientes';
    }
  }
}

enum _MapDatePreset { all, today, last7Days, last30Days, custom }

extension on _MapDatePreset {
  String get label {
    switch (this) {
      case _MapDatePreset.all:
        return 'Todo';
      case _MapDatePreset.today:
        return 'Hoy';
      case _MapDatePreset.last7Days:
        return '7d';
      case _MapDatePreset.last30Days:
        return '30d';
      case _MapDatePreset.custom:
        return 'Rango';
    }
  }
}

class _MapSummary {
  const _MapSummary({
    required this.total,
    required this.inProgress,
    required this.serviced,
    required this.noService,
  });

  final int total;
  final int inProgress;
  final int serviced;
  final int noService;

  factory _MapSummary.fromItems(List<_ClientMapItem> items) {
    var inProgress = 0;
    var serviced = 0;
    var noService = 0;
    for (final item in items) {
      if (item.state.kind == _ClientServiceKind.inProgress) {
        inProgress++;
      } else if (item.state.kind == _ClientServiceKind.serviced) {
        serviced++;
      } else {
        noService++;
      }
    }
    return _MapSummary(
      total: items.length,
      inProgress: inProgress,
      serviced: serviced,
      noService: noService,
    );
  }
}

class _MapViewport {
  const _MapViewport({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

enum _ClientServiceKind { serviced, inProgress, noService }

class _ClientServiceState {
  const _ClientServiceState({required this.kind});

  final _ClientServiceKind kind;

  factory _ClientServiceState.fromOrders(List<ServiceOrderModel> orders) {
    if (orders.isEmpty) {
      return const _ClientServiceState(kind: _ClientServiceKind.noService);
    }

    final hasActive = orders.any(
      (order) =>
          order.status == ServiceOrderStatus.enProceso ||
          order.status == ServiceOrderStatus.pendiente,
    );
    if (hasActive) {
      return const _ClientServiceState(kind: _ClientServiceKind.inProgress);
    }

    final hasCompleted = orders.any(
      (order) => order.status == ServiceOrderStatus.finalizado,
    );
    if (hasCompleted) {
      return const _ClientServiceState(kind: _ClientServiceKind.serviced);
    }

    return const _ClientServiceState(kind: _ClientServiceKind.noService);
  }

  Color get color {
    switch (kind) {
      case _ClientServiceKind.serviced:
        return const Color(0xFF15803D);
      case _ClientServiceKind.inProgress:
        return const Color(0xFFF59E0B);
      case _ClientServiceKind.noService:
        return const Color(0xFFDC2626);
    }
  }

  int get priority {
    switch (kind) {
      case _ClientServiceKind.inProgress:
        return 0;
      case _ClientServiceKind.noService:
        return 1;
      case _ClientServiceKind.serviced:
        return 2;
    }
  }
}

LatLng _mapCenter(List<_ClientMapItem> items) {
  if (items.isEmpty) return const LatLng(18.4861, -69.9312);

  final latitude =
      items.fold<double>(0, (sum, item) => sum + item.location.latitude) /
      items.length;
  final longitude =
      items.fold<double>(0, (sum, item) => sum + item.location.longitude) /
      items.length;
  return LatLng(latitude, longitude);
}

_MapViewport _buildPreferredViewport(List<_ClientMapItem> items) {
  if (items.isEmpty) {
    return const _MapViewport(center: LatLng(18.4861, -69.9312), zoom: 10.5);
  }

  if (items.length == 1) {
    return _MapViewport(center: items.first.location, zoom: 15.5);
  }

  final distance = const Distance();
  final radiusMeters = items.length >= 12 ? 4500.0 : 6500.0;
  List<_ClientMapItem> bestCluster = <_ClientMapItem>[];
  double bestAverageDistance = double.infinity;

  for (final anchor in items) {
    final cluster = <_ClientMapItem>[];
    var distanceSum = 0.0;

    for (final candidate in items) {
      final meters = distance(anchor.location, candidate.location);
      if (meters <= radiusMeters) {
        cluster.add(candidate);
        distanceSum += meters;
      }
    }

    final averageDistance = cluster.isEmpty
        ? double.infinity
        : distanceSum / cluster.length;

    if (cluster.length > bestCluster.length ||
        (cluster.length == bestCluster.length &&
            averageDistance < bestAverageDistance)) {
      bestCluster = cluster;
      bestAverageDistance = averageDistance;
    }
  }

  final effectiveCluster = bestCluster.length >= 2 ? bestCluster : items;
  final center = _mapCenter(effectiveCluster);
  final zoom = _clusterZoom(effectiveCluster, center);
  return _MapViewport(center: center, zoom: zoom);
}

double _clusterZoom(List<_ClientMapItem> items, LatLng center) {
  if (items.length <= 1) return 15.5;

  final latitudeSpan = items
      .map((item) => (item.location.latitude - center.latitude).abs())
      .reduce(math.max);
  final longitudeSpan = items
      .map((item) => (item.location.longitude - center.longitude).abs())
      .reduce(math.max);
  final span = math.max(latitudeSpan, longitudeSpan);

  if (span <= 0.003) return 16.0;
  if (span <= 0.008) return 15.0;
  if (span <= 0.02) return 14.0;
  if (span <= 0.04) return 13.0;
  if (span <= 0.08) return 12.0;
  if (span <= 0.16) return 11.0;
  if (span <= 0.30) return 10.0;
  if (span <= 0.55) return 9.0;
  return 8.0;
}

String _buildTileWarmSignature(List<_ClientMapItem> items) {
  return items
      .map(
        (item) =>
            '${item.client.id}:${item.location.latitude.toStringAsFixed(4)},${item.location.longitude.toStringAsFixed(4)}',
      )
      .join('|');
}

Iterable<String> _buildInitialTileUrls(List<_ClientMapItem> items) sync* {
  if (items.isEmpty) return;

  final center = _mapCenter(items);
  final zoom = items.length <= 1
      ? 15
      : items.length <= 4
      ? 11
      : 9;
  final tilePoint = _latLngToTile(center, zoom);

  for (var dx = -2; dx <= 2; dx++) {
    for (var dy = -2; dy <= 2; dy++) {
      yield 'https://tile.openstreetmap.org/$zoom/${tilePoint.x + dx}/${tilePoint.y + dy}.png';
    }
  }
}

_TilePoint _latLngToTile(LatLng latLng, int zoom) {
  final scale = 1 << zoom;
  final x = ((latLng.longitude + 180.0) / 360.0 * scale).floor();
  final latitudeRadians = latLng.latitude * math.pi / 180.0;
  final y =
      ((1.0 -
                  (math.log(
                        math.tan(latitudeRadians) +
                            1.0 / math.cos(latitudeRadians),
                      ) /
                      math.pi)) /
              2.0 *
              scale)
          .floor();
  return _TilePoint(x: x, y: y);
}

class _TilePoint {
  const _TilePoint({required this.x, required this.y});

  final int x;
  final int y;
}
