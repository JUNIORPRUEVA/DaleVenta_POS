import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/models/product_model.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/product_network_image.dart';
import '../../core/widgets/sync_status_banner.dart';
import 'application/catalog_controller.dart';

String _formatStock(double? stock) {
  if (stock == null) return '—';
  final isWhole = stock % 1 == 0;
  return isWhole ? stock.toStringAsFixed(0) : stock.toStringAsFixed(2);
}

double? _parseCatalogNumber(String raw) {
  var value = raw
      .trim()
      .replaceAll('RD\$', '')
      .replaceAll('rd\$', '')
      .replaceAll(' ', '');
  if (value.contains(',') && value.contains('.')) {
    value = value.replaceAll(',', '');
  } else {
    value = value.replaceAll(',', '.');
  }
  return double.tryParse(value);
}

class CatalogoScreen extends ConsumerStatefulWidget {
  final bool modal;

  const CatalogoScreen({super.key, this.modal = false});

  @override
  ConsumerState<CatalogoScreen> createState() => _CatalogoScreenState();
}

class _CatalogoScreenState extends ConsumerState<CatalogoScreen>
    with WidgetsBindingObserver
    implements RouteAware {
  final _searchCtrl = TextEditingController();
  String _category = 'Todas';
  DateTime? _lastAutoSyncAt;
  Timer? _liveSyncTimer;
  StreamSubscription<CatalogRealtimeMessage>? _realtimeSubscription;
  bool _purgingAllDebug = false;
  bool _routeObserverSubscribed = false;
  RouteObserver<ModalRoute<dynamic>>? _routeObserver;
  static const Duration _liveSyncInterval = Duration(minutes: 2);

  bool get _hasActiveFilter => _category != 'Todas';
  bool get _hasActiveSearch => _searchCtrl.text.trim().isNotEmpty;

  bool _isDesktopWidth(double width) => width >= 1100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeRealtime();
    _scheduleAutoSync();
    _startLiveSync();
  }

  void _subscribeRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = ref
        .read(catalogRealtimeServiceProvider)
        .stream
        .listen((_) => _scheduleCatalogSync());
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
    _scheduleCatalogSync();
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
      _scheduleCatalogSync();
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
      _scheduleCatalogSync();
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
      _scheduleCatalogSync();
    });
  }

  void _scheduleCatalogSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(catalogControllerProvider.notifier)
          .load(silent: true, forceRemote: true);
    });
  }

  Future<void> _purgeAllDebug() async {
    final user = ref.read(authStateProvider).user;
    final canManage = canUseDebugAdminAction(user);
    if (!canManage) {
      return;
    }

    final confirmed = await confirmDebugAdminPurge(
      context,
      moduleLabel: 'catálogo',
      impactLabel: 'todos los productos locales visibles en este módulo',
    );
    if (!confirmed || !mounted) return;

    setState(() => _purgingAllDebug = true);
    try {
      final deleted = await ref
          .read(catalogControllerProvider.notifier)
          .purgeAllDebug();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se limpiaron $deleted productos.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        setState(() => _purgingAllDebug = false);
      }
    }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = (user?.role ?? '').trim().toUpperCase() == 'ADMIN';
    final canManage = isAdmin;

    final isModal = widget.modal;

    final catalog = ref.watch(catalogControllerProvider);

    final categories = <String>{
      'Todas',
      ...catalog.items.map((p) => p.categoriaLabel),
    }.toList()..sort();

    final categoryOptions =
        catalog.items
            .map((p) => p.categoriaLabel)
            .where((c) => c.isNotEmpty && c != 'Sin categoría')
            .toSet()
            .toList()
          ..sort();

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered =
        catalog.items.where((p) {
          final matchCategory =
              _category == 'Todas' || p.categoriaLabel == _category;
          final matchQuery =
              query.isEmpty || p.nombre.toLowerCase().contains(query);
          return matchCategory && matchQuery;
        }).toList()..sort(
          (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
        );
    final categoryCounts = <String, int>{
      for (final category in categories)
        category: category == 'Todas'
            ? catalog.items.length
            : catalog.items
                  .where((product) => product.categoriaLabel == category)
                  .length,
    };

    final hasCategoryFilters = categories.length > 1;

    InputDecoration searchDecoration() {
      final colorScheme = Theme.of(context).colorScheme;
      return InputDecoration(
        hintText: 'Buscar producto',
        hintStyle: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: colorScheme.primary,
        ),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
                icon: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      );
    }

    Widget modalHeader() {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                style: Theme.of(context).textTheme.bodyMedium,
                decoration: searchDecoration(),
              ),
            ),
            if (hasCategoryFilters)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Badge(
                  isLabelVisible: _hasActiveFilter,
                  smallSize: 8,
                  child: IconButton(
                    tooltip: 'Filtrar categoría',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openCategoryFilter(categories),
                    icon: const Icon(Icons.tune, size: 20),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final isWideLayout = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: isModal
          ? null
          : CustomAppBar(
              title: 'Catálogo',
              showLogo: false,
              darkerTone: true,
              highContrast: true,
              actions: [
                DebugAdminActionButton(
                  user: user,
                  enabled: canManage,
                  busy: _purgingAllDebug,
                  tooltip: 'Limpiar tabla (debug)',
                  onPressed: _purgeAllDebug,
                ),
                if (canManage)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilledButton.icon(
                      onPressed: () =>
                          _openProductForm(categories: categoryOptions),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nuevo producto'),
                    ),
                  ),
                if (canManage)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: OutlinedButton.icon(
                      onPressed: _importProductsFromCsv,
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Importar'),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Badge(
                    isLabelVisible: _hasActiveSearch,
                    smallSize: 8,
                    child: IconButton(
                      tooltip: 'Buscar productos',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openCatalogSearch(
                        products: catalog.items,
                        showCost: isAdmin,
                        canManage: canManage,
                        categories: categoryOptions,
                      ),
                      icon: const Icon(Icons.search_rounded, size: 21),
                    ),
                  ),
                ),
                if (hasCategoryFilters)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Badge(
                      isLabelVisible: _hasActiveFilter,
                      smallSize: 8,
                      child: IconButton(
                        tooltip: 'Filtrar categoría',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openCategoryFilter(categories),
                        icon: const Icon(Icons.tune, size: 20),
                      ),
                    ),
                  ),
              ],
              trailing: user == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => context.push(Routes.profile),
                        child: UserAvatar(
                          radius: 16,
                          backgroundColor: Colors.white24,
                          imageUrl: user.fotoPersonalUrl,
                          child: Text(
                            getInitials(user.nombreCompleto),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
      drawer: isModal ? null : buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: canManage && !isModal
          ? FloatingActionButton.extended(
              onPressed: () => _openProductForm(categories: categoryOptions),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Producto'),
            )
          : null,
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          isWideLayout ? 16 : 12,
          isWideLayout ? 16 : 12,
          isWideLayout ? 16 : 12,
          isWideLayout ? 16 : 8,
        ),
        child: Column(
          children: [
            if (isModal) modalHeader(),
            if ((_hasActiveFilter || query.isNotEmpty) && !isModal)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).colorScheme.surfaceContainerLowest,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.82),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mostrando ${filtered.length} de ${catalog.items.length} productos${query.isNotEmpty ? ' para "$query"' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _category = 'Todas';
                          _searchCtrl.clear();
                        });
                      },
                      child: const Text('Limpiar'),
                    ),
                  ],
                ),
              ),
            SyncStatusBanner(
              visible: catalog.refreshing,
              label: 'Actualizando productos en segundo plano...',
            ),
            if ((_hasActiveFilter || query.isNotEmpty) && isModal)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mostrando ${filtered.length} de ${catalog.items.length} productos',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _category = 'Todas';
                          _searchCtrl.clear();
                        });
                      },
                      child: const Text('Limpiar filtros'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (catalog.loading && catalog.items.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (catalog.error != null && catalog.items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 56),
                          const SizedBox(height: 10),
                          Text(catalog.error ?? 'Error cargando productos'),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => ref
                                .read(catalogControllerProvider.notifier)
                                .load(forceRemote: true),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 10),
                          const Text('No hay productos para mostrar'),
                        ],
                      ),
                    );
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      if (_isDesktopWidth(constraints.maxWidth)) {
                        return _DesktopCatalogLayout(
                          products: filtered,
                          totalProducts: catalog.items.length,
                          categories: categories,
                          categoryCounts: categoryCounts,
                          selectedCategory: _category,
                          query: _searchCtrl.text.trim(),
                          isAdmin: isAdmin,
                          canManage: canManage,
                          onSelectCategory: (value) {
                            if (_category == value) return;
                            setState(() => _category = value);
                          },
                          onClearFilters: () {
                            setState(() {
                              _category = 'Todas';
                              _searchCtrl.clear();
                            });
                          },
                          onRefresh: () => ref
                              .read(catalogControllerProvider.notifier)
                              .load(forceRemote: true),
                          onViewProduct: (product) => _showProductDetails(
                            product: product,
                            showCost: isAdmin,
                            canManage: canManage,
                            onEdit: () => _openProductForm(
                              product: product,
                              categories: categoryOptions,
                            ),
                            onDelete: () => _confirmDelete(product),
                          ),
                          onEditProduct: (product) => _openProductForm(
                            product: product,
                            categories: categoryOptions,
                          ),
                          onDeleteProduct: _confirmDelete,
                        );
                      }

                      final width = constraints.maxWidth;
                      final columns = width >= 1320
                          ? 6
                          : width >= 1080
                          ? 5
                          : width >= 820
                          ? 4
                          : width >= 560
                          ? 3
                          : 2;

                      const spacing = 10.0;
                      final cardWidth =
                          (width - spacing * (columns - 1)) / columns;
                      final tileHeight = (cardWidth * 0.84).clamp(108.0, 172.0);

                      return RefreshIndicator(
                        onRefresh: () => ref
                            .read(catalogControllerProvider.notifier)
                            .load(forceRemote: true),
                        child: GridView.builder(
                          itemCount: filtered.length,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                mainAxisSpacing: spacing,
                                crossAxisSpacing: spacing,
                                mainAxisExtent: tileHeight,
                              ),
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            return _ProductCard(
                              product: p,
                              showCost: isAdmin,
                              canManage: canManage,
                              onView: () => _showProductDetails(
                                product: p,
                                showCost: isAdmin,
                                canManage: canManage,
                                onEdit: () => _openProductForm(
                                  product: p,
                                  categories: categoryOptions,
                                ),
                                onDelete: () => _confirmDelete(p),
                              ),
                              onEdit: () => _openProductForm(
                                product: p,
                                categories: categoryOptions,
                              ),
                              onDelete: () => _confirmDelete(p),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCategoryFilter(List<String> categories) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: categories.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final option = categories[index];
              final selected = option == _category;
              return ListTile(
                dense: true,
                title: Text(option, overflow: TextOverflow.ellipsis),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, option),
              );
            },
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _category = selected);
  }

  Future<void> _confirmDelete(ProductModel product) async {
    final controller = ref.read(catalogControllerProvider.notifier);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar producto'),
          content: Text('¿Eliminar "${product.nombre}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await controller.remove(product.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Producto eliminado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  void _openProductForm({
    ProductModel? product,
    required List<String> categories,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            top: 16,
          ),
          child: _ProductForm(
            product: product,
            categories: categories,
            onSaved: () => Navigator.pop(context),
          ),
        );
      },
    );
  }

  Future<void> _importProductsFromCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;

    try {
      final content = utf8.decode(bytes, allowMalformed: true);
      final drafts = _parseProductCsv(content);
      if (drafts.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron productos válidos para importar'),
          ),
        );
        return;
      }

      final imported = await ref
          .read(catalogControllerProvider.notifier)
          .importProducts(drafts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Se importaron $imported productos')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo importar: $e')));
    }
  }

  List<CatalogImportDraft> _parseProductCsv(String content) {
    final lines = const LineSplitter()
        .convert(content)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];

    final first = _parseCsvLine(lines.first);
    final normalizedFirst = first.map(_normalizeCsvHeader).toList();
    final hasHeader = normalizedFirst.any(
      (value) =>
          value == 'nombre' ||
          value == 'producto' ||
          value == 'precio' ||
          value == 'costo',
    );

    int indexOf(List<String> keys, int fallback) {
      for (final key in keys) {
        final index = normalizedFirst.indexOf(key);
        if (index >= 0) return index;
      }
      return fallback;
    }

    final nameIndex = hasHeader
        ? indexOf(['nombre', 'producto', 'name'], 0)
        : 0;
    final priceIndex = hasHeader ? indexOf(['precio', 'price'], 1) : 1;
    final costIndex = hasHeader ? indexOf(['costo', 'cost'], 2) : 2;
    final stockIndex = hasHeader
        ? indexOf(['stock', 'existencia', 'cantidad', 'quantity'], 3)
        : 3;
    final categoryIndex = hasHeader
        ? indexOf(['categoria', 'category', 'familia'], 4)
        : 4;

    final dataLines = hasHeader ? lines.skip(1) : lines;
    final drafts = <CatalogImportDraft>[];
    for (final line in dataLines) {
      final cells = _parseCsvLine(line);
      String cell(int index) =>
          index >= 0 && index < cells.length ? cells[index].trim() : '';

      final nombre = cell(nameIndex);
      final precio = _parseCatalogNumber(cell(priceIndex));
      final costo = _parseCatalogNumber(cell(costIndex));
      final stock = _parseCatalogNumber(cell(stockIndex)) ?? 0;
      final categoria = cell(categoryIndex).isEmpty
          ? 'Sin categoría'
          : cell(categoryIndex);

      if (nombre.isEmpty || precio == null || costo == null) continue;
      drafts.add(
        CatalogImportDraft(
          nombre: nombre,
          precio: precio,
          costo: costo,
          stock: stock,
          categoria: categoria,
        ),
      );
    }
    return drafts;
  }

  String _normalizeCsvHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');
  }

  List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i += 1;
        } else {
          quoted = !quoted;
        }
      } else if ((char == ',' || char == ';' || char == '\t') && !quoted) {
        values.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString());
    return values;
  }

  Future<void> _openCatalogSearch({
    required List<ProductModel> products,
    required bool showCost,
    required bool canManage,
    required List<String> categories,
  }) async {
    final result = await showSearch<_CatalogSearchResult?>(
      context: context,
      delegate: _CatalogSearchDelegate(
        products: products,
        initialQuery: _searchCtrl.text.trim(),
      ),
    );
    if (!mounted || result == null) return;

    final nextQuery = result.query.trim();
    if (nextQuery != _searchCtrl.text.trim()) {
      setState(() {
        _searchCtrl.text = nextQuery;
      });
    }

    final product = result.selectedProduct;
    if (product == null) return;

    await _showProductDetails(
      product: product,
      showCost: showCost,
      canManage: canManage,
      onEdit: () => _openProductForm(product: product, categories: categories),
      onDelete: () => _confirmDelete(product),
    );
  }

  Future<void> _showProductDetails({
    required ProductModel product,
    required bool showCost,
    required bool canManage,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) async {
    if (_isDesktopWidth(MediaQuery.of(context).size.width)) {
      await showDialog<void>(
        context: context,
        builder: (context) => _DesktopProductDetailDialog(
          product: product,
          showCost: showCost,
          canManage: canManage,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final imageUrl = product.displayFotoUrl;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.image_outlined,
                              size: 38,
                              color: theme.colorScheme.outline,
                            ),
                          )
                        : ProductNetworkImage(
                            imageUrl: imageUrl,
                            productId: product.id,
                            productName: product.nombre,
                            originalUrl: product.originalFotoUrl,
                            fit: BoxFit.cover,
                            loading: Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            fallback: Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.broken_image_outlined,
                                size: 38,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  product.nombre,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _ProductDetailLine(
                  label: 'Categoría',
                  value: product.categoriaLabel,
                ),
                _ProductDetailLine(
                  label: 'Disponible',
                  value: _formatStock(product.stock),
                ),
                _ProductDetailLine(
                  label: 'Precio',
                  value: formatRdAccountingAmount(product.precio),
                ),
                if (showCost)
                  _ProductDetailLine(
                    label: 'Costo',
                    value: formatRdAccountingAmount(product.costo),
                  ),
                _ProductDetailLine(
                  label: 'Fecha',
                  value: product.createdAt == null
                      ? '—'
                      : '${product.createdAt!.day.toString().padLeft(2, '0')}/${product.createdAt!.month.toString().padLeft(2, '0')}/${product.createdAt!.year}',
                ),
                if (canManage) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onEdit();
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            onDelete();
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Eliminar'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CatalogSearchResult {
  const _CatalogSearchResult({required this.query, this.selectedProduct});

  final String query;
  final ProductModel? selectedProduct;
}

class _CatalogSearchDelegate extends SearchDelegate<_CatalogSearchResult?> {
  _CatalogSearchDelegate({required this.products, required String initialQuery})
    : super(searchFieldLabel: 'Buscar producto') {
    query = initialQuery;
  }

  final List<ProductModel> products;

  List<ProductModel> get _filteredProducts {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = products
        .where((product) {
          if (normalizedQuery.isEmpty) return true;
          return product.nombre.toLowerCase().contains(normalizedQuery) ||
              product.categoriaLabel.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    filtered.sort(
      (left, right) =>
          left.nombre.toLowerCase().compareTo(right.nombre.toLowerCase()),
    );
    return filtered;
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(toolbarHeight: 64),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.trim().isNotEmpty)
        IconButton(
          tooltip: 'Limpiar búsqueda',
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
          icon: const Icon(Icons.close_rounded),
        ),
      IconButton(
        tooltip: 'Aplicar búsqueda',
        onPressed: () =>
            close(context, _CatalogSearchResult(query: query.trim())),
        icon: const Icon(Icons.check_rounded),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Cerrar',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final filtered = _filteredProducts;
    if (products.isEmpty) {
      return const Center(child: Text('No hay productos disponibles'));
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No se encontraron productos',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = filtered[index];
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          leading: CircleAvatar(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: 0.12),
            child: const Icon(Icons.inventory_2_rounded),
          ),
          title: Text(
            product.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            product.categoriaLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            formatRdAccountingAmount(product.precio),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          onTap: () => close(
            context,
            _CatalogSearchResult(query: query.trim(), selectedProduct: product),
          ),
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final bool showCost;
  final bool canManage;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.showCost,
    required this.canManage,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 1100) {
      return _DesktopProductCard(
        product: product,
        showCost: showCost,
        canManage: canManage,
        onView: onView,
        onEdit: onEdit,
        onDelete: onDelete,
      );
    }

    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 700;
    final imageUrl = product.displayFotoUrl;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onView,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl == null || imageUrl.isEmpty)
              Container(
                color: theme.colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(
                  Icons.image_outlined,
                  size: 28,
                  color: theme.colorScheme.outline,
                ),
              )
            else
              ProductNetworkImage(
                imageUrl: imageUrl,
                productId: product.id,
                productName: product.nombre,
                originalUrl: product.originalFotoUrl,
                fit: BoxFit.cover,
                loading: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                fallback: Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 28,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x30000000), Color(0xB0000000)],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x7A000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  product.categoriaLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (canManage)
              Positioned(
                top: 2,
                right: 2,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  color: theme.colorScheme.surface,
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 11 : 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.categoriaLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: compact ? 9.5 : 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Precio ${formatRdAccountingAmount(product.precio)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 10 : 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Disponible ${_formatStock(product.stock)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 9.5 : 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (showCost)
                    Text(
                      'Costo ${formatRdAccountingAmount(product.costo)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 9.5 : 10.5,
                        fontWeight: FontWeight.w500,
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

class _DesktopCatalogLayout extends StatelessWidget {
  const _DesktopCatalogLayout({
    required this.products,
    required this.totalProducts,
    required this.categories,
    required this.categoryCounts,
    required this.selectedCategory,
    required this.query,
    required this.isAdmin,
    required this.canManage,
    required this.onSelectCategory,
    required this.onClearFilters,
    required this.onRefresh,
    required this.onViewProduct,
    required this.onEditProduct,
    required this.onDeleteProduct,
  });

  final List<ProductModel> products;
  final int totalProducts;
  final List<String> categories;
  final Map<String, int> categoryCounts;
  final String selectedCategory;
  final String query;
  final bool isAdmin;
  final bool canManage;
  final ValueChanged<String> onSelectCategory;
  final VoidCallback onClearFilters;
  final Future<void> Function() onRefresh;
  final ValueChanged<ProductModel> onViewProduct;
  final ValueChanged<ProductModel> onEditProduct;
  final ValueChanged<ProductModel> onDeleteProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1650
        ? 6
        : width >= 1320
        ? 5
        : 4;

    return Row(
      children: [
        SizedBox(
          width: 280,
          child: _CatalogDesktopSidebar(
            categories: categories,
            categoryCounts: categoryCounts,
            selectedCategory: selectedCategory,
            onSelectCategory: onSelectCategory,
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: theme.colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 30,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    sliver: products.isEmpty
                        ? SliverFillRemaining(
                            hasScrollBody: false,
                            child: _CatalogDesktopEmptyState(
                              onClearFilters: onClearFilters,
                              canClearFilters:
                                  selectedCategory != 'Todas' ||
                                  query.isNotEmpty,
                            ),
                          )
                        : SliverGrid(
                            delegate: SliverChildBuilderDelegate((context, i) {
                              final product = products[i];
                              return _ProductCard(
                                product: product,
                                showCost: isAdmin,
                                canManage: canManage,
                                onView: () => onViewProduct(product),
                                onEdit: () => onEditProduct(product),
                                onDelete: () => onDeleteProduct(product),
                              );
                            }, childCount: products.length),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  mainAxisExtent: 198,
                                ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CatalogDesktopSidebar extends StatelessWidget {
  const _CatalogDesktopSidebar({
    required this.categories,
    required this.categoryCounts,
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  final List<String> categories;
  final Map<String, int> categoryCounts;
  final String selectedCategory;
  final ValueChanged<String> onSelectCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.92),
            const Color(0xFF0B1220),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.20),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Categorías',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Navega el catálogo por familia de productos con una vista pensada para escritorio.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0x26FFFFFF), height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = category == selectedCategory;
                final count = categoryCounts[category] ?? 0;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => onSelectCategory(category),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? theme.colorScheme.primary.withValues(
                                        alpha: 0.10,
                                      )
                                    : Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '$count',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopInfoChip extends StatelessWidget {
  const _DesktopInfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: theme.textTheme.labelSmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CatalogDesktopEmptyState extends StatelessWidget {
  const _CatalogDesktopEmptyState({
    required this.onClearFilters,
    required this.canClearFilters,
  });

  final VoidCallback onClearFilters;
  final bool canClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 62,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 14),
          Text(
            'No hay productos para esta vista',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Prueba otra categoría o limpia los filtros para ver más resultados.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (canClearFilters) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.refresh),
              label: const Text('Restablecer vista'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DesktopProductCard extends StatelessWidget {
  const _DesktopProductCard({
    required this.product,
    required this.showCost,
    required this.canManage,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductModel product;
  final bool showCost;
  final bool canManage;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = product.displayFotoUrl;
    final overlayDecoration = BoxDecoration(
      color: Colors.black.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onView,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 7,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: imageUrl == null || imageUrl.isEmpty
                            ? Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 44,
                                  color: theme.colorScheme.outline,
                                ),
                              )
                            : ProductNetworkImage(
                                imageUrl: imageUrl,
                                productId: product.id,
                                productName: product.nombre,
                                originalUrl: product.originalFotoUrl,
                                fit: BoxFit.cover,
                                loading: Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                fallback: Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 40,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x18000000), Color(0xA6000000)],
                            stops: [0.1, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 100),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          product.categoriaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: overlayDecoration,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Precio',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: Colors.white70,
                                            fontSize: 9,
                                          ),
                                    ),
                                    Text(
                                      formatRdAccountingAmount(product.precio),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 10,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (showCost)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: overlayDecoration,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Costo',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: Colors.white70,
                                              fontSize: 9,
                                            ),
                                      ),
                                      Text(
                                        formatRdAccountingAmount(product.costo),
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 10,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: overlayDecoration,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Stock',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: Colors.white70,
                                            fontSize: 9,
                                          ),
                                    ),
                                    Text(
                                      _formatStock(product.stock),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 10,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (canManage)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: PopupMenuButton<String>(
                          icon: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.32),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(
                              Icons.more_horiz,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          onSelected: (value) {
                            if (value == 'edit') onEdit();
                            if (value == 'delete') onDelete();
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Eliminar'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: Row(
                    children: [
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: theme.colorScheme.primary,
                        size: 15,
                      ),
                    ],
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

class _DesktopProductDetailDialog extends StatelessWidget {
  const _DesktopProductDetailDialog({
    required this.product,
    required this.showCost,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductModel product;
  final bool showCost;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = product.displayFotoUrl;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 42),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
        child: Row(
          children: [
            Expanded(
              flex: 6,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(28),
                ),
                child: imageUrl == null || imageUrl.isEmpty
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.image_outlined,
                          size: 58,
                          color: theme.colorScheme.outline,
                        ),
                      )
                    : ProductNetworkImage(
                        imageUrl: imageUrl,
                        productId: product.id,
                        productName: product.nombre,
                        originalUrl: product.originalFotoUrl,
                        fit: BoxFit.cover,
                        loading: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        fallback: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.broken_image_outlined,
                            size: 58,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.nombre,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _DesktopInfoChip(
                          icon: Icons.category_outlined,
                          label: 'Categoría',
                          value: product.categoriaLabel,
                        ),
                        _DesktopInfoChip(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stock',
                          value: _formatStock(product.stock),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _ProductDetailLine(
                      label: 'Precio',
                      value: formatRdAccountingAmount(product.precio),
                    ),
                    if (showCost)
                      _ProductDetailLine(
                        label: 'Costo',
                        value: formatRdAccountingAmount(product.costo),
                      ),
                    _ProductDetailLine(
                      label: 'Disponible',
                      value: _formatStock(product.stock),
                    ),
                    _ProductDetailLine(
                      label: 'Fecha',
                      value: product.createdAt == null
                          ? '—'
                          : '${product.createdAt!.day.toString().padLeft(2, '0')}/${product.createdAt!.month.toString().padLeft(2, '0')}/${product.createdAt!.year}',
                    ),
                    if ((product.descripcion ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text(
                        'Descripción',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.descripcion!.trim(),
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ],
                    const Spacer(),
                    if (canManage)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onEdit();
                              },
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Editar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.error,
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                onDelete();
                              },
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Eliminar'),
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
      ),
    );
  }
}

class _ProductDetailLine extends StatelessWidget {
  const _ProductDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _ProductForm extends ConsumerStatefulWidget {
  final ProductModel? product;
  final VoidCallback onSaved;
  final List<String> categories;

  const _ProductForm({
    required this.product,
    required this.onSaved,
    required this.categories,
  });

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _categoryCtrl;
  Uint8List? _imageBytes;
  String? _imageName;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.nombre ?? '');
    _priceCtrl = TextEditingController(
      text: widget.product?.precio.toStringAsFixed(2) ?? '',
    );
    _costCtrl = TextEditingController(
      text: widget.product?.costo.toStringAsFixed(2) ?? '',
    );
    _stockCtrl = TextEditingController(
      text: widget.product?.stock?.toStringAsFixed(2) ?? '0',
    );
    final initialCategory = widget.product?.categoriaLabel;
    _categoryCtrl = TextEditingController(
      text: initialCategory == 'Sin categoría' ? '' : (initialCategory ?? ''),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() {
        _imageBytes = result.files.single.bytes;
        _imageName = result.files.single.name;
      });
    }
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final price = _parseCatalogNumber(_priceCtrl.text);
    final cost = _parseCatalogNumber(_costCtrl.text);
    final stock = _parseCatalogNumber(_stockCtrl.text);
    final category = _categoryCtrl.text.trim();

    if (name.isEmpty || price == null || cost == null || stock == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Completa nombre, precio, costo y stock con valores válidos',
          ),
        ),
      );
      return;
    }

    if (category.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Agrega una categoría')));
      return;
    }

    if (widget.product == null && _imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una imagen para el producto')),
      );
      return;
    }

    setState(() => _saving = true);
    final controller = ref.read(catalogControllerProvider.notifier);

    try {
      if (widget.product == null) {
        await controller.create(
          nombre: name,
          precio: price,
          costo: cost,
          stock: stock,
          imageBytes: _imageBytes!,
          filename: _imageName ?? 'producto.png',
          categoria: category,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Producto creado')));
      } else {
        await controller.update(
          id: widget.product!.id,
          nombre: name,
          precio: price,
          costo: cost,
          stock: stock,
          newImageBytes: _imageBytes,
          newFilename: _imageName,
          categoria: category,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Producto actualizado')));
      }

      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isEdit ? 'Editar producto' : 'Crear producto',
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _saving ? null : () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Precio'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Costo'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _stockCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Stock disponible'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            decoration: const InputDecoration(
              labelText: 'Categoría (elige o crea)',
            ),
          ),
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.categories
                  .map(
                    (c) => ChoiceChip(
                      label: Text(c),
                      selected: _categoryCtrl.text.trim() == c,
                      onSelected: (_) => _categoryCtrl.text = c,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          Text('Imagen', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _pickImage,
                  icon: const Icon(Icons.file_upload),
                  label: Text(
                    _imageName ?? 'Seleccionar archivo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _imageBytes!,
                    height: 64,
                    width: 64,
                    fit: BoxFit.cover,
                  ),
                )
              else if (isEdit && widget.product?.displayFotoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 64,
                    width: 64,
                    child: ProductNetworkImage(
                      imageUrl: widget.product!.displayFotoUrl!,
                      productId: widget.product!.id,
                      productName: widget.product!.nombre,
                      originalUrl: widget.product!.originalFotoUrl,
                      fit: BoxFit.cover,
                      loading: Container(
                        height: 64,
                        width: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      fallback: Container(
                        height: 64,
                        width: 64,
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(isEdit ? 'Guardar cambios' : 'Crear producto'),
          ),
        ],
      ),
    );
  }
}
