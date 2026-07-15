import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/product_model.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/product_network_image.dart';
import '../../catalogo/application/catalog_controller.dart';
import '../../catalogo/data/catalog_repository.dart';

const _primaryBlue = Color(0xFF1A56DB);
const _lightBlueHover = Color(0xFFEFF6FF);
const _textPrimary = Color(0xFF0F172A);
const _textSecondary = Color(0xFF64748B);
const _borderSoft = Color(0xFFE2E8F0);
const _pageBackground = Color(0xFFEFF4FA);

String _stockText(double? value) {
  if (value == null) return '0';
  return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
}

double _stockOf(ProductModel product) => product.stock ?? 0;
double _profitOf(ProductModel product) => product.precio - product.costo;
double _marginOf(ProductModel product) {
  if (product.costo <= 0) return 0;
  return (_profitOf(product) / product.costo) * 100;
}

bool _isOutOfStock(ProductModel product) => _stockOf(product) <= 0;
bool _isLowStock(ProductModel product) {
  final stock = _stockOf(product);
  return stock > 0 && stock <= 3;
}

double? _parseInventoryNumber(String raw) {
  var value = raw
      .trim()
      .replaceAll('RD\$', '')
      .replaceAll('rd\$', '')
      .replaceAll(' ', '');
  if (value.isEmpty) return null;
  if (value.contains(',') && value.contains('.')) {
    value = value.replaceAll(',', '');
  } else {
    value = value.replaceAll(',', '.');
  }
  return double.tryParse(value);
}

class InventoryModulePages extends ConsumerStatefulWidget {
  const InventoryModulePages({super.key});

  @override
  ConsumerState<InventoryModulePages> createState() =>
      _InventoryModulePagesState();
}

class _InventoryModulePagesState extends ConsumerState<InventoryModulePages> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(catalogControllerProvider.notifier).load(silent: true);
    });
  }

  Future<void> _refresh() {
    return ref.read(catalogControllerProvider.notifier).load(forceRemote: true);
  }

  List<String> _categoryOptions(List<ProductModel> products) {
    final categories = products
        .map((product) => product.categoriaLabel)
        .where((category) => category.trim().isNotEmpty)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  Future<void> _openProductEditor({ProductModel? product}) {
    return _showInventoryProductEditor(
      context,
      ref,
      product: product,
      categories: _categoryOptions(ref.read(catalogControllerProvider).items),
    );
  }

  Future<void> _setProductStock(ProductModel product, double stock) async {
    await ref
        .read(catalogControllerProvider.notifier)
        .adjustStock(product: product, stock: stock);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Stock actualizado: ${product.nombre}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final state = ref.watch(catalogControllerProvider);
    final products = state.items;
    final tab = GoRouterState.of(context).uri.queryParameters['tab'];
    final initialTabIndex = switch (tab) {
      'inventory' => 1,
      'stock' => 2,
      'categories' => 3,
      _ => 0,
    };

    return DefaultTabController(
      length: 4,
      initialIndex: initialTabIndex,
      child: Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        backgroundColor: _pageBackground,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: _textPrimary,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: const Border(bottom: BorderSide(color: _borderSoft)),
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Menú',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          ),
          title: const Text(
            'Inventario',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          actions: [
            FilledButton.icon(
              onPressed: () => _openProductEditor(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nuevo producto'),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: state.refreshing ? null : _refresh,
              icon: state.refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: _primaryBlue,
            unselectedLabelColor: _textSecondary,
            indicatorColor: _primaryBlue,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            tabs: [
              Tab(icon: Icon(Icons.table_rows_outlined), text: 'Catálogo'),
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Inventario'),
              Tab(icon: Icon(Icons.tune_outlined), text: 'Ajuste Stock'),
              Tab(icon: Icon(Icons.category_outlined), text: 'Categorías'),
            ],
          ),
        ),
        body: state.loading && products.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  CatalogTab(
                    products: products,
                    loading: state.refreshing,
                    error: state.error,
                    onRefresh: _refresh,
                    onCreate: () => _openProductEditor(),
                    onEdit: (product) => _openProductEditor(product: product),
                    onSetStock: _setProductStock,
                    onDelete: (product) => ref
                        .read(catalogControllerProvider.notifier)
                        .remove(product.id),
                  ),
                  InventoryTab(products: products, onRefresh: _refresh),
                  StockAdjustmentsPage(
                    products: products,
                    onRefresh: _refresh,
                    onSetStock: _setProductStock,
                  ),
                  CategoriesTab(products: products, onRefresh: _refresh),
                ],
              ),
      ),
    );
  }
}

class ProductsSurface extends StatelessWidget {
  const ProductsSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 14,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

EdgeInsets productsResponsivePagePadding(
  BoxConstraints constraints, {
  double top = 14,
  double bottom = 18,
}) {
  final width = constraints.maxWidth;
  final fraction = width >= 1200 ? 0.96 : (width >= 760 ? 0.94 : 0.95);
  final contentWidth = (width * fraction).clamp(0.0, 1400.0);
  final horizontal = ((width - contentWidth) / 2).clamp(10.0, 28.0);
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}

class CatalogTab extends StatefulWidget {
  const CatalogTab({
    super.key,
    required this.products,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onCreate,
    required this.onEdit,
    required this.onSetStock,
    required this.onDelete,
  });

  final List<ProductModel> products;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;
  final ValueChanged<ProductModel> onEdit;
  final Future<void> Function(ProductModel product, double stock) onSetStock;
  final Future<void> Function(ProductModel product) onDelete;

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  final _searchCtrl = TextEditingController();
  final _selectedIds = <String>{};
  Timer? _debounce;
  String _query = '';
  String? _category;
  bool _onlyLowStock = false;
  bool _onlyOutStock = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final values = widget.products
        .map((product) => product.categoriaLabel)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  List<ProductModel> get _visible {
    final query = _query.trim().toLowerCase();
    return widget.products.where((product) {
      if (_category != null && product.categoriaLabel != _category) {
        return false;
      }
      if (_onlyLowStock && !_isLowStock(product)) return false;
      if (_onlyOutStock && !_isOutOfStock(product)) return false;
      if (query.isEmpty) return true;
      return product.nombre.toLowerCase().contains(query) ||
          (product.codigo ?? '').toLowerCase().contains(query) ||
          product.categoriaLabel.toLowerCase().contains(query);
    }).toList();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _selectAllVisible(bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.addAll(_visible.map((product) => product.id));
      } else {
        _selectedIds.removeAll(_visible.map((product) => product.id));
      }
    });
  }

  Future<void> _confirmDelete(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Deseas eliminar "${product.nombre}" del catálogo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onDelete(product);
    if (!mounted) return;
    setState(() => _selectedIds.remove(product.id));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final allSelected =
        visible.isNotEmpty &&
        visible.every((product) => _selectedIds.contains(product.id));

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              _CatalogToolbar(
                controller: _searchCtrl,
                categories: _categories,
                selectedCategory: _category,
                onlyLowStock: _onlyLowStock,
                onlyOutStock: _onlyOutStock,
                selectedCount: _selectedIds.length,
                onSearchChanged: _onSearchChanged,
                onCategoryChanged: (value) => setState(() => _category = value),
                onToggleLowStock: (value) =>
                    setState(() => _onlyLowStock = value),
                onToggleOutStock: (value) =>
                    setState(() => _onlyOutStock = value),
                onClearFilters: () => setState(() {
                  _category = null;
                  _onlyLowStock = false;
                  _onlyOutStock = false;
                  _searchCtrl.clear();
                  _query = '';
                }),
                onCreate: widget.onCreate,
              ),
              const SizedBox(height: 12),
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _InlineWarning(message: widget.error!),
                ),
              if (compact)
                _CompactCatalogList(
                  products: visible,
                  selectedIds: _selectedIds,
                  onToggle: (product, value) => setState(() {
                    value
                        ? _selectedIds.add(product.id)
                        : _selectedIds.remove(product.id);
                  }),
                  onEdit: widget.onEdit,
                  onSetStock: widget.onSetStock,
                  onDelete: _confirmDelete,
                )
              else
                _CatalogTable(
                  products: visible,
                  selectedIds: _selectedIds,
                  allSelected: allSelected,
                  onToggleAll: _selectAllVisible,
                  onToggle: (product, value) => setState(() {
                    value
                        ? _selectedIds.add(product.id)
                        : _selectedIds.remove(product.id);
                  }),
                  onEdit: widget.onEdit,
                  onSetStock: widget.onSetStock,
                  onDelete: _confirmDelete,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CatalogToolbar extends StatelessWidget {
  const _CatalogToolbar({
    required this.controller,
    required this.categories,
    required this.selectedCategory,
    required this.onlyLowStock,
    required this.onlyOutStock,
    required this.selectedCount,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onToggleLowStock,
    required this.onToggleOutStock,
    required this.onClearFilters,
    required this.onCreate,
  });

  final TextEditingController controller;
  final List<String> categories;
  final String? selectedCategory;
  final bool onlyLowStock;
  final bool onlyOutStock;
  final int selectedCount;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<bool> onToggleLowStock;
  final ValueChanged<bool> onToggleOutStock;
  final VoidCallback onClearFilters;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ProductsSurface(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Buscar por nombre, código o categoría',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: selectedCategory,
              hint: const Text('Todas las categorías'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todas las categorías'),
                ),
                for (final category in categories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: onCategoryChanged,
            ),
          ),
          FilterChip(
            label: const Text('Stock bajo'),
            selected: onlyLowStock,
            onSelected: onToggleLowStock,
          ),
          FilterChip(
            label: const Text('Agotados'),
            selected: onlyOutStock,
            onSelected: onToggleOutStock,
          ),
          OutlinedButton.icon(
            onPressed: onClearFilters,
            icon: const Icon(Icons.cleaning_services_outlined, size: 17),
            label: const Text('Limpiar'),
          ),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('Nuevo producto'),
          ),
          if (selectedCount > 0)
            Chip(
              backgroundColor: _lightBlueHover,
              label: Text('$selectedCount seleccionados'),
            ),
        ],
      ),
    );
  }
}

class _CatalogTable extends StatelessWidget {
  const _CatalogTable({
    required this.products,
    required this.selectedIds,
    required this.allSelected,
    required this.onToggleAll,
    required this.onToggle,
    required this.onEdit,
    required this.onSetStock,
    required this.onDelete,
  });

  final List<ProductModel> products;
  final Set<String> selectedIds;
  final bool allSelected;
  final ValueChanged<bool> onToggleAll;
  final void Function(ProductModel product, bool selected) onToggle;
  final ValueChanged<ProductModel> onEdit;
  final Future<void> Function(ProductModel product, double stock) onSetStock;
  final ValueChanged<ProductModel> onDelete;

  @override
  Widget build(BuildContext context) {
    return ProductsSurface(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            color: _textSecondary,
            fontSize: 12,
          ),
          columns: [
            DataColumn(
              label: Checkbox(
                value: allSelected,
                onChanged: (value) => onToggleAll(value ?? false),
              ),
            ),
            const DataColumn(label: Text('Código')),
            const DataColumn(label: Text('Nombre')),
            const DataColumn(label: Text('Categoría')),
            const DataColumn(label: Text('Costo'), numeric: true),
            const DataColumn(label: Text('Precio'), numeric: true),
            const DataColumn(label: Text('Stock'), numeric: true),
            const DataColumn(label: Text('Ganancia'), numeric: true),
            const DataColumn(label: Text('Margen'), numeric: true),
            const DataColumn(label: Text('Acciones')),
          ],
          rows: [
            for (final product in products)
              DataRow(
                selected: selectedIds.contains(product.id),
                cells: [
                  DataCell(
                    Checkbox(
                      value: selectedIds.contains(product.id),
                      onChanged: (value) => onToggle(product, value ?? false),
                    ),
                  ),
                  DataCell(Text(product.codigo ?? product.id)),
                  DataCell(_ProductNameCell(product: product)),
                  DataCell(Text(product.categoriaLabel)),
                  DataCell(_MoneyText(product.costo)),
                  DataCell(_MoneyText(product.precio)),
                  DataCell(_StockBadge(product: product)),
                  DataCell(_MoneyText(_profitOf(product))),
                  DataCell(Text('${_marginOf(product).toStringAsFixed(1)}%')),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar',
                          onPressed: () => onEdit(product),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Ajustar stock',
                          onPressed: () => _showStockAdjustmentPanel(
                            context,
                            product: product,
                            onSetStock: onSetStock,
                          ),
                          icon: const Icon(Icons.tune_outlined),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: () => onDelete(product),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
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

class _CompactCatalogList extends StatelessWidget {
  const _CompactCatalogList({
    required this.products,
    required this.selectedIds,
    required this.onToggle,
    required this.onEdit,
    required this.onSetStock,
    required this.onDelete,
  });

  final List<ProductModel> products;
  final Set<String> selectedIds;
  final void Function(ProductModel product, bool selected) onToggle;
  final ValueChanged<ProductModel> onEdit;
  final Future<void> Function(ProductModel product, double stock) onSetStock;
  final ValueChanged<ProductModel> onDelete;

  @override
  Widget build(BuildContext context) {
    return ProductsSurface(
      child: Column(
        children: [
          for (final product in products)
            CompactProductCard(
              product: product,
              selected: selectedIds.contains(product.id),
              onSelected: (value) => onToggle(product, value),
              onEdit: () => onEdit(product),
              onStock: () => _showStockAdjustmentPanel(
                context,
                product: product,
                onSetStock: onSetStock,
              ),
              onDelete: () => onDelete(product),
            ),
        ],
      ),
    );
  }
}

class InventoryTab extends StatelessWidget {
  const InventoryTab({
    super.key,
    required this.products,
    required this.onRefresh,
  });

  final List<ProductModel> products;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final active = products.where((product) => product.activo).toList();
    final totalCost = active.fold<double>(
      0,
      (sum, product) => sum + (_stockOf(product) * product.costo),
    );
    final totalRevenue = active.fold<double>(
      0,
      (sum, product) => sum + (_stockOf(product) * product.precio),
    );
    final totalUnits = active.fold<double>(0, (sum, p) => sum + _stockOf(p));
    final lowStock = active.where(_isLowStock).length;
    final outStock = active.where(_isOutOfStock).length;
    final profit = totalRevenue - totalCost;
    final margin = totalCost <= 0 ? 0 : (profit / totalCost) * 100;

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  KpiCard(
                    title: 'Inversión Total',
                    value: formatRdCurrencyAccounting(totalCost),
                    icon: Icons.account_balance_wallet_outlined,
                    color: _primaryBlue,
                  ),
                  KpiCard(
                    title: 'Valor de Venta',
                    value: formatRdCurrencyAccounting(totalRevenue),
                    icon: Icons.sell_outlined,
                    color: const Color(0xFF16A34A),
                  ),
                  KpiCard(
                    title: 'Ganancia Potencial',
                    value: formatRdCurrencyAccounting(profit),
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF7C3AED),
                  ),
                  KpiCard(
                    title: 'Margen Promedio',
                    value: '${margin.toStringAsFixed(1)}%',
                    icon: Icons.percent_rounded,
                    color: const Color(0xFF0F766E),
                  ),
                  KpiCard(
                    title: 'Unidades en Stock',
                    value: _stockText(totalUnits),
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFF4F46E5),
                  ),
                  KpiCard(
                    title: 'Productos Activos',
                    value: '${active.length}',
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF0891B2),
                  ),
                  KpiCard(
                    title: 'Alertas activas',
                    value: '${lowStock + outStock}',
                    icon: Icons.warning_amber_rounded,
                    color: (lowStock + outStock) == 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFF97316),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _InventoryBreakdown(products: active),
            ],
          ),
        );
      },
    );
  }
}

class StockAdjustmentsPage extends StatefulWidget {
  const StockAdjustmentsPage({
    super.key,
    required this.products,
    required this.onRefresh,
    required this.onSetStock,
  });

  final List<ProductModel> products;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ProductModel product, double stock) onSetStock;

  @override
  State<StockAdjustmentsPage> createState() => _StockAdjustmentsPageState();
}

class _StockAdjustmentsPageState extends State<StockAdjustmentsPage> {
  ProductModel? _selected;
  String _mode = 'Incrementar';
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _quantity => _parseInventoryNumber(_qtyCtrl.text) ?? 0;

  double _previewStock(ProductModel product) {
    final stock = _stockOf(product);
    return switch (_mode) {
      'Disminuir' => stock - _quantity,
      'Fijar exacto' => _quantity,
      _ => stock + _quantity,
    };
  }

  Future<void> _applyAdjustment() async {
    final selected =
        _selected ??
        (widget.products.isNotEmpty ? widget.products.first : null);
    if (selected == null || _quantity < 0) return;
    final nextStock = _previewStock(selected);
    if (nextStock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El stock no puede quedar negativo')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSetStock(selected, nextStock);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ajuste aplicado: ${selected.nombre} ahora tiene ${_stockText(nextStock)}',
          ),
        ),
      );
      _noteCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo ajustar stock: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        _selected ??
        (widget.products.isNotEmpty ? widget.products.first : null);

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              ProductsSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'INVENTARIO',
                      style: TextStyle(
                        color: _primaryBlue,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Ajuste de stock',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ProductModel>(
                      key: ValueKey(selected?.id ?? 'empty-product'),
                      initialValue: selected,
                      items: [
                        for (final product in widget.products)
                          DropdownMenuItem(
                            value: product,
                            child: Text(
                              '${product.codigo ?? product.id} · ${product.nombre}',
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _selected = value),
                      decoration: const InputDecoration(
                        labelText: 'Producto',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Incrementar',
                          label: Text('Incrementar'),
                          icon: Icon(Icons.add_rounded),
                        ),
                        ButtonSegment(
                          value: 'Disminuir',
                          label: Text('Disminuir'),
                          icon: Icon(Icons.remove_rounded),
                        ),
                        ButtonSegment(
                          value: 'Fijar exacto',
                          label: Text('Fijar exacto'),
                          icon: Icon(Icons.edit_outlined),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (value) =>
                          setState(() => _mode = value.first),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Cantidad',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _noteCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nota',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      _InlineInfo(
                        icon: Icons.preview_outlined,
                        message:
                            'Stock actual ${_stockText(selected.stock)} → Nuevo stock ${_stockText(_previewStock(selected))}',
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _applyAdjustment,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: const Text('Guardar ajuste'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              ProductsSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Productos',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final product in widget.products.take(20))
                      CompactProductCard(
                        product: product,
                        selected: selected?.id == product.id,
                        onSelected: (_) => setState(() => _selected = product),
                        onStock: () => setState(() => _selected = product),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CategoriesTab extends StatelessWidget {
  const CategoriesTab({
    super.key,
    required this.products,
    required this.onRefresh,
  });

  final List<ProductModel> products;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final categories = <String, int>{};
    for (final product in products) {
      categories.update(
        product.categoriaLabel,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final rows = categories.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              ProductsSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionHeader(
                      title: 'Categorías',
                      subtitle: '${rows.length} categorías visibles',
                    ),
                    const SizedBox(height: 10),
                    if (rows.isEmpty)
                      const ProductsEmptyState(
                        icon: Icons.category_outlined,
                        title: 'Sin categorías',
                        message:
                            'Las categorías aparecerán cuando existan productos.',
                      )
                    else
                      for (final entry in rows)
                        _SimpleManagementTile(
                          icon: Icons.category_outlined,
                          title: entry.key,
                          subtitle: '${entry.value} productos',
                          badge: 'Activa',
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 214,
      height: 118,
      child: ProductsSurface(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: _textSecondary,
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompactProductCard extends StatelessWidget {
  const CompactProductCard({
    super.key,
    required this.product,
    this.selected = false,
    required this.onSelected,
    this.onEdit,
    this.onStock,
    this.onDelete,
  });

  final ProductModel product;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback? onEdit;
  final VoidCallback? onStock;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final statusColor = _isOutOfStock(product)
        ? Colors.red
        : _isLowStock(product)
        ? Colors.orange
        : _primaryBlue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? _lightBlueHover : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _primaryBlue : _borderSoft),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 3, color: statusColor),
              Checkbox(
                value: selected,
                onChanged: (v) => onSelected(v ?? false),
              ),
              ProductThumbnail(product: product, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      product.codigo ?? product.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      product.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      product.categoriaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _CompactMetric(label: 'Stock', value: _stockText(product.stock)),
              _CompactMetric(
                label: 'Valor',
                value: formatRdCurrencyAccounting(
                  _stockOf(product) * product.precio,
                ),
              ),
              _CompactMetric(
                label: 'Margen',
                value: '${_marginOf(product).toStringAsFixed(0)}%',
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Editar',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (onStock != null)
                TextButton(onPressed: onStock, child: const Text('Stock')),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({super.key, required this.product, this.size = 44});

  final ProductModel product;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.displayFotoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE6F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? const Icon(Icons.sell_outlined, color: Color(0xFFCBD5E1))
          : ProductNetworkImage(
              imageUrl: imageUrl,
              productId: product.id,
              productName: product.nombre,
              originalUrl: product.originalFotoUrl,
              fit: BoxFit.cover,
              loading: const SizedBox.shrink(),
              fallback: const Icon(
                Icons.sell_outlined,
                color: Color(0xFFCBD5E1),
              ),
            ),
    );
  }
}

class ProductsEmptyState extends StatelessWidget {
  const ProductsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 52, color: const Color(0xFFCBD5E1)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textSecondary),
          ),
        ],
      ),
    );
  }
}

class _InventoryBreakdown extends StatelessWidget {
  const _InventoryBreakdown({required this.products});

  final List<ProductModel> products;

  @override
  Widget build(BuildContext context) {
    final byCategory = <String, ({double units, double value})>{};
    for (final product in products) {
      final current =
          byCategory[product.categoriaLabel] ?? (units: 0, value: 0);
      byCategory[product.categoriaLabel] = (
        units: current.units + _stockOf(product),
        value: current.value + (_stockOf(product) * product.precio),
      );
    }
    final rows = byCategory.entries.toList()
      ..sort((a, b) => b.value.value.compareTo(a.value.value));

    return ProductsSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Inventario por categoría',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          for (final row in rows.take(12))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(row.key),
              subtitle: Text('${_stockText(row.value.units)} unidades'),
              trailing: Text(
                formatRdCurrencyAccounting(row.value.value),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProductNameCell extends StatelessWidget {
  const _ProductNameCell({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProductThumbnail(product: product, size: 36),
        const SizedBox(width: 10),
        SizedBox(
          width: 230,
          child: Text(
            product.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _MoneyText extends StatelessWidget {
  const _MoneyText(this.value);
  final double value;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatRdCurrencyAccounting(value),
      textAlign: TextAlign.right,
      style: const TextStyle(fontWeight: FontWeight.w800),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final color = _isOutOfStock(product)
        ? Colors.red
        : _isLowStock(product)
        ? Colors.orange
        : const Color(0xFF16A34A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _stockText(product.stock),
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: const TextStyle(color: _textSecondary, fontSize: 10),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              Text(subtitle, style: const TextStyle(color: _textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SimpleManagementTile extends StatelessWidget {
  const _SimpleManagementTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: _lightBlueHover,
        foregroundColor: _primaryBlue,
        child: Icon(icon),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: Chip(label: Text(badge)),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _InlineInfo(icon: Icons.warning_amber_rounded, message: message);
  }
}

class _InlineInfo extends StatelessWidget {
  const _InlineInfo({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _lightBlueHover,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _primaryBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showStockAdjustmentPanel(
  BuildContext context, {
  required ProductModel product,
  required Future<void> Function(ProductModel product, double stock) onSetStock,
}) {
  final qtyCtrl = TextEditingController(text: '1');
  var mode = 'Incrementar';
  var saving = false;

  double quantity() => _parseInventoryNumber(qtyCtrl.text) ?? 0;
  double preview() {
    final stock = _stockOf(product);
    return switch (mode) {
      'Disminuir' => stock - quantity(),
      'Fijar exacto' => quantity(),
      _ => stock + quantity(),
    };
  }

  Future<void> submit(
    BuildContext dialogContext,
    void Function(void Function()) setPanelState,
  ) async {
    final nextStock = preview();
    if (nextStock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El stock no puede quedar negativo')),
      );
      return;
    }
    setPanelState(() => saving = true);
    try {
      await onSetStock(product, nextStock);
      if (dialogContext.mounted) Navigator.pop(dialogContext);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo ajustar stock: $e')));
      }
    } finally {
      if (dialogContext.mounted) setPanelState(() => saving = false);
    }
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black45,
    builder: (sheetContext) {
      final size = MediaQuery.sizeOf(sheetContext);
      final panelWidth = size.width >= 640 ? 520.0 : size.width;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: panelWidth,
          height: size.height,
          child: StatefulBuilder(
            builder: (dialogContext, setPanelState) => Material(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ProductThumbnail(product: product, size: 56),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              Text(product.codigo ?? product.id),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _InlineInfo(
                      icon: Icons.inventory_2_outlined,
                      message:
                          'Stock actual: ${_stockText(product.stock)} · Valor: ${formatRdCurrencyAccounting(_stockOf(product) * product.precio)}',
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'Incrementar',
                          label: Text('Incrementar'),
                          icon: Icon(Icons.add_rounded),
                        ),
                        ButtonSegment(
                          value: 'Disminuir',
                          label: Text('Disminuir'),
                          icon: Icon(Icons.remove_rounded),
                        ),
                        ButtonSegment(
                          value: 'Fijar exacto',
                          label: Text('Fijar'),
                          icon: Icon(Icons.edit_outlined),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (value) {
                        setPanelState(() => mode = value.first);
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setPanelState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _InlineInfo(
                      icon: Icons.preview_outlined,
                      message: 'Nuevo stock: ${_stockText(preview())}',
                    ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () => submit(dialogContext, setPanelState),
                        icon: saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Guardar ajuste'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  ).whenComplete(qtyCtrl.dispose);
}

Future<void> _showInventoryProductEditor(
  BuildContext context,
  WidgetRef ref, {
  ProductModel? product,
  required List<String> categories,
}) {
  final nameCtrl = TextEditingController(text: product?.nombre ?? '');
  final priceCtrl = TextEditingController(
    text: product == null ? '' : formatRdAccountingAmount(product.precio),
  );
  final costCtrl = TextEditingController(
    text: product == null ? '' : formatRdAccountingAmount(product.costo),
  );
  final stockCtrl = TextEditingController(
    text: product == null ? '0' : _stockText(product.stock),
  );
  final categoryCtrl = TextEditingController(
    text: product == null || product.categoriaLabel == 'Sin categoría'
        ? ''
        : product.categoriaLabel,
  );
  Uint8List? imageBytes;
  String? imageName;
  var saving = false;
  var pickingImage = false;

  Future<void> pickImage(
    BuildContext dialogContext,
    void Function(void Function()) setPanelState,
  ) async {
    if (pickingImage) return;
    setPanelState(() => pickingImage = true);
    try {
      await Future<void>.delayed(Duration.zero);
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      final file = result?.files.single;
      if (file?.bytes == null) return;
      if (!dialogContext.mounted) return;
      setPanelState(() {
        imageBytes = file!.bytes;
        imageName = file.name;
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo leer la imagen: $e')),
        );
      }
    } finally {
      if (dialogContext.mounted) {
        setPanelState(() => pickingImage = false);
      } else {
        pickingImage = false;
      }
    }
  }

  Future<void> submit(
    BuildContext dialogContext,
    void Function(void Function()) setPanelState,
  ) async {
    final name = nameCtrl.text.trim();
    final price = _parseInventoryNumber(priceCtrl.text);
    final cost = _parseInventoryNumber(costCtrl.text);
    final stock = _parseInventoryNumber(stockCtrl.text);
    final category = categoryCtrl.text.trim();
    if (name.isEmpty ||
        price == null ||
        cost == null ||
        stock == null ||
        category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa nombre, precio, costo, stock y categoría'),
        ),
      );
      return;
    }

    setPanelState(() => saving = true);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? uploadedImagePath;
      if (imageBytes != null && imageName != null) {
        uploadedImagePath = await repo.uploadImage(
          bytes: imageBytes!,
          filename: imageName!,
        );
      }
      if (product == null) {
        await repo.createProduct(
          nombre: name,
          precio: price,
          costo: cost,
          stock: stock,
          categoria: category,
          fotoUrl: uploadedImagePath,
        );
      } else {
        await repo.updateProduct(
          id: product.id,
          nombre: name,
          precio: price,
          costo: cost,
          stock: stock,
          categoria: category,
          fotoUrl: uploadedImagePath,
        );
      }
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              product == null ? 'Producto creado' : 'Producto actualizado',
            ),
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          unawaited(
            ref
                .read(catalogControllerProvider.notifier)
                .load(forceRemote: true),
          );
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (dialogContext.mounted) setPanelState(() => saving = false);
    }
  }

  final existingImageUrl = product?.displayFotoUrl?.trim() ?? '';

  return Navigator.of(context)
      .push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (pageContext) {
            return StatefulBuilder(
              builder: (dialogContext, setPanelState) => Material(
                color: Colors.white,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: _lightBlueHover,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              product == null
                                  ? Icons.add_box_outlined
                                  : Icons.edit_outlined,
                              color: _primaryBlue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              product == null
                                  ? 'Nuevo producto'
                                  : 'Editar producto',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Nombre del producto',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: priceCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Precio',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: costCtrl,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Costo',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: stockCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Stock disponible',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: categoryCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Categoría',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (categories.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  for (final category in categories)
                                    ChoiceChip(
                                      label: Text(category),
                                      selected:
                                          categoryCtrl.text.trim() == category,
                                      onSelected: (_) {
                                        setPanelState(
                                          () => categoryCtrl.text = category,
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: saving || pickingImage
                                  ? null
                                  : () =>
                                        pickImage(dialogContext, setPanelState),
                              icon: pickingImage
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.upload_file_rounded),
                              label: Text(
                                pickingImage
                                    ? 'Seleccionando imagen...'
                                    : imageName ??
                                          'Subir imagen desde el ordenador',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              height: 160,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _lightBlueHover,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: _borderSoft),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: imageBytes != null
                                  ? Image.memory(
                                      imageBytes!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                    )
                                  : (product != null &&
                                        existingImageUrl.isNotEmpty)
                                  ? ProductNetworkImage(
                                      imageUrl: existingImageUrl,
                                      productId: product.id,
                                      productName: product.nombre,
                                      originalUrl: product.originalFotoUrl,
                                      fit: BoxFit.cover,
                                      fallback: const Icon(
                                        Icons.image_outlined,
                                        size: 44,
                                        color: _textSecondary,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.image_outlined,
                                      size: 44,
                                      color: _textSecondary,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: saving
                              ? null
                              : () => submit(dialogContext, setPanelState),
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            product == null
                                ? 'Crear producto'
                                : 'Guardar cambios',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      )
      .whenComplete(() {
        nameCtrl.dispose();
        priceCtrl.dispose();
        costCtrl.dispose();
        stockCtrl.dispose();
        categoryCtrl.dispose();
      });
}
