import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/admin_authorization.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/cache/fulltech_cache_manager.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';

import '../../core/models/product_model.dart';

import '../../core/printing/unified_ticket_printer.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';

import '../../core/widgets/product_network_image.dart';
import '../../core/widgets/fulltech_dialog.dart';
import '../../features/account/delete_account_dialog.dart';
import '../cash/cash_dialogs.dart';
import '../clientes/cliente_model.dart';
import 'application/ventas_controller.dart';
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
  final FocusNode _searchFocus = FocusNode();
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
  OverlayEntry? _noStockNoticeEntry;
  DateTime? _lastSuccessfulRemoteSyncAt;
  List<ProductModel> _products = const [];
  List<SaleDraftItem> _cart = [];
  Set<String> _selectedCategories = <String>{};
  bool _searchOpen = false;

  ClienteModel? _selectedClient;

  String _money(double value) => formatRdCurrencyAccounting(value);

  List<ProductModel> get _filteredProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      final code = (p.codigo ?? '').trim().toLowerCase();
      final matchesText =
          q.isEmpty || p.nombre.toLowerCase().contains(q) || code.contains(q);
      final matchesCategory =
          _selectedCategories.isEmpty ||
          _selectedCategories.contains(p.categoriaLabel);
      return matchesText && matchesCategory;
    }).toList();
  }

  bool _matchesProductCode(ProductModel product, String rawCode) {
    final code = (product.codigo ?? '').trim().toLowerCase();
    final query = rawCode.trim().toLowerCase();
    return code.isNotEmpty && query.isNotEmpty && code == query;
  }

  ProductModel? _findProductByCode(String rawCode) {
    for (final product in _products) {
      if (_matchesProductCode(product, rawCode)) return product;
    }
    return null;
  }

  void _submitProductSearch(String rawValue) {
    final value = rawValue.trim();
    if (value.isEmpty) return;
    final product = _findProductByCode(value);
    if (product == null) {
      final visible = _filteredProducts;
      if (visible.length == 1) {
        _addProduct(visible.first);
        _searchCtrl.clear();
        setState(() {});
        _searchFocus.requestFocus();
      }
      return;
    }
    _addProduct(product);
    _searchCtrl.clear();
    setState(() {});
    _searchFocus.requestFocus();
  }

  List<String> get _availableCategories {
    final values = _products.map((item) => item.categoriaLabel).toSet().toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  double get _totalSold =>
      _cart.fold(0, (sum, item) => sum + item.subtotalSold);

  double get _totalUnits => _cart.fold(0, (sum, item) => sum + item.qty);

  bool _hasNoStock(SaleDraftItem item) {
    if (item.isExternal) return false;
    final stock = item.product?.stock;
    return stock == null || stock <= 0;
  }

  bool _productHasNoStock(ProductModel product) {
    final stock = product.stock;
    return stock == null || stock <= 0;
  }

  void _showNoStockNotice() {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    _noStockNoticeEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.paddingOf(context).top + (isDesktop ? 16 : 10),
        left: isDesktop ? 28 : 14,
        right: isDesktop ? 28 : 14,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFFB91C1C),
                          size: 18,
                        ),
                        SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            'Este producto no tiene stock suficiente. Por favor agrega stock.',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF7F1D1D),
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    _noStockNoticeEntry = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (_noStockNoticeEntry == entry) {
        entry.remove();
        _noStockNoticeEntry = null;
      }
    });
  }

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
    _noStockNoticeEntry?.remove();
    _noStockNoticeEntry = null;
    _searchCtrl.dispose();
    _searchFocus.dispose();
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
    unawaited(
      FulltechImageCacheManager.warmImageUrls(
        products.map((p) => p.displayFotoUrl),
      ),
    );
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

  Future<T?> _showRightDrawer<T>({
    required String barrierLabel,
    required WidgetBuilder builder,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(alignment: Alignment.centerRight, child: builder(context));
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
          child: child,
        );
      },
    );
  }

  Future<void> _openCategoryDrawer() async {
    final next = await _showRightDrawer<Set<String>>(
      barrierLabel: 'Filtros de categoria',
      builder: (context) => _CategoryFilterDrawer(
        categories: _availableCategories,
        selectedCategories: _selectedCategories,
      ),
    );

    if (!mounted || next == null) return;
    setState(() => _selectedCategories = next);
  }

  Future<void> _openActionsDrawer() async {
    await _showRightDrawer<void>(
      barrierLabel: 'Menu de acciones',
      builder: (context) => _SalesActionsDrawer(
        hasCart: _cart.isNotEmpty,
        hasClient: _selectedClient != null,
        onNewTicket: () {
          Navigator.of(context).pop();
          setState(() {
            _cart = [];
            _selectedClient = null;
            _noteCtrl.clear();
          });
        },
        onSelectClient: () {
          Navigator.of(context).pop();
          _openClientPickerDialog();
        },
        onNewClient: () {
          Navigator.of(context).pop();
          _createQuickClient();
        },
        onCreateQuotation: () {
          Navigator.of(context).pop();
          context.go(Routes.cotizaciones);
        },
        onQuotationList: () {
          Navigator.of(context).pop();
          context.go(Routes.cotizacionesHistorial);
        },
        onSalesList: () {
          Navigator.of(context).pop();
          context.go(Routes.ventasLista);
        },
        onAddNote: () {
          Navigator.of(context).pop();
          _openNoteDialog();
        },
        onExternalSale: () {
          Navigator.of(context).pop();
          _openExternalItemDialog();
        },
        onRefreshProducts: () {
          Navigator.of(context).pop();
          _loadProducts(forceRemote: true);
        },
        onClearCache: () {
          Navigator.of(context).pop();
          _clearAllProductCache();
        },
      ),
    );
  }

  Future<void> _openClientDetailPanel(ClienteModel client) async {
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width >= 1024
        ? (width * 0.29).clamp(420.0, 560.0)
        : width;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Detalle del cliente',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: _SalesClientDetailPanel(
            client: client,
            width: panelWidth,
            onClose: () => Navigator.of(dialogContext).pop(),
            onSelect: () {
              Navigator.of(dialogContext).pop();
              setState(() => _selectedClient = client);
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
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Widget _buildMobileAppBarSearchField() {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        autofocus: true,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: Colors.white,
        textInputAction: TextInputAction.search,
        onChanged: (_) => setState(() {}),
        onSubmitted: _submitProductSearch,
        decoration: InputDecoration(
          hintText: 'Buscar producto',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: .75),
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white),
          suffixIcon: _searchCtrl.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar',
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() {});
                    _searchFocus.requestFocus();
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .14),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .28)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .28)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileAppBarTitle() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Facturación',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 2),
        Text(
          'Factura y cotiza',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
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
      backgroundColor: isWide ? null : AppColors.background,
      appBar: CustomAppBar(
        title: isWide ? 'Registrar Venta' : 'Facturación',
        titleWidget: !isWide
            ? (_searchOpen
                  ? _buildMobileAppBarSearchField()
                  : _buildMobileAppBarTitle())
            : null,
        fallbackRoute: Routes.ventas,
        preferDrawerLeading: true,
        showLogo: false,
        showDepartmentLabel: isWide,
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
                      child: Text('Limpiar cache de productos'),
                    ),
                  ],
                ),
                SizedBox(
                  width: 200,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: _submitProductSearch,
                      decoration: const InputDecoration(
                        hintText: 'Buscar o escanear codigo...',
                        prefixIcon: Icon(
                          Icons.qr_code_scanner_outlined,
                          size: 18,
                        ),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.zero,
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                      ),
                    ),
                  ),
                ),
              ]
            : [
                if (!_searchOpen)
                  IconButton(
                    tooltip: 'Producto externo',
                    onPressed: _openExternalItemDialog,
                    icon: const Icon(Icons.add_rounded),
                  ),
                IconButton(
                  tooltip: _searchOpen ? 'Cerrar búsqueda' : 'Buscar',
                  onPressed: () {
                    setState(() {
                      _searchOpen = !_searchOpen;
                      if (!_searchOpen) {
                        _searchCtrl.clear();
                      }
                    });
                    if (_searchOpen) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _searchFocus.requestFocus();
                      });
                    }
                  },
                  icon: Icon(
                    _searchOpen ? Icons.close_rounded : Icons.search_rounded,
                  ),
                ),
                if (!_searchOpen) ...[
                  IconButton(
                    tooltip: _selectedCategories.isEmpty
                        ? 'Filtros'
                        : '${_selectedCategories.length} filtro(s)',
                    onPressed: _openCategoryDrawer,
                    icon: Badge(
                      isLabelVisible: _selectedCategories.isNotEmpty,
                      smallSize: 8,
                      child: const Icon(Icons.filter_alt_outlined),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Acciones',
                    onPressed: _openActionsDrawer,
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ],
        trailing: isWide
            ? const _SalesCompanyAccountMenu()
            : const SizedBox.shrink(),
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            if (_loadingProducts) const LinearProgressIndicator(minHeight: 2),
            if (!isWide) _buildMobileInvoiceModeBar(),
            if (!isWide && _selectedCategories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedCategories.length} categoria(s) activa(s)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedCategories = <String>{}),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('Limpiar'),
                    ),
                  ],
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

                      final panelRatio = isWide
                          ? 0.42
                          : screenHeight < 720
                          ? 0.60
                          : 0.62;
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
      ),
    );
  }

  Widget _buildProductGrid({required bool isCompact}) {
    final visible = _filteredProducts;

    if (visible.isEmpty) {
      return const Center(child: Text('No hay productos para mostrar'));
    }

    final mobileGridSurface = MediaQuery.sizeOf(context).width < 700;
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final mobileGrid = width < 560;
        final crossAxisCount = width < 340
            ? 2
            : mobileGrid
            ? 3
            : width < 900
            ? 4
            : 5;
        final compactCard = width < 900;
        final gridPadding = mobileGridSurface ? 0.0 : 8.0;
        const gridSpacing = 7.0;
        final cellWidth =
            (width - (gridPadding * 2) - (gridSpacing * (crossAxisCount - 1))) /
            crossAxisCount;
        final twoRowHeight = (height - (gridPadding * 2) - gridSpacing) / 2;
        final aspectRatio = mobileGrid
            ? (cellWidth / twoRowHeight.clamp(92.0, 150.0))
            : compactCard
            ? 1.0
            : 1.08;

        return GridView.builder(
          padding: EdgeInsets.all(gridPadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: gridSpacing,
            mainAxisSpacing: gridSpacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final product = visible[index];
            return _SaleProductGridCard(
              product: product,
              money: _money,
              mobileGrid: mobileGrid,
              compactCard: compactCard,
              onTap: () => _addProduct(product),
            );
          },
        );
      },
    );

    if (mobileGridSurface) {
      return Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .45),
          ),
        ),
        child: grid,
      );
    }

    return Column(children: [Expanded(child: grid)]);
  }

  Widget _buildMobileInvoiceModeBar() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .34),
        ),
      ),
      child: InkWell(
        onTap: _openActionsDrawer,
        child: Row(
          children: [
            const Text(
              'Factura',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _selectedClient?.nombre.trim().isNotEmpty == true
                    ? _selectedClient!.nombre.trim()
                    : 'Consumidor final',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: const Color(0xFF52667C),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '${_cart.length}',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.5),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCartPanel() {
    final theme = Theme.of(context);
    final hasClient = _selectedClient != null;
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Text(
                      'Agrega productos para iniciar la factura',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 46),
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 6,
                      thickness: .6,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: .42,
                      ),
                    ),
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      final qtyValue = item.qty % 1 == 0
                          ? item.qty.toInt().toString()
                          : item.qty.toStringAsFixed(2);
                      final outOfStock = _hasNoStock(item);
                      return ListTile(
                        dense: true,
                        minLeadingWidth: 26,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 1,
                        ),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: (item.imageUrl ?? '').trim().isEmpty
                                ? ColoredBox(
                                    color: const Color(0xFFEAF1FF),
                                    child: Icon(
                                      item.isExternal
                                          ? Icons.receipt_long_outlined
                                          : Icons.inventory_2_outlined,
                                      color: const Color(0xFF52667C),
                                      size: 18,
                                    ),
                                  )
                                : ProductNetworkImage(
                                    imageUrl: item.imageUrl!,
                                    productId: item.productId ?? item.name,
                                    productName: item.name,
                                    originalUrl: item.product?.originalFotoUrl,
                                    fit: BoxFit.cover,
                                    fallback: const ColoredBox(
                                      color: Color(0xFFEAF1FF),
                                      child: Icon(
                                        Icons.inventory_2_outlined,
                                        color: Color(0xFF52667C),
                                        size: 18,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (outOfStock) const _NoStockTinyLabel(),
                            Text(
                              item.name.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Flexible(
                              child: Text(
                                '$qtyValue x ${_money(item.priceSoldUnit)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  color: const Color(0xFF60758A),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: SizedBox(
                          width: 110,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Text(
                                  _money(item.subtotalSold),
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2E4E9),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: IconButton(
                                  tooltip: 'Editar',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      _openEditCartItemDialog(index),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2E4E9),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.12),
                                  ),
                                ),
                                child: IconButton(
                                  tooltip: 'Quitar',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  onPressed: () => setState(
                                    () => _cart = [..._cart]..removeAt(index),
                                  ),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: () => _openEditCartItemDialog(index),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Sub ${_money(_totalSold)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${_totalUnits.toStringAsFixed(_totalUnits % 1 == 0 ? 0 : 2)} uds',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _openClientPickerDialog,
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: Icon(
                            hasClient
                                ? Icons.person_rounded
                                : Icons.person_add_alt_1_rounded,
                            size: 16,
                          ),
                          label: Text(
                            hasClient
                                ? _selectedClient!.nombre
                                : 'Cliente requerido',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'TOTAL',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            _money(_totalSold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      SizedBox(
                        width: 42,
                        height: 38,
                        child: IconButton(
                          tooltip: 'Limpiar factura',
                          visualDensity: VisualDensity.standard,
                          padding: EdgeInsets.zero,
                          style: IconButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            disabledForegroundColor: const Color(
                              0xFFDC2626,
                            ).withValues(alpha: .34),
                            backgroundColor: const Color(
                              0xFFDC2626,
                            ).withValues(alpha: .08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          onPressed: _cart.isEmpty
                              ? null
                              : () => setState(() {
                                  _cart = [];
                                  _selectedClient = null;
                                  _noteCtrl.clear();
                                }),
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openNoteDialog,
                          icon: Icon(
                            _noteCtrl.text.trim().isEmpty
                                ? Icons.note_add_outlined
                                : Icons.sticky_note_2_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _noteCtrl.text.trim().isEmpty ? 'Nota' : 'Con nota',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(92, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _saving || !hasClient || _cart.isEmpty
                              ? null
                              : _saveSale,
                          icon: _saving
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_outline,
                                  size: 16,
                                ),
                          label: const Text(
                            'Generar',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(112, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            backgroundColor: const Color(0xFF1957E6),
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartPanel({
    required bool isCompact,
    required bool showInlineTotals,
  }) {
    final isWide = MediaQuery.of(context).size.width >= 1024;
    if (!isWide) return _buildMobileCartPanel();
    final hasClient = _selectedClient != null;
    return Padding(
      padding: EdgeInsets.all(isCompact ? 10 : (isWide ? 8 : 12)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.zero,
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
              final compactVertical = availableHeight < 340;
              final stackActions = constraints.maxWidth < 380;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Solo mostrar encabezado si hay cliente seleccionado ──
                  if (hasClient) ...[
                    _SelectedSaleClientHeader(
                      client: _selectedClient!,
                      onTap: _openClientPickerDialog,
                      onClear: () => setState(() => _selectedClient = null),
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
                              final outOfStock = _hasNoStock(item);

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => _openEditCartItemDialog(index),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).dividerColor.withValues(alpha: 0.20),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          qtyValue,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (outOfStock)
                                                const _NoStockTinyLabel(),
                                              Text(
                                                item.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _money(item.subtotalSold),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE2E4E9),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.black.withValues(
                                                alpha: 0.12,
                                              ),
                                            ),
                                          ),
                                          child: IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                              minHeight: 26,
                                              minWidth: 26,
                                            ),
                                            splashRadius: 14,
                                            tooltip: 'Quitar item',
                                            onPressed: () => setState(
                                              () => _cart.removeAt(index),
                                            ),
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.black,
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
                  if (stackActions)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CartClientButton(
                          hasClient: hasClient,
                          clientName: _selectedClient?.nombre,
                          onPressed: _openClientPickerDialog,
                        ),
                        const SizedBox(height: 6),
                        _CartNoteButton(
                          hasNote: _noteCtrl.text.trim().isNotEmpty,
                          onPressed: _openNoteDialog,
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: _CartClientButton(
                            hasClient: hasClient,
                            clientName: _selectedClient?.nombre,
                            onPressed: _openClientPickerDialog,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _CartNoteButton(
                            hasNote: _noteCtrl.text.trim().isNotEmpty,
                            onPressed: _openNoteDialog,
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
                              borderRadius: BorderRadius.zero,
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
                              borderRadius: BorderRadius.zero,
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
                              trailing: TextButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  unawaited(_openClientDetailPanel(c));
                                },
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                ),
                                label: const Text('Ver'),
                              ),
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

  Future<void> _openExternalItemDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: '0');
    String? errorText;

    final item = await showDialog<SaleDraftItem>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Vender fuera del inventario'),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del item',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cantidad',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Precio',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Costo',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
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
                  final name = nameCtrl.text.trim();
                  final qty = double.tryParse(qtyCtrl.text.trim());
                  final price = double.tryParse(priceCtrl.text.trim());
                  final cost = double.tryParse(costCtrl.text.trim()) ?? 0;

                  if (name.isEmpty) {
                    setDialogState(
                      () => errorText = 'Escribe el nombre del item',
                    );
                    return;
                  }
                  if (qty == null ||
                      qty <= 0 ||
                      price == null ||
                      price < 0 ||
                      cost < 0) {
                    setDialogState(
                      () => errorText = 'Revisa cantidad, precio y costo',
                    );
                    return;
                  }

                  Navigator.of(dialogContext).pop(
                    SaleDraftItem(
                      name: name,
                      imageUrl: null,
                      isExternal: true,
                      qty: qty,
                      priceSoldUnit: price,
                      costUnitSnapshot: cost,
                    ),
                  );
                },
                child: const Text('Agregar'),
              ),
            ],
          );
        },
      ),
    );

    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();

    if (item == null || !mounted) return;
    setState(() => _cart = [..._cart, item]);
  }

  void _addProduct(ProductModel product) {
    if (_productHasNoStock(product)) {
      _showNoStockNotice();
    }
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

    final payment = await showDialog<_SalePaymentDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SalePaymentDialog(total: _totalSold),
    );
    if (payment == null) return;

    setState(() => _saving = true);
    try {
      final created = await _createSaleWithAuthorizationFallback(payment);
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
      ref.invalidate(ventasControllerProvider);
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

  Future<SaleModel?> _createSaleWithAuthorizationFallback(
    _SalePaymentDraft payment,
  ) async {
    try {
      return await _createSale(payment);
    } catch (error) {
      if (!_isPermissionDenied(error) || !mounted) rethrow;
      setState(() => _saving = false);
      final allowed = await ensureAdminAuthorization(
        context,
        ref,
        permission: AppPermission.viewSales,
        forceAdminAuthorization: true,
        reason: 'Autorizar cobro de factura',
      );
      if (!mounted) return null;
      if (!allowed) {
        throw ApiException('No se autorizó el cobro de la factura.');
      }
      setState(() => _saving = true);
      return _createSale(payment);
    }
  }

  Future<SaleModel?> _createSale(_SalePaymentDraft payment) {
    return ref
        .read(ventasRepositoryProvider)
        .createSale(
          customerId: _selectedClient!.id,
          customerName: _selectedClient!.nombre,
          customerPhone: _selectedClient!.telefono,
          note: _noteCtrl.text,
          paymentMethod: payment.method,
          paymentCashAmount: payment.cashAmount,
          paymentTransferAmount: payment.transferAmount,
          expectedTotalSold: _totalSold,
          items: _cart,
        );
  }

  bool _isPermissionDenied(Object error) {
    if (error is ApiException) {
      return error.type == ApiErrorType.forbidden ||
          error.code == 403 ||
          error.message.toLowerCase().contains('no tienes permiso');
    }
    return error.toString().toLowerCase().contains('no tienes permiso');
  }
}

class _SaleProductGridCard extends StatelessWidget {
  const _SaleProductGridCard({
    required this.product,
    required this.money,
    required this.mobileGrid,
    required this.compactCard,
    required this.onTap,
  });

  final ProductModel product;
  final String Function(double value) money;
  final bool mobileGrid;
  final bool compactCard;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stockValue = product.stock;
    final outOfStock = stockValue == null || stockValue <= 0;
    final stockText = stockValue == null
        ? '0'
        : stockValue == stockValue.roundToDouble()
        ? stockValue.toStringAsFixed(0)
        : stockValue.toStringAsFixed(2);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.25),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if ((product.displayFotoUrl ?? '').isEmpty)
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.inventory_2_outlined)),
              )
            else
              ProductNetworkImage(
                imageUrl: product.displayFotoUrl!,
                productId: product.id,
                productName: product.nombre,
                originalUrl: product.originalFotoUrl,
                fit: BoxFit.cover,
                loading: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.inventory_2_outlined)),
                ),
                fallback: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xAA000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 2,
              top: 2,
              child: outOfStock
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        'SIN STOCK',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: mobileGrid ? 7 : 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.3,
                          height: 1,
                        ),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6),
                          width: 0.7,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DISP',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: mobileGrid ? 7 : 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            stockText,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: mobileGrid ? 13 : 15,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                    width: 0.7,
                  ),
                ),
                child: Text(
                  money(product.precio),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: mobileGrid ? 9.5 : 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: mobileGrid ? 20 : 24,
                height: mobileGrid ? 20 : 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF1957E6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .85),
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: mobileGrid ? 28 : 32,
              bottom: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: mobileGrid
                          ? 10.8
                          : compactCard
                          ? 10.5
                          : 11,
                    ),
                  ),
                  const SizedBox(height: 2),
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
                      product.categoriaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: mobileGrid
                            ? 8.8
                            : compactCard
                            ? 8.5
                            : 9.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalePaymentDraft {
  const _SalePaymentDraft({
    required this.method,
    required this.cashAmount,
    required this.transferAmount,
  });

  final String method;
  final double cashAmount;
  final double transferAmount;
}

class _SalePaymentDialog extends StatefulWidget {
  const _SalePaymentDialog({required this.total});

  final double total;

  @override
  State<_SalePaymentDialog> createState() => _SalePaymentDialogState();
}

class _SalePaymentDialogState extends State<_SalePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _cashCtrl;
  late final TextEditingController _transferCtrl;
  String _method = 'cash';

  @override
  void initState() {
    super.initState();
    _cashCtrl = TextEditingController(text: widget.total.toStringAsFixed(2));
    _transferCtrl = TextEditingController(text: '0.00');
  }

  @override
  void dispose() {
    _cashCtrl.dispose();
    _transferCtrl.dispose();
    super.dispose();
  }

  void _selectMethod(String method) {
    setState(() {
      _method = method;
      if (method == 'cash') {
        _cashCtrl.text = widget.total.toStringAsFixed(2);
        _transferCtrl.text = '0.00';
      } else if (method == 'transfer') {
        _cashCtrl.text = '0.00';
        _transferCtrl.text = widget.total.toStringAsFixed(2);
      } else {
        final cash = parseDominicanAmount(_cashCtrl.text) ?? 0;
        final safeCash = cash <= 0 || cash >= widget.total
            ? widget.total / 2
            : cash;
        _cashCtrl.text = safeCash.toStringAsFixed(2);
        _transferCtrl.text = (widget.total - safeCash).toStringAsFixed(2);
      }
    });
  }

  void _syncTransferFromCash() {
    if (_method != 'mixed') return;
    final cash = parseDominicanAmount(_cashCtrl.text);
    if (cash == null) return;
    final transfer = widget.total - cash;
    if (transfer < 0) return;
    _transferCtrl.text = transfer.toStringAsFixed(2);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final cash = parseDominicanAmount(_cashCtrl.text) ?? 0;
    final transfer = parseDominicanAmount(_transferCtrl.text) ?? 0;
    Navigator.of(context).pop(
      _SalePaymentDraft(
        method: _method,
        cashAmount: double.parse(cash.toStringAsFixed(2)),
        transferAmount: double.parse(transfer.toStringAsFixed(2)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.total;
    final cash = parseDominicanAmount(_cashCtrl.text) ?? 0;
    final transfer = parseDominicanAmount(_transferCtrl.text) ?? 0;
    final paid = cash + transfer;
    final remaining = total - paid;

    return AlertDialog(
      title: const Text('Cobrar venta'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                formatRdCurrencyAccounting(total),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'cash',
                    icon: Icon(Icons.payments_outlined),
                    label: Text('Efectivo'),
                  ),
                  ButtonSegment(
                    value: 'transfer',
                    icon: Icon(Icons.sync_alt_rounded),
                    label: Text('Transferencia'),
                  ),
                  ButtonSegment(
                    value: 'mixed',
                    icon: Icon(Icons.call_split_rounded),
                    label: Text('Mixto'),
                  ),
                ],
                selected: {_method},
                onSelectionChanged: (value) => _selectMethod(value.first),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cashCtrl,
                enabled: _method != 'transfer',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) {
                  _syncTransferFromCash();
                  setState(() {});
                },
                decoration: const InputDecoration(
                  labelText: 'Efectivo',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validatePaymentAmounts(),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _transferCtrl,
                enabled: _method != 'cash',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Transferencia',
                  prefixText: r'RD$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _validatePaymentAmounts(),
              ),
              const SizedBox(height: 12),
              Text(
                remaining.abs() < 0.01
                    ? 'Pago completo'
                    : 'Diferencia: ${formatRdCurrencyAccounting(remaining)}',
                style: TextStyle(
                  color: remaining.abs() < 0.01
                      ? const Color(0xFF047857)
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Guardar e imprimir'),
        ),
      ],
    );
  }

  String? _validatePaymentAmounts() {
    final cash = parseDominicanAmount(_cashCtrl.text);
    final transfer = parseDominicanAmount(_transferCtrl.text);
    if (cash == null || transfer == null) return 'Monto inválido';
    if (_method == 'cash' && (cash - widget.total).abs() >= 0.01) {
      return 'El efectivo debe cubrir el total';
    }
    if (_method == 'transfer' && (transfer - widget.total).abs() >= 0.01) {
      return 'La transferencia debe cubrir el total';
    }
    if (_method == 'mixed' && (cash <= 0 || transfer <= 0)) {
      return 'El pago mixto requiere ambos montos';
    }
    if ((cash + transfer - widget.total).abs() >= 0.01) {
      return 'Efectivo + transferencia debe igualar el total';
    }
    return null;
  }
}

class _CategoryFilterDrawer extends StatefulWidget {
  const _CategoryFilterDrawer({
    required this.categories,
    required this.selectedCategories,
  });

  final List<String> categories;
  final Set<String> selectedCategories;

  @override
  State<_CategoryFilterDrawer> createState() => _CategoryFilterDrawerState();
}

class _CategoryFilterDrawerState extends State<_CategoryFilterDrawer> {
  late Set<String> _draft;

  @override
  void initState() {
    super.initState();
    _draft = {...widget.selectedCategories};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.82).clamp(
      280.0,
      360.0,
    );
    return SafeArea(
      child: Material(
        color: theme.colorScheme.surface,
        child: SizedBox(
          width: drawerWidth,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RightDrawerHeader(
                icon: Icons.filter_alt_outlined,
                title: 'Categorias',
                subtitle: _draft.isEmpty
                    ? 'Todas visibles'
                    : '${_draft.length} seleccionada(s)',
                onClose: () => Navigator.of(context).pop(),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  _draft.isEmpty
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  color: _draft.isEmpty ? theme.colorScheme.primary : null,
                ),
                title: const Text('Todas las categorias'),
                onTap: () => setState(_draft.clear),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: widget.categories.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final category = widget.categories[index];
                    final selected = _draft.contains(category);
                    return CheckboxListTile(
                      value: selected,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        category,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onChanged: (_) => setState(() {
                        if (selected) {
                          _draft.remove(category);
                        } else {
                          _draft.add(category);
                        }
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  style: FilledButton.styleFrom(
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  child: const Text('Aplicar filtros'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesActionsDrawer extends StatelessWidget {
  const _SalesActionsDrawer({
    required this.hasCart,
    required this.hasClient,
    required this.onNewTicket,
    required this.onSelectClient,
    required this.onNewClient,
    required this.onCreateQuotation,
    required this.onQuotationList,
    required this.onSalesList,
    required this.onAddNote,
    required this.onExternalSale,
    required this.onRefreshProducts,
    required this.onClearCache,
  });

  final bool hasCart;
  final bool hasClient;
  final VoidCallback onNewTicket;
  final VoidCallback onSelectClient;
  final VoidCallback onNewClient;
  final VoidCallback onCreateQuotation;
  final VoidCallback onQuotationList;
  final VoidCallback onSalesList;
  final VoidCallback onAddNote;
  final VoidCallback onExternalSale;
  final VoidCallback onRefreshProducts;
  final VoidCallback onClearCache;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drawerWidth = (MediaQuery.sizeOf(context).width * 0.84).clamp(
      292.0,
      380.0,
    );
    return SafeArea(
      child: Material(
        color: theme.colorScheme.surface,
        child: SizedBox(
          width: drawerWidth,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RightDrawerHeader(
                icon: Icons.tune_outlined,
                title: 'Acciones',
                subtitle: hasCart ? 'Ticket en proceso' : 'Ticket nuevo',
                onClose: () => Navigator.of(context).pop(),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _ActionDrawerTile(
                      icon: Icons.add_box_outlined,
                      title: 'Crear nuevo ticket',
                      subtitle: 'Limpia la venta actual',
                      onTap: onNewTicket,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.person_search_outlined,
                      title: hasClient ? 'Cambiar cliente' : 'Cliente',
                      subtitle: 'Seleccionar cliente del ticket',
                      onTap: onSelectClient,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.person_add_alt_1,
                      title: 'Crear cliente',
                      subtitle: 'Cliente rapido para esta venta',
                      onTap: onNewClient,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.request_quote_outlined,
                      title: 'Cotizaciones',
                      subtitle: 'Crear una cotizacion',
                      onTap: onCreateQuotation,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.list_alt_outlined,
                      title: 'Lista de cotizaciones',
                      subtitle: 'Ver historial de cotizaciones',
                      onTap: onQuotationList,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.receipt_long_outlined,
                      title: 'Lista de ventas',
                      subtitle: 'Ver ventas registradas',
                      onTap: onSalesList,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.sticky_note_2_outlined,
                      title: 'Agregar una nota',
                      subtitle: 'Nota interna de la venta',
                      onTap: onAddNote,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.inventory_2_outlined,
                      title: 'Vender fuera del inventario',
                      subtitle: 'Item manual sin producto',
                      onTap: onExternalSale,
                    ),
                    const Divider(height: 18),
                    _ActionDrawerTile(
                      icon: Icons.refresh,
                      title: 'Recargar productos',
                      subtitle: 'Sincronizar catalogo',
                      onTap: onRefreshProducts,
                    ),
                    _ActionDrawerTile(
                      icon: Icons.cleaning_services_outlined,
                      title: 'Limpiar cache de productos',
                      subtitle: 'Forzar imagenes y catalogo fresco',
                      onTap: onClearCache,
                    ),
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

class _RightDrawerHeader extends StatelessWidget {
  const _RightDrawerHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _ActionDrawerTile extends StatelessWidget {
  const _ActionDrawerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _SelectedSaleClientHeader extends StatelessWidget {
  const _SelectedSaleClientHeader({
    required this.client,
    required this.onTap,
    required this.onClear,
  });

  final ClienteModel client;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = client.nombre.trim().isEmpty
        ? 'Sin nombre'
        : client.nombre.trim();
    final phone = client.telefono.trim();

    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8E5EC)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCFE0FF)),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: Color(0xFF1957E6),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF172033),
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                    children: [
                      TextSpan(
                        text: 'Cliente ',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (phone.isNotEmpty)
                        TextSpan(
                          text: ' - $phone',
                          style: const TextStyle(
                            color: Color(0xFF52667C),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quitar cliente',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                onPressed: onClear,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF64748B),
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesClientDetailPanel extends StatelessWidget {
  const _SalesClientDetailPanel({
    required this.client,
    required this.width,
    required this.onClose,
    required this.onSelect,
  });

  final ClienteModel client;
  final double width;
  final VoidCallback onClose;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = client.nombre.trim().isEmpty
        ? 'Cliente sin nombre'
        : client.nombre.trim();
    final phone = client.telefono.trim();
    final email = (client.correo ?? '').trim();
    final address = (client.direccion ?? '').trim();
    final gps = (client.locationUrl ?? '').trim();

    return Material(
      color: Colors.white,
      elevation: 18,
      child: SizedBox(
        width: width,
        height: MediaQuery.sizeOf(context).height,
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
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCFE0FF)),
                      ),
                      child: const Icon(
                        Icons.person_search_rounded,
                        color: Color(0xFF1957E6),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detalle del cliente',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Información para esta venta',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFD8E5EC)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFD8E5EC)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: const Color(0xFF172033),
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF059669),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'Cliente activo',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF059669),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (phone.isNotEmpty)
                      _SalesClientDetailLine(
                        icon: Icons.call_outlined,
                        label: 'Teléfono',
                        value: phone,
                      ),
                    if (email.isNotEmpty)
                      _SalesClientDetailLine(
                        icon: Icons.email_outlined,
                        label: 'Correo',
                        value: email,
                      ),
                    if (address.isNotEmpty)
                      _SalesClientDetailLine(
                        icon: Icons.place_outlined,
                        label: 'Dirección',
                        value: address,
                        maxLines: 3,
                      ),
                    if (gps.isNotEmpty)
                      const _SalesClientDetailLine(
                        icon: Icons.map_outlined,
                        label: 'Ubicación',
                        value: 'GPS disponible',
                      ),
                    if (client.createdAt != null)
                      _SalesClientDetailLine(
                        icon: Icons.calendar_today_outlined,
                        label: 'Creado',
                        value: _formatSaleClientDate(client.createdAt!),
                      ),
                    if (client.updatedAt != null)
                      _SalesClientDetailLine(
                        icon: Icons.update_rounded,
                        label: 'Actualizado',
                        value: _formatSaleClientDate(client.updatedAt!),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: Color(0xFFD8E5EC))),
                ),
                child: FilledButton.icon(
                  onPressed: onSelect,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Usar este cliente'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1957E6),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesClientDetailLine extends StatelessWidget {
  const _SalesClientDetailLine({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFCFE0FF)),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF1957E6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF172033),
                    fontWeight: FontWeight.w800,
                    height: 1.15,
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

String _formatSaleClientDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

class _CartClientButton extends StatelessWidget {
  const _CartClientButton({
    required this.hasClient,
    required this.clientName,
    required this.onPressed,
  });

  final bool hasClient;
  final String? clientName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.person_search_outlined, size: 16),
      label: Text(
        hasClient ? (clientName ?? 'Cliente') : 'Seleccionar cliente',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        textStyle: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _CartNoteButton extends StatelessWidget {
  const _CartNoteButton({required this.hasNote, required this.onPressed});

  final bool hasNote;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.sticky_note_2_outlined, size: 16),
      label: Text(
        hasNote ? 'Editar nota' : 'Nota',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        textStyle: const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _NoStockTinyLabel extends StatelessWidget {
  const _NoStockTinyLabel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: const Text(
        'Sin stock',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Color(0xFFDC2626),
          fontSize: 7,
          fontWeight: FontWeight.w900,
          height: 1,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _SalesCompanyAccountMenu extends ConsumerWidget {
  const _SalesCompanyAccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final companyName = company.maybeWhen(
      data: (settings) => _compactSalesCompanyName(settings.companyName),
      orElse: () => 'Empresa',
    );
    final logoBase64 = company.maybeWhen(
      data: (settings) => settings.logoBase64?.trim(),
      orElse: () => null,
    );

    return Padding(
      padding: const EdgeInsets.only(right: 10, left: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Cuenta y empresa',
        offset: const Offset(0, 44),
        elevation: 8,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFDDE7EE)),
        ),
        constraints: const BoxConstraints(minWidth: 260),
        itemBuilder: (menuContext) => [
          PopupMenuItem(
            value: 'profile',
            child: const _SalesCompanyMenuRow(
              icon: Icons.person_outline_rounded,
              label: 'Perfil',
            ),
            onTap: () => _goAfterMenu(context, Routes.profile),
          ),
          PopupMenuItem(
            value: 'users',
            child: const _SalesCompanyMenuRow(
              icon: Icons.groups_2_outlined,
              label: 'Usuarios',
            ),
            onTap: () => _goAfterMenu(context, Routes.users),
          ),
          PopupMenuItem(
            value: 'company_settings',
            child: const _SalesCompanyMenuRow(
              icon: Icons.business_center_outlined,
              label: 'Empresa',
            ),
            onTap: () => _goAfterMenu(context, Routes.configuracionEmpresa),
          ),
          PopupMenuItem(
            value: 'printer_settings',
            child: const _SalesCompanyMenuRow(
              icon: Icons.print_outlined,
              label: 'Impresora',
            ),
            onTap: () => _goAfterMenu(context, Routes.configuracionImpresora),
          ),
          PopupMenuItem(
            value: 'backup_settings',
            child: const _SalesCompanyMenuRow(
              icon: Icons.cloud_sync_outlined,
              label: 'Backup',
            ),
            onTap: () => _goAfterMenu(context, Routes.configuracionBackup),
          ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem(
            value: 'logout',
            child: const _SalesCompanyMenuRow(
              icon: Icons.logout_rounded,
              label: 'Cerrar sesion',
              danger: true,
            ),
            onTap: () {
              Future<void>.delayed(Duration.zero, () async {
                await ref.read(authStateProvider.notifier).logout();
                if (context.mounted) context.go(Routes.login);
              });
            },
          ),
          PopupMenuItem(
            value: 'delete_account',
            child: const _SalesCompanyMenuRow(
              icon: Icons.delete_forever_outlined,
              label: 'Eliminar mi cuenta',
              danger: true,
            ),
            onTap: () {
              Future<void>.delayed(Duration.zero, () {
                if (context.mounted) showDeleteAccountDialog(context, ref);
              });
            },
          ),
        ],
        child: _SalesCompanyButton(label: companyName, logoBase64: logoBase64),
      ),
    );
  }

  void _goAfterMenu(BuildContext context, String route) {
    Future<void>.delayed(Duration.zero, () {
      if (context.mounted) context.go(route);
    });
  }
}

class _SalesCompanyButton extends StatefulWidget {
  const _SalesCompanyButton({required this.label, required this.logoBase64});

  final String label;
  final String? logoBase64;

  @override
  State<_SalesCompanyButton> createState() => _SalesCompanyButtonState();
}

class _SalesCompanyButtonState extends State<_SalesCompanyButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerCancel: (_) => setState(() => _pressed = false),
        onPointerUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.012 : 1),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 40,
            constraints: const BoxConstraints(minWidth: 132, maxWidth: 220),
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: active
                    ? const [Color(0xFF2E6BFF), Color(0xFF164ED6)]
                    : const [Color(0xFF1F62FF), Color(0xFF1957E6)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF7DA2FF)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1957E6).withValues(alpha: 0.22),
                  blurRadius: active ? 18 : 10,
                  offset: Offset(0, active ? 7 : 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SalesCompanyLogoBox(logoBase64: widget.logoBase64, size: 26),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SalesCompanyLogoBox extends StatelessWidget {
  const _SalesCompanyLogoBox({required this.logoBase64, this.size = 28});

  final String? logoBase64;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logoBytes = _decodeLogo(logoBase64);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoBytes == null
          ? Icon(
              Icons.storefront_rounded,
              size: size * 0.58,
              color: Colors.white,
            )
          : Image.memory(logoBytes, fit: BoxFit.cover),
    );
  }

  Uint8List? _decodeLogo(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      final payload = raw.contains(',') ? raw.split(',').last : raw;
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }
}

class _SalesCompanyMenuRow extends StatelessWidget {
  const _SalesCompanyMenuRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFDC2626) : const Color(0xFF183548);
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

String _compactSalesCompanyName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  if (normalized.isEmpty) return 'Empresa';
  if (normalized.length <= 18) return normalized;
  final firstSegment = normalized.split(' ').first.trim();
  if (firstSegment.length >= 3) return firstSegment;
  return normalized.substring(0, 18);
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
