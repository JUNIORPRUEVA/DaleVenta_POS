import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/cache/fulltech_cache_manager.dart';
import '../../core/models/product_model.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/product_network_image.dart';
import '../../core/widgets/fulltech_dialog.dart';
import '../clientes/cliente_model.dart';
import 'data/ventas_repository.dart';
import 'sales_models.dart';

class RegistrarVentaScreen extends ConsumerStatefulWidget {
  const RegistrarVentaScreen({super.key});

  @override
  ConsumerState<RegistrarVentaScreen> createState() =>
      _RegistrarVentaScreenState();
}

class _RegistrarVentaScreenState extends ConsumerState<RegistrarVentaScreen>
    with WidgetsBindingObserver
    implements RouteAware {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();
  DateTime? _lastAutoSyncAt;
  Timer? _liveSyncTimer;
  StreamSubscription<CatalogRealtimeMessage>? _realtimeSubscription;
  static const Duration _liveSyncInterval = Duration(minutes: 2);
  static const Duration _silentRefreshMinInterval = Duration(seconds: 20);

  bool _routeObserverSubscribed = false;
  RouteObserver<ModalRoute<dynamic>>? _routeObserver;

  bool _loadingProducts = true;
  bool _saving = false;
  bool _remoteRefreshInFlight = false;
  DateTime? _lastSuccessfulRemoteSyncAt;
  List<ProductModel> _products = const [];
  List<SaleDraftItem> _cart = [];
  String? _selectedCategory;

  ClienteModel? _selectedClient;

  String _money(double value) => formatRdCurrencyAccounting(value);

  List<ProductModel> get _filteredProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      final matchesText = q.isEmpty || p.nombre.toLowerCase().contains(q);
      final matchesCategory =
          _selectedCategory == null || p.categoriaLabel == _selectedCategory;
      return matchesText && matchesCategory;
    }).toList();
  }

  List<String> get _availableCategories {
    final values = _products.map((item) => item.categoriaLabel).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  double get _totalSold =>
      _cart.fold(0, (sum, item) => sum + item.subtotalSold);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeRealtime();
    _startLiveSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadProducts(forceRemote: true, silent: true));
    });
  }

  void _subscribeRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = ref
        .read(catalogRealtimeServiceProvider)
        .stream
        .listen((_) => _loadProducts(forceRemote: true, silent: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeRouteObserver();
    _scheduleAutoSync();
  }

  void _subscribeRouteObserver() {
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final observer = ref.read(appRouteObserverProvider);
    observer.subscribe(this, route);
    _routeObserver = observer;
    _routeObserverSubscribed = true;
  }

  void _syncProductsOnEnter() {
    if (!mounted) return;
    _loadProducts(forceRemote: true, silent: true);
  }

  @override
  void didPush() {
    _syncProductsOnEnter();
  }

  @override
  void didPopNext() {
    _syncProductsOnEnter();
  }

  @override
  void didPushNext() {}

  @override
  void didPop() {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _startLiveSync();
      _loadProducts(forceRemote: true, silent: true);
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopLiveSync();
    }
  }

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(_liveSyncInterval, (_) {
      if (!mounted) return;
      _loadProducts(forceRemote: true, silent: true);
    });
  }

  void _stopLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  void _scheduleAutoSync() {
    final now = DateTime.now();
    final last = _lastAutoSyncAt;
    if (last != null && now.difference(last).inMilliseconds < 1200) return;
    _lastAutoSyncAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadProducts(forceRemote: true, silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_routeObserverSubscribed) {
      _routeObserver?.unsubscribe(this);
      _routeObserverSubscribed = false;
      _routeObserver = null;
    }
    _stopLiveSync();
    _realtimeSubscription?.cancel();
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts({
    bool forceRemote = false,
    bool silent = false,
  }) async {
    if (silent && forceRemote && _remoteRefreshInFlight) return;
    if (silent &&
        forceRemote &&
        _products.isNotEmpty &&
        _lastSuccessfulRemoteSyncAt != null &&
        DateTime.now().difference(_lastSuccessfulRemoteSyncAt!) <
            _silentRefreshMinInterval) {
      return;
    }
    if (silent && forceRemote) {
      _remoteRefreshInFlight = true;
    }

    if (mounted && !silent) setState(() => _loadingProducts = true);
    try {
      final fetched = await ref
          .read(ventasRepositoryProvider)
          .fetchProducts(forceRefresh: forceRemote);
      final syncVersion = buildCatalogSyncVersion(fetched);
      final products = applyCatalogSyncVersion(fetched, syncVersion);
      if (!mounted) return;
      setState(() {
        _products = products;
        _loadingProducts = false;
      });
      _prefetchProductImages(products);
      _lastSuccessfulRemoteSyncAt = DateTime.now();
    } catch (e) {
      if (mounted && !silent) setState(() => _loadingProducts = false);
      if (!mounted) return;
      if (silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar productos: $e')),
      );
    } finally {
      if (silent && forceRemote) {
        _remoteRefreshInFlight = false;
      }
    }
  }

  void _prefetchProductImages(List<ProductModel> products) {
    final urls = products
        .map((p) => p.displayFotoUrl)
        .whereType<String>()
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .take(80)
        .toList();
    if (urls.isEmpty) return;

    Future.microtask(() async {
      for (final url in urls) {
        try {
          await FulltechImageCacheManager.instance.downloadFile(url);
        } catch (_) {
          // Ignore individual image failures.
        }
      }
    });
  }

  Future<void> _clearAllProductCache() async {
    await FulltechImageCacheManager.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Caché limpiado')));
    setState(() {
      _products = const [];
      _loadingProducts = true;
    });
    await _loadProducts();
  }

  Future<void> _pickCategoryFilter() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final categories = _availableCategories;
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.category_outlined,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Filtrar por categoría',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    ListTile(
                      leading: Icon(
                        _selectedCategory == null
                            ? Icons.check_circle
                            : Icons.list_alt_outlined,
                        color: _selectedCategory == null
                            ? theme.colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        'Todas las categorías',
                        style: TextStyle(
                          fontWeight: _selectedCategory == null
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: _selectedCategory == null
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, null),
                    ),
                    if (categories.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Divider(height: 1),
                      ),
                      for (final category in categories)
                        ListTile(
                          leading: Icon(
                            _selectedCategory == category
                                ? Icons.check_circle
                                : Icons.category_outlined,
                            color: _selectedCategory == category
                                ? theme.colorScheme.primary
                                : null,
                          ),
                          title: Text(
                            category,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: _selectedCategory == category
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _selectedCategory == category
                                  ? theme.colorScheme.primary
                                  : null,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, category),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == _selectedCategory) return;
    setState(() => _selectedCategory = selected);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isWide = screenWidth >= 1024;
    final isCompact = screenWidth < 900;
    final showInlineTotals = screenWidth >= 700 && screenHeight >= 780;
    final maxContentWidth = isWide ? 1180.0 : double.infinity;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Registrar Venta',
        fallbackRoute: Routes.ventas,
        preferDrawerLeading: true,
        showLogo: false,
        showDepartmentLabel: false,
        actions: isWide
            ? [
                IconButton(
                  tooltip: 'Recargar productos',
                  onPressed: () => _loadProducts(forceRemote: true),
                  icon: const Icon(Icons.refresh),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (value) {
                    if (value == 'clear_cache') {
                      _clearAllProductCache();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'clear_cache',
                      child: Text('Limpiar caché de productos'),
                    ),
                  ],
                ),
                SizedBox(
                  width: 200,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Buscar...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                      ),
                    ),
                  ),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Recargar productos',
                  onPressed: () => _loadProducts(forceRemote: true),
                  icon: const Icon(Icons.refresh),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (value) {
                    if (value == 'clear_cache') {
                      _clearAllProductCache();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'clear_cache',
                      child: Text('Limpiar caché de productos'),
                    ),
                  ],
                ),
              ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: Column(
        children: [
          if (!isWide)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar producto...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchCtrl.text.isNotEmpty)
                        IconButton(
                          tooltip: 'Limpiar búsqueda',
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                      IconButton(
                        tooltip: _selectedCategory == null
                            ? 'Filtrar por categoría'
                            : 'Categoría: $_selectedCategory',
                        onPressed: _pickCategoryFilter,
                        icon: Icon(
                          _selectedCategory == null
                              ? Icons.filter_alt_outlined
                              : Icons.filter_alt,
                        ),
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const dividerHeight = 1.0;
                    final available = constraints.maxHeight;
                    final contentHeight = (available - dividerHeight).clamp(
                      160.0,
                      available,
                    );

                    final panelRatio = isWide ? 0.42 : 0.50;
                    final panelHeight = contentHeight * panelRatio;
                    final productHeight = contentHeight - panelHeight;

                    return Column(
                      children: [
                        SizedBox(
                          height: productHeight,
                          child: _buildProductGrid(isCompact: isCompact),
                        ),
                        Container(
                          height: dividerHeight,
                          color: Theme.of(context).dividerColor,
                        ),
                        SizedBox(
                          height: panelHeight,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: isWide ? 720 : double.infinity,
                              ),
                              child: _buildCartPanel(
                                isCompact: isCompact,
                                showInlineTotals: showInlineTotals,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid({required bool isCompact}) {
    if (_loadingProducts && _products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredProducts;
    final visible = filtered;

    if (visible.isEmpty) {
      return const Center(child: Text('No hay productos para mostrar'));
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width < 360
                  ? 2
                  : width < 520
                  ? 3
                  : width < 900
                  ? 4
                  : 5;
              final compactCard = width < 900;
              final aspectRatio = compactCard ? 1.05 : 1.08;

              return GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: aspectRatio,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final p = visible[index];

                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _addProduct(p),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.25),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if ((p.displayFotoUrl ?? '').isEmpty)
                            Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: Icon(Icons.inventory_2_outlined),
                              ),
                            )
                          else
                            ProductNetworkImage(
                              imageUrl: p.displayFotoUrl!,
                              productId: p.id,
                              productName: p.nombre,
                              originalUrl: p.originalFotoUrl,
                              fit: BoxFit.cover,
                              loading: Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(Icons.inventory_2_outlined),
                                ),
                              ),
                              fallback: Container(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          const Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x00000000),
                                    Color(0xAA000000),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 6,
                            right: 6,
                            bottom: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.nombre,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: compactCard ? 10 : 11,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                // Categoría con badge elegante - sin corte de texto
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: compactCard ? 4 : 5,
                                    vertical: compactCard ? 1.5 : 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    p.categoriaLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.fade,
                                    softWrap: false,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: compactCard ? 8.5 : 9.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _money(p.precio),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compactCard ? 9 : 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCartPanel({
    required bool isCompact,
    required bool showInlineTotals,
  }) {
    final isWide = MediaQuery.of(context).size.width >= 1024;
    final hasClient = _selectedClient != null;
    return Padding(
      padding: EdgeInsets.all(isCompact ? 10 : (isWide ? 8 : 12)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isCompact ? 8 : (isWide ? 10 : 10),
            isCompact ? 8 : (isWide ? 10 : 10),
            isCompact ? 8 : (isWide ? 10 : 10),
            isCompact ? 4 : (isWide ? 4 : 6),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableHeight = constraints.maxHeight;
              final compactVertical = availableHeight < 320;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Solo mostrar encabezado si hay cliente seleccionado ──
                  if (hasClient) ...[
                    Text(
                      _selectedClient!.nombre,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_cart.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          '${_cart.length} item(s)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    SizedBox(height: compactVertical ? 4 : 6),
                  ] else
                    SizedBox(height: compactVertical ? 4 : 6),
                  // ── Lista de items ──
                  Expanded(
                    flex: 5,
                    child: _cart.isEmpty
                        ? const Center(
                            child: Text('Agrega productos para iniciar'),
                          )
                        : ListView.separated(
                            itemCount: _cart.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final item = _cart[index];
                              final qtyValue = item.qty % 1 == 0
                                  ? item.qty.toInt().toString()
                                  : item.qty.toStringAsFixed(2);

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _openEditCartItemDialog(index),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          qtyValue,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11,
                                          ),
                                          maxLines: 1,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _money(item.subtotalSold),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minHeight: 24,
                                              minWidth: 24,
                                            ),
                                            splashRadius: 12,
                                            tooltip: 'Quitar item',
                                            onPressed: () => setState(
                                              () => _cart.removeAt(index),
                                            ),
                                            icon: const Icon(
                                              Icons.close,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  SizedBox(height: compactVertical ? 4 : 6),
                  // ── Botones de acción (cliente + nota) ──
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _openClientPickerDialog,
                          icon: const Icon(
                            Icons.person_search_outlined,
                            size: 16,
                          ),
                          label: Text(
                            hasClient
                                ? _selectedClient!.nombre
                                : 'Seleccionar cliente',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openNoteDialog,
                          icon: const Icon(
                            Icons.sticky_note_2_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _noteCtrl.text.trim().isEmpty
                                ? 'Nota'
                                : 'Editar nota',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_noteCtrl.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _noteCtrl.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  // ── Línea divisoria + Total a Cobrar ──
                  if (_cart.isNotEmpty) ...[
                    const Divider(height: 12, thickness: 1),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text(
                            'Cobrar',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _money(_totalSold),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // ── Botón de guardar/limpiar ──
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving || !hasClient || _cart.isEmpty
                              ? null
                              : _saveSale,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'GUARDAR VENTA',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      ),
                      if (_cart.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => setState(() {
                            _cart = [];
                            _selectedClient = null;
                            _noteCtrl.clear();
                          }),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          child: Text(
                            'Limpiar',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openNoteDialog() async {
    final noteEditor = TextEditingController(text: _noteCtrl.text);

    final saved = await FullTechFormDialog.show<bool>(
      context,
      title: 'Nota de la venta',
      confirmText: 'Guardar',
      maxWidth: FullTechDialogTokens.maxWidthSmall,
      content: TextField(
        controller: noteEditor,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'Escribe una nota (opcional)',
          border: OutlineInputBorder(),
        ),
      ),
      onConfirm: () => Navigator.of(context).pop(true),
    );

    if (saved == true && mounted) {
      setState(() {
        _noteCtrl.text = noteEditor.text.trim();
      });
    }
  }

  Future<void> _openClientPickerDialog() async {
    final searchCtrl = TextEditingController();
    var rows = <ClienteModel>[];
    bool loading = true;

    try {
      rows = await ref.read(ventasRepositoryProvider).searchClients('');
    } catch (_) {
      rows = const [];
    } finally {
      loading = false;
    }

    if (!mounted) return;

    Future<void> runSearch(StateSetter setDialogState) async {
      setDialogState(() => loading = true);
      try {
        final result = await ref
            .read(ventasRepositoryProvider)
            .searchClients(searchCtrl.text);
        if (!mounted) return;
        setDialogState(() {
          rows = result;
          loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setDialogState(() => loading = false);
      }
    }

    final selected = await FullTechDialog.show<ClienteModel>(
      context,
      title: 'Seleccionar cliente',
      maxWidth: FullTechDialogTokens.maxWidthSmall,
      child: StatefulBuilder(
        builder: (context, setDialogState) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: searchCtrl,
                onSubmitted: (_) => runSearch(setDialogState),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o teléfono',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () => runSearch(setDialogState),
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              else
                SizedBox(
                  height: 220,
                  child: rows.isEmpty
                      ? const Center(child: Text('No hay clientes disponibles'))
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = rows[index];
                            return ListTile(
                              dense: true,
                              title: Text(c.nombre),
                              subtitle: Text(c.telefono),
                              onTap: () => Navigator.of(context).pop(c),
                            );
                          },
                        ),
                ),
            ],
          );
        },
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            _createQuickClient();
          },
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Agregar nuevo cliente'),
        ),
      ],
    );

    if (selected != null && mounted) {
      setState(() => _selectedClient = selected);
    }
  }

  void _addProduct(ProductModel product) {
    final idx = _cart.indexWhere((item) => item.product?.id == product.id);
    if (idx >= 0) {
      final current = _cart[idx];
      _updateItem(idx, current.copyWith(qty: current.qty + 1));
      return;
    }

    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(product.id);
    final productId = isUuid ? product.id : null;

    setState(() {
      _cart = [
        ..._cart,
        SaleDraftItem(
          product: product,
          productId: productId,
          name: product.nombre,
          imageUrl: product.displayFotoUrl,
          isExternal: productId == null,
          qty: 1,
          priceSoldUnit: product.precio,
          costUnitSnapshot: product.costo,
        ),
      ];
    });
  }

  void _updateItem(int index, SaleDraftItem next) {
    setState(() {
      final list = [..._cart];
      list[index] = next;
      _cart = list;
    });
  }

  Future<void> _openEditCartItemDialog(int index) async {
    final item = _cart[index];
    final qtyCtrl = TextEditingController(
      text: item.qty % 1 == 0
          ? item.qty.toInt().toString()
          : item.qty.toStringAsFixed(2),
    );
    final priceCtrl = TextEditingController(
      text: item.priceSoldUnit.toStringAsFixed(2),
    );
    String? errorText;

    final updated = await showDialog<SaleDraftItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Editar producto agregado'),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(dialogContext).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Precio a vender',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final qty = double.tryParse(qtyCtrl.text.trim());
                  final price = double.tryParse(priceCtrl.text.trim());

                  if (qty == null || qty <= 0) {
                    setDialogState(
                      () => errorText = 'La cantidad debe ser mayor que 0',
                    );
                    return;
                  }

                  if (price == null || price < 0) {
                    setDialogState(
                      () => errorText = 'El precio a vender debe ser 0 o mayor',
                    );
                    return;
                  }

                  Navigator.of(
                    dialogContext,
                  ).pop(item.copyWith(qty: qty, priceSoldUnit: price));
                },
                child: const Text('Guardar cambios'),
              ),
            ],
          );
        },
      ),
    );

    qtyCtrl.dispose();
    priceCtrl.dispose();

    if (updated == null || !mounted) return;
    _updateItem(index, updated);
  }

  Future<void> _createQuickClient() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear cliente rápido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final created = await ref
          .read(ventasRepositoryProvider)
          .createQuickClient(nombre: nameCtrl.text, telefono: phoneCtrl.text);
      if (!mounted) return;
      setState(() {
        _selectedClient = created;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente creado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo crear cliente: $e')));
    }
  }

  Future<void> _saveSale() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agrega al menos un item')));
      return;
    }

    if (_cart.any(
      (item) =>
          item.qty <= 0 || item.priceSoldUnit < 0 || item.costUnitSnapshot < 0,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Revisa: qty > 0 y montos no negativos')),
      );
      return;
    }

    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes seleccionar un cliente')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final created = await ref
          .read(ventasRepositoryProvider)
          .createSale(
            customerId: _selectedClient!.id,
            note: _noteCtrl.text,
            items: _cart,
          );
      if (created != null) {
        final printResult = await ref
            .read(unifiedTicketPrinterProvider)
            .printSaleTicket(sale: created, items: created.items);
        if (!printResult.success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Venta guardada, pero no se imprimio: ${printResult.message}',
              ),
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _cart = [];
        _selectedClient = null;
        _noteCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta guardada correctamente')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final double initialValue;
  final double min;
  final ValueChanged<double> onChanged;

  const _NumberField({
    required this.label,
    required this.initialValue,
    required this.min,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (value) {
        final parsed = double.tryParse(value.trim()) ?? widget.initialValue;
        final safe = parsed < widget.min ? widget.min : parsed;
        widget.onChanged(safe);
      },
    );
  }
}
