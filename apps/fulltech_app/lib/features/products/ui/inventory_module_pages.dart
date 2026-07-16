import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/env.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/models/product_model.dart';
import '../../../core/utils/media_file_actions.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/product_image_url.dart';
import '../../../core/utils/simple_xlsx.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/fulltech_dialog.dart';
import '../../../core/widgets/fulltech_page_header.dart';
import '../../../core/widgets/product_network_image.dart';
import '../../catalogo/application/catalog_controller.dart';
import '../../catalogo/data/catalog_repository.dart';

const _primaryBlue = Color(0xFF1A56DB);
const _lightBlueHover = Color(0xFFEFF6FF);
const _textSecondary = Color(0xFF64748B);
const _borderSoft = Color(0xFFE2E8F0);
const _pageBackground = Color(0xFFEFF4FA);
const double _desktopSidePanelWidth = 500;
const double _desktopWideSidePanelWidth = 550;
const double _stockLowThreshold = 5;
const String _inventoryCategoriesCacheKey = 'inventory_categories_v1';
const String _inventorySuppliersCacheKey = 'inventory_suppliers_v1';

enum _StockLevel { out, low, high }

enum _StockFilter { all, out, low, high }

extension on _StockFilter {
  String get label => switch (this) {
    _StockFilter.all => 'Todos',
    _StockFilter.out => 'Sin stock',
    _StockFilter.low => 'Stock bajo',
    _StockFilter.high => 'Stock alto',
  };
}

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
  return stock > 0 && stock <= _stockLowThreshold;
}

_StockLevel _resolveStockLevel(ProductModel product) {
  if (_isOutOfStock(product)) return _StockLevel.out;
  if (_isLowStock(product)) return _StockLevel.low;
  return _StockLevel.high;
}

String _stockLevelLabel(_StockLevel level) => switch (level) {
  _StockLevel.out => 'Sin stock',
  _StockLevel.low => 'Stock bajo',
  _StockLevel.high => 'Stock alto',
};

Color _stockLevelColor(_StockLevel level) => switch (level) {
  _StockLevel.out => const Color(0xFFEF4444),
  _StockLevel.low => const Color(0xFFF59E0B),
  _StockLevel.high => const Color(0xFF1A56DB),
};

bool _matchesStockFilter(ProductModel product, _StockFilter filter) {
  final level = _resolveStockLevel(product);
  return switch (filter) {
    _StockFilter.all => true,
    _StockFilter.out => level == _StockLevel.out,
    _StockFilter.low => level == _StockLevel.low,
    _StockFilter.high => level == _StockLevel.high,
  };
}

String _normalizeCategoryName(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class InventoryCategoryModel {
  const InventoryCategoryModel({
    required this.id,
    required this.name,
    this.imageBase64,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? imageBase64;
  final DateTime createdAt;
  final DateTime updatedAt;

  InventoryCategoryModel copyWith({
    String? name,
    String? imageBase64,
    bool clearImage = false,
    DateTime? updatedAt,
  }) {
    return InventoryCategoryModel(
      id: id,
      name: name ?? this.name,
      imageBase64: clearImage ? null : (imageBase64 ?? this.imageBase64),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'imageBase64': imageBase64,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory InventoryCategoryModel.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return InventoryCategoryModel(
      id: (map['id'] ?? '').toString(),
      name: _normalizeCategoryName((map['name'] ?? '').toString()),
      imageBase64: (map['imageBase64'] as String?)?.trim().isEmpty == true
          ? null
          : map['imageBase64'] as String?,
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? now,
      updatedAt: DateTime.tryParse((map['updatedAt'] ?? '').toString()) ?? now,
    );
  }
}

class InventoryCategoriesState {
  const InventoryCategoriesState({
    this.items = const [],
    this.loading = false,
    this.saving = false,
    this.error,
  });

  final List<InventoryCategoryModel> items;
  final bool loading;
  final bool saving;
  final String? error;

  InventoryCategoriesState copyWith({
    List<InventoryCategoryModel>? items,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
  }) {
    return InventoryCategoriesState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final inventoryCategoriesProvider =
    StateNotifierProvider<
      InventoryCategoriesController,
      InventoryCategoriesState
    >((ref) {
      return InventoryCategoriesController();
    });

class InventoryCategoriesController
    extends StateNotifier<InventoryCategoriesState> {
  InventoryCategoriesController() : super(const InventoryCategoriesState()) {
    unawaited(load());
  }

  final _cache = LocalJsonCache();

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final map = await _cache.readMap(_inventoryCategoriesCacheKey);
      final rows = (map?['items'] as List?) ?? const [];
      final items =
          rows
              .whereType<Map>()
              .map((row) => InventoryCategoryModel.fromMap(row.cast()))
              .where(
                (item) => item.id.trim().isNotEmpty && item.name.isNotEmpty,
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
      state = state.copyWith(items: items, loading: false);
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudieron cargar las categorías: $e',
      );
    }
  }

  Future<void> _persist(List<InventoryCategoryModel> items) async {
    final sorted = [...items]..sort((a, b) => a.name.compareTo(b.name));
    await _cache.writeMap(_inventoryCategoriesCacheKey, {
      'items': sorted.map((item) => item.toMap()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    state = state.copyWith(items: sorted, saving: false, clearError: true);
  }

  Future<void> upsert({
    String? id,
    required String name,
    String? imageBase64,
    bool clearImage = false,
  }) async {
    final cleanName = _normalizeCategoryName(name);
    if (cleanName.isEmpty) {
      throw const FormatException('El nombre de la categoría es obligatorio');
    }
    state = state.copyWith(saving: true, clearError: true);
    try {
      final now = DateTime.now();
      final existingIndex = state.items.indexWhere((item) => item.id == id);
      final duplicate = state.items.any(
        (item) =>
            item.id != id &&
            item.name.toLowerCase().trim() == cleanName.toLowerCase().trim(),
      );
      if (duplicate) {
        throw const FormatException('Ya existe una categoría con ese nombre');
      }

      final next = [...state.items];
      if (existingIndex >= 0) {
        next[existingIndex] = next[existingIndex].copyWith(
          name: cleanName,
          imageBase64: imageBase64,
          clearImage: clearImage,
          updatedAt: now,
        );
      } else {
        next.add(
          InventoryCategoryModel(
            id: id ?? 'cat-${now.microsecondsSinceEpoch}',
            name: cleanName,
            imageBase64: imageBase64,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await _persist(next);
    } catch (e) {
      state = state.copyWith(saving: false, error: '$e');
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await _persist(state.items.where((item) => item.id != id).toList());
    } catch (e) {
      state = state.copyWith(saving: false, error: '$e');
      rethrow;
    }
  }
}

class InventorySupplierModel {
  const InventorySupplierModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory InventorySupplierModel.fromMap(Map<String, dynamic> map) {
    final now = DateTime.now();
    return InventorySupplierModel(
      id: (map['id'] ?? '').toString(),
      name: _normalizeCategoryName((map['name'] ?? '').toString()),
      createdAt: DateTime.tryParse((map['createdAt'] ?? '').toString()) ?? now,
      updatedAt: DateTime.tryParse((map['updatedAt'] ?? '').toString()) ?? now,
    );
  }
}

class InventorySuppliersState {
  const InventorySuppliersState({this.items = const [], this.saving = false});

  final List<InventorySupplierModel> items;
  final bool saving;

  InventorySuppliersState copyWith({
    List<InventorySupplierModel>? items,
    bool? saving,
  }) {
    return InventorySuppliersState(
      items: items ?? this.items,
      saving: saving ?? this.saving,
    );
  }
}

final inventorySuppliersProvider =
    StateNotifierProvider<
      InventorySuppliersController,
      InventorySuppliersState
    >((ref) {
      return InventorySuppliersController();
    });

class InventorySuppliersController
    extends StateNotifier<InventorySuppliersState> {
  InventorySuppliersController() : super(const InventorySuppliersState()) {
    unawaited(load());
  }

  final _cache = LocalJsonCache();

  Future<void> load() async {
    final map = await _cache.readMap(_inventorySuppliersCacheKey);
    final rows = (map?['items'] as List?) ?? const [];
    final items =
        rows
            .whereType<Map>()
            .map((row) => InventorySupplierModel.fromMap(row.cast()))
            .where((item) => item.id.trim().isNotEmpty && item.name.isNotEmpty)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    state = state.copyWith(items: items);
  }

  Future<void> upsertMany(Iterable<String> names) async {
    final cleanNames = names
        .map(_normalizeCategoryName)
        .where((name) => name.isNotEmpty)
        .toSet();
    if (cleanNames.isEmpty) return;

    state = state.copyWith(saving: true);
    final now = DateTime.now();
    final next = [...state.items];
    for (final name in cleanNames) {
      final exists = next.any(
        (item) => item.name.trim().toLowerCase() == name.toLowerCase(),
      );
      if (exists) continue;
      next.add(
        InventorySupplierModel(
          id: 'sup-${now.microsecondsSinceEpoch}-${next.length}',
          name: name,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    next.sort((a, b) => a.name.compareTo(b.name));
    await _cache.writeMap(_inventorySuppliersCacheKey, {
      'items': next.map((item) => item.toMap()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    state = state.copyWith(items: next, saving: false);
  }
}

double? _parseInventoryNumber(String raw) {
  var value = raw
      .trim()
      .replaceAll('\ufeff', '')
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

String _catalogExportFileName() {
  return 'Inventario_FULLTECH_FINAL_listo.xlsx';
}

num _xlsxNumber(num? value) {
  if (value == null) return 0;
  final number = value.toDouble();
  return number % 1 == 0 ? number.toInt() : number;
}

Uint8List _buildInventoryWorkbook({
  required List<ProductModel> products,
  required List<InventorySupplierModel> suppliers,
}) {
  return buildSimpleXlsx([
    SimpleXlsxSheet(
      name: 'Catalogo',
      rows: [
        const [
          'codigo',
          'producto',
          'categoria',
          'proveedor',
          'precio',
          'costo',
          'stock',
          'descripcion',
          'fotoUrl',
        ],
        for (final product in products)
          [
            (product.codigo ?? '').trim().isNotEmpty
                ? product.codigo!.trim()
                : product.id,
            product.nombre,
            product.categoriaLabel,
            '',
            _xlsxNumber(product.precio),
            _xlsxNumber(product.costo),
            _xlsxNumber(product.stock),
            product.descripcion ?? '',
            product.displayFotoUrl ??
                product.fotoUrl ??
                product.originalFotoUrl ??
                '',
          ],
        for (final supplier in suppliers)
          ['', '', '', supplier.name, '', '', '', '', ''],
      ],
    ),
  ]);
}

class _CatalogImportBundle {
  const _CatalogImportBundle({
    required this.products,
    required this.categories,
    required this.suppliers,
  });

  final List<CatalogImportDraft> products;
  final List<String> categories;
  final List<String> suppliers;
}

_CatalogImportBundle _parseCatalogRows(List<List<String>> rows) {
  if (rows.isEmpty) {
    return const _CatalogImportBundle(
      products: [],
      categories: [],
      suppliers: [],
    );
  }
  final normalizedFirst = rows.first.map(_normalizeCatalogHeader).toList();
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
      ? indexOf(['nombre', 'producto', 'name', 'descripcion'], 1)
      : 0;
  final priceIndex = hasHeader
      ? indexOf(['precio', 'precio venta', 'price'], 4)
      : 1;
  final costIndex = hasHeader ? indexOf(['costo', 'cost'], 5) : 2;
  final stockIndex = hasHeader
      ? indexOf(['stock', 'existencia', 'cantidad', 'quantity'], 6)
      : 3;
  final categoryIndex = hasHeader
      ? indexOf(['categoria', 'category', 'familia'], 2)
      : 4;
  final supplierIndex = hasHeader
      ? indexOf(['proveedor', 'suplidor', 'supplier', 'provider'], 3)
      : -1;

  final dataRows = hasHeader ? rows.skip(1) : rows;
  final drafts = <CatalogImportDraft>[];
  final categories = <String>{};
  final suppliers = <String>{};
  for (final cells in dataRows) {
    String cell(int index) =>
        index >= 0 && index < cells.length ? cells[index].trim() : '';

    final nombre = cell(nameIndex);
    final precio = _parseInventoryNumber(cell(priceIndex));
    final costo = _parseInventoryNumber(cell(costIndex));
    final stock = _parseInventoryNumber(cell(stockIndex)) ?? 0;
    final categoria = cell(categoryIndex).isEmpty
        ? 'Sin categoría'
        : cell(categoryIndex);
    final proveedor = cell(supplierIndex);

    if (categoria.trim().isNotEmpty) {
      categories.add(_normalizeCategoryName(categoria));
    }
    if (proveedor.trim().isNotEmpty) {
      suppliers.add(_normalizeCategoryName(proveedor));
    }

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
  return _CatalogImportBundle(
    products: drafts,
    categories: categories.where((name) => name.isNotEmpty).toList()..sort(),
    suppliers: suppliers.where((name) => name.isNotEmpty).toList()..sort(),
  );
}

_CatalogImportBundle _parseCatalogWorkbook(Uint8List bytes) {
  final workbook = readSimpleXlsx(bytes);
  final rows =
      workbook['Catalogo'] ??
      workbook['Catálogo'] ??
      workbook['catalogo'] ??
      workbook['Productos'] ??
      workbook['productos'];
  final fallbackRows = workbook.values.isEmpty
      ? const <List<String>>[]
      : workbook.values.first;
  return _parseCatalogRows(rows ?? fallbackRows);
}

String _normalizeCatalogHeader(String value) {
  return value
      .replaceAll('\ufeff', '')
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n');
}

List<String> _parseCatalogCsvLine(String line) {
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

_CatalogImportBundle _parseCatalogCsv(String content) {
  final lines = const LineSplitter()
      .convert(content.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    return const _CatalogImportBundle(
      products: [],
      categories: [],
      suppliers: [],
    );
  }

  return _parseCatalogRows([
    for (final line in lines) _parseCatalogCsvLine(line),
  ]);
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

  List<String> _categoryOptions(
    List<ProductModel> products,
    List<InventoryCategoryModel> managedCategories,
  ) {
    final categories = <String>{
      ...managedCategories.map((category) => category.name),
      ...products
          .map((product) => product.categoriaLabel)
          .where((category) => category.trim().isNotEmpty),
    }.toList();
    categories.sort();
    return categories;
  }

  Future<void> _openProductEditor({ProductModel? product}) async {
    final categoryState = ref.read(inventoryCategoriesProvider);
    final result = await showInventoryProductEditor(
      context,
      product: product,
      categories: _categoryOptions(
        ref.read(catalogControllerProvider).items,
        categoryState.items,
      ),
    );
    if (!mounted || result?.saved != true) return;
    await ref.read(catalogControllerProvider.notifier).load(forceRemote: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          product == null ? 'Producto creado' : 'Producto actualizado',
        ),
      ),
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

  Future<void> _exportCatalog() async {
    final products = ref.read(catalogControllerProvider).items;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos para exportar')),
      );
      return;
    }

    try {
      final suppliers = ref.read(inventorySuppliersProvider).items;
      final saved = await saveMediaBytes(
        bytes: _buildInventoryWorkbook(
          products: products,
          suppliers: suppliers,
        ),
        fileName: _catalogExportFileName(),
        allowedExtensions: const ['xlsx'],
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Inventario exportado en Excel' : 'Exportación cancelada',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar el catálogo: $e')),
      );
    }
  }

  Future<void> _importCatalog() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt'],
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;

    try {
      final extension = (file?.extension ?? '').trim().toLowerCase();
      final isExcel = extension == 'xlsx';
      final typedBytes = Uint8List.fromList(bytes);
      final bundle = isExcel
          ? _parseCatalogWorkbook(typedBytes)
          : _parseCatalogCsv(utf8.decode(bytes, allowMalformed: true));
      if (!mounted) return;
      if (bundle.products.isEmpty &&
          bundle.categories.isEmpty &&
          bundle.suppliers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se encontraron datos válidos para importar'),
          ),
        );
        return;
      }

      final confirmed = await FullTechConfirmDialog.show(
        context,
        title: 'Importar catálogo',
        message:
            'Se crearán ${bundle.products.length} productos, se sincronizarán ${bundle.categories.length} categorías y ${bundle.suppliers.length} suplidores desde el catálogo. ¿Deseas continuar?',
        confirmText: 'Importar',
        cancelText: 'Cancelar',
        icon: Icons.upload_file_rounded,
      );
      if (confirmed != true || !mounted) return;

      for (final categoryName in bundle.categories) {
        InventoryCategoryModel? existing;
        for (final item in ref.read(inventoryCategoriesProvider).items) {
          if (item.name.trim().toLowerCase() ==
              categoryName.trim().toLowerCase()) {
            existing = item;
            break;
          }
        }
        await ref
            .read(inventoryCategoriesProvider.notifier)
            .upsert(id: existing?.id, name: categoryName);
      }
      await ref
          .read(inventorySuppliersProvider.notifier)
          .upsertMany(bundle.suppliers);
      final imported = bundle.products.isEmpty
          ? 0
          : await ref
                .read(catalogControllerProvider.notifier)
                .importProducts(bundle.products);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Se importaron $imported productos, ${bundle.categories.length} categorías y ${bundle.suppliers.length} suplidores',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo importar el catálogo: $e')),
      );
    }
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
        appBar: FullTechPageHeader(
          title: 'Inventario',
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
                    onImport: _importCatalog,
                    onExport: _exportCatalog,
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
    required this.onImport,
    required this.onExport,
    required this.onEdit,
    required this.onSetStock,
    required this.onDelete,
  });

  final List<ProductModel> products;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;
  final Future<void> Function() onImport;
  final Future<void> Function() onExport;
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
    final confirmed = await FullTechConfirmDialog.show(
      context,
      title: 'Eliminar producto',
      message: '¿Deseas eliminar "${product.nombre}" del catálogo?',
      confirmText: 'Eliminar',
      cancelText: 'Cancelar',
      icon: Icons.delete_outline_rounded,
      iconColor: FullTechDialogTokens.errorColor,
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
                onImport: widget.onImport,
                onExport: widget.onExport,
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
    required this.onImport,
    required this.onExport,
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
  final Future<void> Function() onImport;
  final Future<void> Function() onExport;

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
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_rounded, size: 17),
            label: const Text('Importar'),
          ),
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded, size: 17),
            label: const Text('Exportar'),
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
                  DataCell(
                    Text(
                      product.codigo?.trim().isNotEmpty == true
                          ? product.codigo!.trim()
                          : 'Sin SKU',
                    ),
                  ),
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
  late List<ProductModel> _products;
  ProductModel? _selected;
  String _mode = 'Agregar';
  String _categoryFilter = 'Todas las categorías';
  _StockFilter _stockFilter = _StockFilter.all;
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _products = List<ProductModel>.of(widget.products);
  }

  @override
  void didUpdateWidget(covariant StockAdjustmentsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.products, widget.products)) {
      _products = List<ProductModel>.of(widget.products);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double get _quantity => _parseInventoryNumber(_qtyCtrl.text) ?? 0;

  double _previewStock(ProductModel product) {
    final stock = _stockOf(product);
    return switch (_mode) {
      'Disminuir' => stock - _quantity,
      _ => stock + _quantity,
    };
  }

  List<String> get _categories {
    final values = _products
        .map((product) => product.categoriaLabel.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  List<ProductModel> get _filteredProducts {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _products
        .where((product) {
          final matchesSearch =
              query.isEmpty ||
              product.nombre.toLowerCase().contains(query) ||
              (product.codigo?.toLowerCase().contains(query) ?? false);
          final matchesCategory =
              _categoryFilter == 'Todas las categorías' ||
              product.categoriaLabel == _categoryFilter;
          return matchesSearch &&
              matchesCategory &&
              _matchesStockFilter(product, _stockFilter);
        })
        .toList(growable: false);
  }

  bool get _canSubmit {
    final selected =
        _selected ?? (_products.isNotEmpty ? _products.first : null);
    if (_saving || selected == null || _quantity <= 0 || !_quantity.isFinite) {
      return false;
    }
    return _previewStock(selected) >= 0;
  }

  Future<void> _applyAdjustment() async {
    final selected =
        _selected ?? (_products.isNotEmpty ? _products.first : null);
    if (selected == null || _quantity <= 0 || !_quantity.isFinite) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una cantidad mayor que cero')),
      );
      return;
    }
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
            'Stock actualizado: ${selected.nombre} ahora tiene ${_stockText(nextStock)}',
          ),
        ),
      );
      _noteCtrl.clear();
      _qtyCtrl.text = '1';
      final updated = selected.copyWith(stock: nextStock);
      setState(() {
        _products = [
          for (final product in _products)
            if (product.id == updated.id) updated else product,
        ];
        _selected = updated;
      });
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
        _selected ?? (_products.isNotEmpty ? _products.first : null);
    final filtered = _filteredProducts;

    return Column(
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              if (_canSubmit)
                const SingleActivator(LogicalKeyboardKey.enter):
                    _applyAdjustment,
              if (_canSubmit)
                const SingleActivator(LogicalKeyboardKey.numpadEnter):
                    _applyAdjustment,
            },
            child: Focus(
              autofocus: true,
              child: RefreshIndicator(
                onRefresh: widget.onRefresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Buscar producto',
                        prefixIcon: Icon(Icons.search_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _categoryFilter,
                      items: [
                        const DropdownMenuItem(
                          value: 'Todas las categorías',
                          child: Text('Todas las categorías'),
                        ),
                        for (final category in _categories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _categoryFilter = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Categoría',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SegmentedButton<_StockFilter>(
                        segments: [
                          for (final filter in _StockFilter.values)
                            ButtonSegment(
                              value: filter,
                              label: Text(filter.label),
                            ),
                        ],
                        selected: {_stockFilter},
                        onSelectionChanged: (value) =>
                            setState(() => _stockFilter = value.first),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (selected != null)
                      _SelectedStockProduct(product: selected),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'Agregar',
                            label: Text('Agregar stock'),
                            icon: Icon(Icons.add_rounded),
                          ),
                          ButtonSegment(
                            value: 'Disminuir',
                            label: Text('Disminuir stock'),
                            icon: Icon(Icons.remove_rounded),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (value) =>
                            setState(() => _mode = value.first),
                      ),
                      const SizedBox(height: 10),
                      TextField(
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
                      const SizedBox(height: 10),
                      TextField(
                        controller: _noteCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Motivo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _InlineInfo(
                        icon: Icons.inventory_2_outlined,
                        message:
                            'Stock actual: ${_stockText(selected.stock)}   Nuevo stock: ${_stockText(_previewStock(selected))}',
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Productos',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '${filtered.length}',
                          style: const TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (filtered.isEmpty)
                      const ProductsEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'Sin resultados',
                        message: 'No encontramos productos con esos filtros.',
                      )
                    else
                      for (final product in filtered)
                        _StockProductRow(
                          product: product,
                          selected: selected?.id == product.id,
                          onSelected: () => setState(() => _selected = product),
                        ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canSubmit ? _applyAdjustment : null,
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
              label: const Text('Aplicar ajuste'),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectedStockProduct extends StatelessWidget {
  const _SelectedStockProduct({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final level = _resolveStockLevel(product);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _lightBlueHover,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCFE0FF)),
      ),
      child: Row(
        children: [
          ProductThumbnail(product: product, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  product.categoriaLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Stock ${_stockText(product.stock)}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              _StockLevelBadge(level: level),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockProductRow extends StatelessWidget {
  const _StockProductRow({
    required this.product,
    required this.selected,
    required this.onSelected,
  });

  final ProductModel product;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final level = _resolveStockLevel(product);
    final color = _stockLevelColor(level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? _lightBlueHover : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? _primaryBlue : _borderSoft,
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: [
                ProductThumbnail(product: product, size: 34),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        product.categoriaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10.8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _StockLevelBadge(level: level),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _stockText(product.stock),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const Text(
                      'Stock actual',
                      style: TextStyle(color: _textSecondary, fontSize: 9),
                    ),
                    const SizedBox(height: 3),
                    TextButton(
                      onPressed: onSelected,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 26),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Ajustar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StockLevelBadge extends StatelessWidget {
  const _StockLevelBadge({required this.level});

  final _StockLevel level;

  @override
  Widget build(BuildContext context) {
    final color = _stockLevelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        _stockLevelLabel(level),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class CategoriesTab extends ConsumerStatefulWidget {
  const CategoriesTab({
    super.key,
    required this.products,
    required this.onRefresh,
  });

  final List<ProductModel> products;
  final Future<void> Function() onRefresh;

  @override
  ConsumerState<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends ConsumerState<CategoriesTab> {
  String _query = '';

  Map<String, int> get _productCounts {
    final counts = <String, int>{};
    for (final product in widget.products) {
      counts.update(
        product.categoriaLabel,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  List<InventoryCategoryModel> _mergedCategories(
    List<InventoryCategoryModel> managed,
  ) {
    final byName = <String, InventoryCategoryModel>{
      for (final item in managed) item.name.toLowerCase(): item,
    };
    for (final name in _productCounts.keys) {
      final clean = _normalizeCategoryName(name);
      if (clean.isEmpty) continue;
      byName.putIfAbsent(
        clean.toLowerCase(),
        () => InventoryCategoryModel(
          id: 'derived-${clean.toLowerCase()}',
          name: clean,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
    }
    final rows = byName.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows
        .where((item) => item.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openEditor({InventoryCategoryModel? category}) async {
    final result = await showDialog<_CategoryEditorResult>(
      context: context,
      barrierColor: FullTechDialogTokens.overlayColor,
      builder: (dialogContext) => _CategoryEditorDialog(category: category),
    );
    if (result == null || !mounted) return;

    final oldName = category?.name;
    await ref
        .read(inventoryCategoriesProvider.notifier)
        .upsert(
          id: category?.id.startsWith('derived-') == true ? null : category?.id,
          name: result.name,
          imageBase64: result.imageBase64,
          clearImage: result.clearImage,
        );

    if (oldName != null &&
        oldName.trim().toLowerCase() != result.name.trim().toLowerCase()) {
      await _renameProductsCategory(oldName: oldName, newName: result.name);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          category == null ? 'Categoría creada' : 'Categoría editada',
        ),
      ),
    );
  }

  Future<void> _renameProductsCategory({
    required String oldName,
    required String newName,
  }) async {
    final affected = widget.products
        .where(
          (product) =>
              product.categoriaLabel.trim().toLowerCase() ==
              oldName.trim().toLowerCase(),
        )
        .toList();
    if (affected.isEmpty) return;

    final controller = ref.read(catalogControllerProvider.notifier);
    for (final product in affected) {
      await controller.update(
        id: product.id,
        nombre: product.nombre,
        precio: product.precio,
        costo: product.costo,
        stock: product.stock ?? 0,
        categoria: newName,
      );
    }
    await widget.onRefresh();
  }

  Future<void> _deleteCategory(InventoryCategoryModel category) async {
    final count = _productCounts[category.name] ?? 0;
    if (count > 0) {
      await FullTechConfirmDialog.show(
        context,
        title: 'Categoría en uso',
        message:
            'Esta categoría tiene $count productos. Mueve o edita esos productos antes de eliminarla.',
        confirmText: 'Entendido',
        cancelText: 'Cerrar',
        icon: Icons.info_outline_rounded,
      );
      return;
    }

    final confirmed = await FullTechConfirmDialog.show(
      context,
      title: 'Eliminar categoría',
      message: '¿Deseas eliminar "${category.name}"?',
      confirmText: 'Eliminar',
      cancelText: 'Cancelar',
      icon: Icons.delete_outline_rounded,
      iconColor: FullTechDialogTokens.errorColor,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    if (!category.id.startsWith('derived-')) {
      await ref.read(inventoryCategoriesProvider.notifier).remove(category.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryState = ref.watch(inventoryCategoriesProvider);
    final rows = _mergedCategories(categoryState.items);
    final totalProducts = _productCounts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );

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
                    Row(
                      children: [
                        const Expanded(
                          child: _SectionHeader(
                            title: 'Categorías',
                            subtitle: 'Administra familias, fotos y catálogo',
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: categoryState.saving
                              ? null
                              : () => _openEditor(),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Nueva categoría'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 320,
                          child: TextField(
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Buscar categoría',
                              border: OutlineInputBorder(),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                        _CategorySummaryChip(
                          label: '${categoryState.items.length} creadas',
                          icon: Icons.edit_note_rounded,
                        ),
                        _CategorySummaryChip(
                          label: '${rows.length} visibles',
                          icon: Icons.category_outlined,
                        ),
                        _CategorySummaryChip(
                          label: '$totalProducts productos',
                          icon: Icons.inventory_2_outlined,
                        ),
                      ],
                    ),
                    if (categoryState.error != null) ...[
                      const SizedBox(height: 12),
                      _InlineWarning(message: categoryState.error!),
                    ],
                    const SizedBox(height: 16),
                    if (rows.isEmpty)
                      const ProductsEmptyState(
                        icon: Icons.category_outlined,
                        title: 'Sin categorías',
                        message:
                            'Crea tu primera categoría con nombre e imagen.',
                      )
                    else
                      LayoutBuilder(
                        builder: (context, inner) {
                          final compact = inner.maxWidth < 760;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final category in rows)
                                _CategoryManagementCard(
                                  width: compact
                                      ? inner.maxWidth
                                      : ((inner.maxWidth - 12) / 2)
                                            .clamp(360.0, 560.0)
                                            .toDouble(),
                                  category: category,
                                  productCount:
                                      _productCounts[category.name] ?? 0,
                                  managed: !category.id.startsWith('derived-'),
                                  onEdit: () => _openEditor(category: category),
                                  onDelete: () => _deleteCategory(category),
                                ),
                            ],
                          );
                        },
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

class _CategorySummaryChip extends StatelessWidget {
  const _CategorySummaryChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: _primaryBlue),
      label: Text(label),
      backgroundColor: _lightBlueHover,
      side: const BorderSide(color: Color(0xFFCFE0FF)),
      labelStyle: const TextStyle(
        color: Color(0xFF123A75),
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _CategoryManagementCard extends StatelessWidget {
  const _CategoryManagementCard({
    required this.width,
    required this.category,
    required this.productCount,
    required this.managed,
    required this.onEdit,
    required this.onDelete,
  });

  final double width;
  final InventoryCategoryModel category;
  final int productCount;
  final bool managed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodeCategoryImage(category.imageBase64);
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderSoft),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 74,
                      height: 58,
                      color: _lightBlueHover,
                      child: imageBytes == null
                          ? const Icon(
                              Icons.category_outlined,
                              size: 28,
                              color: _primaryBlue,
                            )
                          : Image.memory(imageBytes, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: Color(0xFF17212B),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$productCount productos · ${managed ? 'Administrada' : 'Detectada'}',
                          style: const TextStyle(
                            color: _textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(92, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: FullTechDialogTokens.errorColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Uint8List? _decodeCategoryImage(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

class _CategoryEditorResult {
  const _CategoryEditorResult({
    required this.name,
    this.imageBase64,
    this.clearImage = false,
  });

  final String name;
  final String? imageBase64;
  final bool clearImage;
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({this.category});

  final InventoryCategoryModel? category;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  late final TextEditingController _nameCtrl;
  Uint8List? _imageBytes;
  String? _imageBase64;
  String? _imageName;
  bool _clearImage = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.category?.name ?? '');
    _imageBase64 = widget.category?.imageBase64;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('No se pudo leer la imagen seleccionada');
      }
      setState(() {
        _imageBytes = bytes;
        _imageBase64 = base64Encode(bytes);
        _imageName = file.name;
        _clearImage = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo leer la imagen: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    final name = _normalizeCategoryName(_nameCtrl.text);
    if (name.isEmpty) {
      setState(() => _error = 'Escribe el nombre de la categoría.');
      return;
    }
    Navigator.of(context).pop(
      _CategoryEditorResult(
        name: name,
        imageBase64: _imageBase64,
        clearImage: _clearImage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewBytes =
        _imageBytes ??
        (_clearImage ? null : _decodeCategoryImage(_imageBase64));
    return FullTechDialog(
      title: widget.category == null ? 'Nueva categoría' : 'Editar categoría',
      maxWidth: 460,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            _FormErrorBanner(message: _error!),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nombre de la categoría',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 14),
          Container(
            height: 170,
            decoration: BoxDecoration(
              color: _lightBlueHover,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _borderSoft),
            ),
            clipBehavior: Clip.antiAlias,
            child: previewBytes == null
                ? const Icon(
                    Icons.image_outlined,
                    size: 48,
                    color: _textSecondary,
                  )
                : Image.memory(previewBytes, fit: BoxFit.cover),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _picking ? null : _pickImage,
                  icon: _picking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file_rounded),
                  label: Text(
                    _picking
                        ? 'Seleccionando...'
                        : (_imageName ?? 'Seleccionar foto'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Quitar foto',
                onPressed: previewBytes == null
                    ? null
                    : () {
                        setState(() {
                          _imageBytes = null;
                          _imageBase64 = null;
                          _imageName = null;
                          _clearImage = true;
                        });
                      },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DialogSecondaryButton(
                  label: 'Cancelar',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DialogPrimaryButton(
                  label: widget.category == null ? 'Crear' : 'Guardar',
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ],
      ),
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
                      product.codigo?.trim().isNotEmpty == true
                          ? product.codigo!.trim()
                          : product.categoriaLabel,
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
  var mode = 'Agregar';
  var saving = false;

  double quantity() => _parseInventoryNumber(qtyCtrl.text) ?? 0;
  double preview() {
    final stock = _stockOf(product);
    return switch (mode) {
      'Disminuir' => stock - quantity(),
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
                              Text(product.categoriaLabel),
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
                          value: 'Agregar',
                          label: Text('Agregar stock'),
                          icon: Icon(Icons.add_rounded),
                        ),
                        ButtonSegment(
                          value: 'Disminuir',
                          label: Text('Disminuir stock'),
                          icon: Icon(Icons.remove_rounded),
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

class ProductFormResult {
  const ProductFormResult({required this.saved});

  final bool saved;
}

class _InventorySidePanelScaffold extends StatelessWidget {
  const _InventorySidePanelScaffold({
    required this.title,
    required this.icon,
    required this.onClose,
    required this.body,
    this.footer,
    this.onSubmit,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onClose;
  final Widget body;
  final Widget? footer;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (onSubmit != null)
          const SingleActivator(LogicalKeyboardKey.enter): onSubmit!,
        if (onSubmit != null)
          const SingleActivator(LogicalKeyboardKey.numpadEnter): onSubmit!,
        if (onClose != null)
          const SingleActivator(LogicalKeyboardKey.escape): onClose!,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          color: Colors.white,
          child: SafeArea(
            left: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: const Border(
                  left: BorderSide(color: Color(0xFFC9D8EA)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 20,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
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
                          child: Icon(icon, color: _primaryBlue),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                              color: Color(0xFF52667C),
                            ),
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
                  const Divider(height: 1),
                  Expanded(child: body),
                  if (footer != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: footer!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<ProductFormResult?> showInventoryProductEditor(
  BuildContext context, {
  ProductModel? product,
  required List<String> categories,
}) {
  return showGeneralDialog<ProductFormResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: product == null ? 'Nuevo producto' : 'Editar producto',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(dialogContext);
      final panelWidth = _inventorySidePanelWidth(size);
      return Stack(
        children: [
          const _InventorySidePanelBackdrop(),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: panelWidth,
              height: size.height,
              child: InventoryProductEditorPage(
                product: product,
                categories: categories,
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

Future<void> showInventoryStockAdjustmentsPanel(
  BuildContext context, {
  required List<ProductModel> products,
  required Future<void> Function() onRefresh,
  required Future<void> Function(ProductModel product, double stock) onSetStock,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Ajustar stock',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 190),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(dialogContext);
      final panelWidth = _inventorySidePanelWidth(size);
      return Stack(
        children: [
          const _InventorySidePanelBackdrop(),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: panelWidth,
              height: size.height,
              child: _InventorySidePanelScaffold(
                title: 'Ajustar stock',
                icon: Icons.inventory_2_outlined,
                onClose: () => Navigator.of(dialogContext).pop(),
                body: StockAdjustmentsPage(
                  products: products,
                  onRefresh: onRefresh,
                  onSetStock: onSetStock,
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

double _inventorySidePanelWidth(Size size) {
  if (size.width < 700) return size.width;
  final desired = size.width >= 1600
      ? _desktopWideSidePanelWidth
      : _desktopSidePanelWidth;
  return desired.clamp(0, size.width * 0.92).toDouble();
}

class _InventorySidePanelBackdrop extends StatelessWidget {
  const _InventorySidePanelBackdrop();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 2.4, sigmaY: 2.4),
        child: ColoredBox(color: Colors.white.withValues(alpha: 0.05)),
      ),
    );
  }
}

class InventoryProductEditorPage extends ConsumerStatefulWidget {
  const InventoryProductEditorPage({
    super.key,
    required this.product,
    required this.categories,
  });

  final ProductModel? product;
  final List<String> categories;

  @override
  ConsumerState<InventoryProductEditorPage> createState() =>
      _InventoryProductEditorPageState();
}

class _InventoryProductEditorPageState
    extends ConsumerState<InventoryProductEditorPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _categoryCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _priceFocus;
  late final FocusNode _costFocus;
  late final FocusNode _stockFocus;
  late final FocusNode _categoryFocus;

  Uint8List? _imageBytes;
  String? _imageName;
  bool _isSaving = false;
  bool _isPickingImage = false;
  String? _formError;

  ProductModel? get _product => widget.product;

  @override
  void initState() {
    super.initState();
    debugPrint('[ProductForm#$hashCode] initState');
    final product = widget.product;
    _nameCtrl = TextEditingController(text: product?.nombre ?? '');
    _priceCtrl = TextEditingController(
      text: product == null ? '' : formatRdAccountingAmount(product.precio),
    );
    _costCtrl = TextEditingController(
      text: product == null ? '' : formatRdAccountingAmount(product.costo),
    );
    _stockCtrl = TextEditingController(
      text: product == null ? '0' : _stockText(product.stock),
    );
    _categoryCtrl = TextEditingController(
      text: product == null || product.categoriaLabel == 'Sin categoría'
          ? ''
          : product.categoriaLabel,
    );
    _nameFocus = FocusNode();
    _priceFocus = FocusNode();
    _costFocus = FocusNode();
    _stockFocus = FocusNode();
    _categoryFocus = FocusNode();
  }

  @override
  void dispose() {
    debugPrint('[ProductForm#$hashCode] dispose');
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _categoryCtrl.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    _costFocus.dispose();
    _stockFocus.dispose();
    _categoryFocus.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isPickingImage || _isSaving) return;
    debugPrint('[ProductForm#$hashCode] pick start mounted=$mounted');
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isPickingImage = true;
      _formError = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('No se pudieron leer los bytes de la imagen');
      }
      setState(() {
        _imageBytes = bytes;
        _imageName = file.name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = 'No se pudo leer la imagen: $e');
    } finally {
      debugPrint('[ProductForm#$hashCode] pick end mounted=$mounted');
      if (mounted) {
        setState(() => _isPickingImage = false);
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    debugPrint('[ProductForm#$hashCode] save start mounted=$mounted');
    FocusManager.instance.primaryFocus?.unfocus();

    final name = _nameCtrl.text.trim();
    final price = _parseInventoryNumber(_priceCtrl.text);
    final cost = _parseInventoryNumber(_costCtrl.text);
    final stock = _parseInventoryNumber(_stockCtrl.text);
    final category = _categoryCtrl.text.trim();
    if (name.isEmpty ||
        price == null ||
        cost == null ||
        stock == null ||
        category.isEmpty) {
      setState(
        () => _formError = 'Completa nombre, precio, costo, stock y categoría',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final repo = ref.read(catalogRepositoryProvider);
      String? uploadedImagePath;
      if (_imageBytes != null && _imageName != null) {
        uploadedImagePath = await repo.uploadImage(
          bytes: _imageBytes!,
          filename: _imageName!,
        );
        final cachedUrl = buildProductImageUrl(
          imageUrl: uploadedImagePath,
          baseUrl: Env.apiBaseUrl,
        );
        unawaited(
          FulltechImageCacheManager.putImageBytes(
            url: cachedUrl,
            bytes: _imageBytes!,
            filename: _imageName,
          ),
        );
      }

      final product = _product;
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

      if (!mounted) return;
      debugPrint('[ProductForm#$hashCode] pop saved');
      Navigator.of(context).pop(const ProductFormResult(saved: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _formError = 'No se pudo guardar: $e';
      });
    }
  }

  void _close() {
    if (_isSaving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    debugPrint('[ProductForm#$hashCode] pop cancel');
    Navigator.of(context).pop(const ProductFormResult(saved: false));
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final existingImageUrl = product?.displayFotoUrl?.trim() ?? '';

    return _InventorySidePanelScaffold(
      title: product == null ? 'Nuevo producto' : 'Editar producto',
      icon: product == null ? Icons.add_box_outlined : Icons.edit_outlined,
      onClose: _isSaving ? null : _close,
      onSubmit: _isSaving ? null : _save,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_formError != null) ...[
              _FormErrorBanner(message: _formError!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              enabled: !_isSaving,
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
                    controller: _priceCtrl,
                    focusNode: _priceFocus,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
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
                    controller: _costCtrl,
                    focusNode: _costFocus,
                    enabled: !_isSaving,
                    keyboardType: const TextInputType.numberWithOptions(
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
              controller: _stockCtrl,
              focusNode: _stockFocus,
              enabled: !_isSaving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Stock disponible',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _categoryCtrl,
              focusNode: _categoryFocus,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Categoría',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final category in widget.categories)
                    ChoiceChip(
                      label: Text(category),
                      selected: _categoryCtrl.text.trim() == category,
                      onSelected: _isSaving
                          ? null
                          : (_) {
                              setState(() {
                                _categoryCtrl.text = category;
                              });
                            },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _isSaving || _isPickingImage ? null : _pickImage,
              icon: _isPickingImage
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(
                _isPickingImage
                    ? 'Seleccionando imagen...'
                    : _imageName ?? 'Subir imagen desde el ordenador',
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
              child: _imageBytes != null
                  ? Image.memory(
                      _imageBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                  : (product != null && existingImageUrl.isNotEmpty)
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
      footer: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save_outlined),
          label: Text(product == null ? 'Crear producto' : 'Guardar cambios'),
        ),
      ),
    );
  }
}

class _FormErrorBanner extends StatelessWidget {
  const _FormErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFB91C1C),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
