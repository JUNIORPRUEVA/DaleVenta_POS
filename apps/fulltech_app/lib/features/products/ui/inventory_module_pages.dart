import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/api/env.dart';
import '../../../core/auth/admin_authorization.dart';
import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/models/product_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/media_file_actions.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/local_file_bytes.dart';
import '../../../core/utils/product_image_url.dart';
import '../../../core/utils/simple_xlsx.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../core/widgets/fulltech_dialog.dart';
import '../../../core/widgets/fulltech_page_header.dart';
import '../../../core/widgets/product_network_image.dart';
import '../../catalogo/application/catalog_controller.dart';
import '../../catalogo/data/catalog_repository.dart';

const _primaryBlue = AppColors.secondary;
const _lightBlueHover = AppColors.secondarySoft;
const _textSecondary = AppColors.textMuted;
const _borderSoft = AppColors.border;
const _pageBackground = AppColors.background;
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
  _StockLevel.out => AppColors.error,
  _StockLevel.low => AppColors.warning,
  _StockLevel.high => AppColors.secondary,
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
  final codeIndex = hasHeader
      ? indexOf(['codigo', 'code', 'sku', 'barcode', 'codigo barra'], -1)
      : -1;
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
    final codigo = cell(codeIndex);
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
        codigo: codigo.isEmpty ? null : codigo,
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

Future<Uint8List?> _readPickedFileBytes(PlatformFile file) async {
  final memoryBytes = file.bytes;
  if (memoryBytes != null && memoryBytes.isNotEmpty) {
    return Uint8List.fromList(memoryBytes);
  }
  final path = file.path;
  if (path == null || path.trim().isEmpty) return null;
  final localBytes = await readLocalFileBytes(path);
  return localBytes.isEmpty ? null : Uint8List.fromList(localBytes);
}

String _normalizeImportCode(String? value) {
  return (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String _normalizeImportText(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String _importIdentityKey({
  required String nombre,
  String? codigo,
  required double precio,
  required double costo,
  required double stock,
  required String categoria,
}) {
  final code = _normalizeImportCode(codigo);
  if (code.isNotEmpty) return 'code:$code';
  return [
    'identity',
    _normalizeImportText(nombre),
    _normalizeImportText(categoria),
    precio.toStringAsFixed(2),
    costo.toStringAsFixed(2),
    stock.toStringAsFixed(2),
  ].join('|');
}

class _CatalogImportDecision {
  const _CatalogImportDecision({required this.updateExisting});

  final bool updateExisting;
}

class _CatalogImportSummary {
  const _CatalogImportSummary({
    required this.newProducts,
    required this.existingProducts,
    required this.fileDuplicates,
  });

  final int newProducts;
  final int existingProducts;
  final int fileDuplicates;
}

_CatalogImportSummary _analyzeImport({
  required List<ProductModel> products,
  required List<CatalogImportDraft> drafts,
}) {
  final existingKeys = <String>{};
  for (final product in products) {
    existingKeys.add(
      _importIdentityKey(
        nombre: product.nombre,
        codigo: product.codigo,
        precio: product.precio,
        costo: product.costo,
        stock: product.stock ?? 0,
        categoria: product.categoriaLabel,
      ),
    );
    final identityWithoutCode = _importIdentityKey(
      nombre: product.nombre,
      precio: product.precio,
      costo: product.costo,
      stock: product.stock ?? 0,
      categoria: product.categoriaLabel,
    );
    existingKeys.add(identityWithoutCode);
  }

  final seenFileKeys = <String>{};
  var newProducts = 0;
  var existingProducts = 0;
  var fileDuplicates = 0;
  for (final draft in drafts) {
    final key = _importIdentityKey(
      nombre: draft.nombre,
      codigo: draft.codigo,
      precio: draft.precio,
      costo: draft.costo,
      stock: draft.stock,
      categoria: draft.categoria,
    );
    if (!seenFileKeys.add(key)) {
      fileDuplicates += 1;
      continue;
    }
    final identityWithoutCode = _importIdentityKey(
      nombre: draft.nombre,
      precio: draft.precio,
      costo: draft.costo,
      stock: draft.stock,
      categoria: draft.categoria,
    );
    if (existingKeys.contains(key) ||
        existingKeys.contains(identityWithoutCode)) {
      existingProducts += 1;
    } else {
      newProducts += 1;
    }
  }
  return _CatalogImportSummary(
    newProducts: newProducts,
    existingProducts: existingProducts,
    fileDuplicates: fileDuplicates,
  );
}

class _ImportSummaryLine extends StatelessWidget {
  const _ImportSummaryLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _primaryBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class InventoryModulePages extends ConsumerStatefulWidget {
  const InventoryModulePages({super.key, this.initialMobileTab});

  final String? initialMobileTab;

  @override
  ConsumerState<InventoryModulePages> createState() =>
      _InventoryModulePagesState();
}

class _InventoryModulePagesState extends ConsumerState<InventoryModulePages> {
  final _catalogKey = GlobalKey<_CatalogTabState>();
  final _stockKey = GlobalKey<_StockAdjustmentsPageState>();
  final _categoriesKey = GlobalKey<_CategoriesTabState>();
  final _inventoryKey = GlobalKey<_InventoryTabState>();
  final _mobileSearchCtrl = TextEditingController();
  bool _mobileSearchOpen = false;
  int _mobileTabIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(catalogControllerProvider.notifier).load(silent: true);
    });
  }

  @override
  void dispose() {
    _mobileSearchCtrl.dispose();
    super.dispose();
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
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.editProducts,
      reason: product == null ? 'Crear producto' : 'Editar producto',
    );
    if (!allowed || !mounted) return;
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
    await ref
        .read(catalogControllerProvider.notifier)
        .load(forceRemote: true, silent: true);
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
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.addStock,
      reason: 'Ajustar stock de producto',
    );
    if (!allowed || !mounted) return;
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

  Future<void> _exportProductsSelection(List<ProductModel> products) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona productos para exportar')),
      );
      return;
    }
    final saved = await saveMediaBytes(
      bytes: _buildInventoryWorkbook(
        products: products,
        suppliers: ref.read(inventorySuppliersProvider).items,
      ),
      fileName:
          'catalogo_seleccion_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      allowedExtensions: const ['xlsx'],
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? 'Selección exportada' : 'Exportación cancelada'),
      ),
    );
  }

  Future<void> _showProductsPdf(List<ProductModel> products) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona productos para ver el PDF')),
      );
      return;
    }
    final bytes = await _buildProductsPdf(products);
    if (!mounted) return;
    await Printing.layoutPdf(
      name: 'productos_seleccion.pdf',
      onLayout: (_) async => bytes,
    );
  }

  Future<Uint8List> _buildProductsPdf(List<ProductModel> products) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'Catálogo seleccionado',
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('${products.length} productos'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: .5),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue50),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellPadding: const pw.EdgeInsets.all(5),
            headers: const [
              'Código',
              'Producto',
              'Categoría',
              'Stock',
              'Precio',
            ],
            data: [
              for (final product in products)
                [
                  product.codigo?.trim().isNotEmpty == true
                      ? product.codigo!.trim()
                      : 'Sin SKU',
                  product.nombre,
                  product.categoriaLabel,
                  _stockText(product.stock),
                  formatRdCurrencyAccounting(product.precio),
                ],
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  Future<void> _deleteProductsSelection(List<ProductModel> products) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona productos para eliminar')),
      );
      return;
    }
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.editProducts,
      reason: 'Eliminar productos',
    );
    if (!allowed || !mounted) return;
    final confirmed = await FullTechConfirmDialog.show(
      context,
      title: 'Eliminar selección',
      message: '¿Deseas eliminar ${products.length} productos seleccionados?',
      confirmText: 'Eliminar',
      cancelText: 'Cancelar',
      icon: Icons.delete_outline_rounded,
      iconColor: FullTechDialogTokens.errorColor,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    final controller = ref.read(catalogControllerProvider.notifier);
    for (final product in products) {
      await controller.remove(product.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${products.length} productos eliminados')),
    );
  }

  Future<void> _importCatalog() async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.editProducts,
      reason: 'Importar catálogo de productos',
    );
    if (!allowed || !mounted) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'txt'],
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;

    try {
      final bytes = await _readPickedFileBytes(file);
      if (!mounted) return;
      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer el archivo seleccionado'),
          ),
        );
        return;
      }
      final extension = (file.extension ?? '').trim().toLowerCase();
      final isExcel = extension == 'xlsx';
      final bundle = isExcel
          ? _parseCatalogWorkbook(bytes)
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

      final importDecision = await _showImportDecisionDialog(
        context,
        products: ref.read(catalogControllerProvider).items,
        drafts: bundle.products,
        categoriesCount: bundle.categories.length,
        suppliersCount: bundle.suppliers.length,
      );
      if (importDecision == null || !mounted) return;

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
      if (!mounted) return;
      final progress = ValueNotifier<CatalogImportProgress>(
        const CatalogImportProgress(done: 0, total: 0, current: ''),
      );
      unawaited(_showImportProgressDialog(rootNavigator.context, progress));
      CatalogImportResult imported;
      try {
        imported = bundle.products.isEmpty
            ? const CatalogImportResult(
                created: 0,
                updated: 0,
                skippedExisting: 0,
                skippedFileDuplicates: 0,
              )
            : await ref
                  .read(catalogControllerProvider.notifier)
                  .importProducts(
                    bundle.products,
                    updateExisting: importDecision.updateExisting,
                    onProgress: (value) => progress.value = value,
                  );
      } finally {
        if (rootNavigator.canPop()) {
          rootNavigator.pop();
        }
        progress.dispose();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importación lista: ${imported.created} nuevos, ${imported.updated} actualizados, ${imported.skippedExisting} existentes omitidos, ${imported.skippedFileDuplicates} repetidos del archivo omitidos.',
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

  void _setMobileSearch(String value) {
    switch (_mobileTabIndex) {
      case 1:
        _inventoryKey.currentState?.setSearchQuery(value);
        break;
      case 2:
        _stockKey.currentState?.setSearchQuery(value);
        break;
      case 3:
        _categoriesKey.currentState?.setSearchQuery(value);
        break;
      default:
        _catalogKey.currentState?.setSearchQuery(value);
        break;
    }
  }

  void _toggleMobileSearch() {
    setState(() {
      _mobileSearchOpen = !_mobileSearchOpen;
      if (!_mobileSearchOpen) {
        _mobileSearchCtrl.clear();
        _setMobileSearch('');
      }
    });
  }

  void _openCurrentMobileFilters() {
    switch (_mobileTabIndex) {
      case 1:
        _inventoryKey.currentState?.openMobileFilters();
        break;
      case 2:
        _stockKey.currentState?.openMobileFilters();
        break;
      case 3:
        _categoriesKey.currentState?.openMobileFilters();
        break;
      default:
        _catalogKey.currentState?.openMobileFilters();
        break;
    }
  }

  void _runCurrentMobileAdd() {
    switch (_mobileTabIndex) {
      case 3:
        _categoriesKey.currentState?.openNewCategory();
        break;
      case 1:
        break;
      default:
        _openProductEditor();
        break;
    }
  }

  Future<void> _handleMobileOverflow(String action) async {
    if (_mobileTabIndex != 0) return;
    switch (action) {
      case 'import':
        await _importCatalog();
        break;
      case 'export':
        await _exportCatalog();
        break;
      case 'export-selected':
        await _catalogKey.currentState?.exportSelected();
        break;
      case 'pdf':
        await _catalogKey.currentState?.showSelectedPdf();
        break;
      case 'delete':
        await _catalogKey.currentState?.deleteSelected();
        break;
    }
  }

  Future<_CatalogImportDecision?> _showImportDecisionDialog(
    BuildContext context, {
    required List<ProductModel> products,
    required List<CatalogImportDraft> drafts,
    required int categoriesCount,
    required int suppliersCount,
  }) {
    final summary = _analyzeImport(products: products, drafts: drafts);
    return showDialog<_CatalogImportDecision>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Importación inteligente'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ImportSummaryLine(
                icon: Icons.add_box_outlined,
                label: 'Nuevos',
                value: summary.newProducts,
              ),
              _ImportSummaryLine(
                icon: Icons.sync_alt_rounded,
                label: 'Ya existen',
                value: summary.existingProducts,
              ),
              _ImportSummaryLine(
                icon: Icons.content_copy_outlined,
                label: 'Repetidos en archivo',
                value: summary.fileDuplicates,
              ),
              _ImportSummaryLine(
                icon: Icons.category_outlined,
                label: 'Categorías',
                value: categoriesCount,
              ),
              _ImportSummaryLine(
                icon: Icons.local_shipping_outlined,
                label: 'Suplidores',
                value: suppliersCount,
              ),
              const SizedBox(height: 12),
              Text(
                summary.existingProducts > 0
                    ? 'Puedes importar solo los productos nuevos o actualizar los existentes con los datos del archivo.'
                    : 'Se importarán solo productos nuevos; los repetidos del archivo se omiten automáticamente.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton.tonal(
              onPressed: summary.newProducts == 0
                  ? null
                  : () => Navigator.of(
                      dialogContext,
                    ).pop(const _CatalogImportDecision(updateExisting: false)),
              child: const Text('Solo nuevos'),
            ),
            FilledButton(
              onPressed: summary.existingProducts == 0
                  ? null
                  : () => Navigator.of(
                      dialogContext,
                    ).pop(const _CatalogImportDecision(updateExisting: true)),
              child: const Text('Actualizar existentes'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showImportProgressDialog(
    BuildContext context,
    ValueNotifier<CatalogImportProgress> progress,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Importando productos'),
            content: ValueListenableBuilder<CatalogImportProgress>(
              valueListenable: progress,
              builder: (context, value, _) {
                final total = value.total <= 0 ? 1 : value.total;
                final ratio = (value.done / total).clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: ratio),
                    const SizedBox(height: 12),
                    Text('${value.done} de ${value.total} productos'),
                    if (value.current.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        value.current,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final state = ref.watch(catalogControllerProvider);
    final products = state.items;
    final canEditProducts = user != null;
    final canAddStock = user != null;
    final isMobile = MediaQuery.sizeOf(context).width < 640;
    var tab = widget.initialMobileTab;
    if (tab == null) {
      try {
        tab = GoRouterState.of(context).uri.queryParameters['tab'];
      } catch (_) {
        tab = null;
      }
    }
    final initialTabIndex = switch (tab) {
      'inventory' => 1,
      'stock' => 2,
      'categories' => 3,
      _ => 0,
    };
    _mobileTabIndex = initialTabIndex;
    final desktopTitle = switch (initialTabIndex) {
      1 => 'Recuento de inventario',
      2 => 'Ajuste stock',
      3 => 'Categorías',
      _ => 'Catálogo',
    };
    final mobileTitle = switch (initialTabIndex) {
      1 => 'Conteo',
      2 => 'Stock',
      3 => 'Categorías',
      _ => 'Catálogo',
    };

    final pages = [
      CatalogTab(
        key: _catalogKey,
        products: products,
        loading: state.refreshing,
        error: state.error,
        onRefresh: _refresh,
        onCreate: () => _openProductEditor(),
        onImport: _importCatalog,
        onExport: _exportCatalog,
        onExportSelection: _exportProductsSelection,
        onPdfSelection: _showProductsPdf,
        onBulkDelete: _deleteProductsSelection,
        onEdit: (product) => _openProductEditor(product: product),
        onSetStock: _setProductStock,
        canEditProducts: canEditProducts,
        canAddStock: canAddStock,
        onDelete: (product) async {
          final allowed = await ensureAdminAuthorization(
            context,
            ref,
            permission: AppPermission.editProducts,
            reason: 'Eliminar producto',
          );
          if (!allowed || !context.mounted) return;
          await ref.read(catalogControllerProvider.notifier).remove(product.id);
        },
      ),
      InventoryTab(key: _inventoryKey, products: products, onRefresh: _refresh),
      StockAdjustmentsPage(
        key: _stockKey,
        products: products,
        onRefresh: _refresh,
        onSetStock: _setProductStock,
        canAddStock: canAddStock,
      ),
      CategoriesTab(
        key: _categoriesKey,
        products: products,
        onRefresh: _refresh,
      ),
    ];

    return DefaultTabController(
      length: 4,
      initialIndex: initialTabIndex,
      child: Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        backgroundColor: _pageBackground,
        appBar: isMobile
            ? CustomAppBar(
                title: mobileTitle,
                showLogo: false,
                showDepartmentLabel: false,
                trailing: const SizedBox.shrink(),
                titleWidget: _mobileSearchOpen
                    ? _InventoryMobileSearchField(
                        controller: _mobileSearchCtrl,
                        hintText: 'Buscar en $mobileTitle',
                        onChanged: _setMobileSearch,
                        onClose: _toggleMobileSearch,
                      )
                    : null,
                actions: [
                  if (initialTabIndex == 0 || initialTabIndex == 3)
                    _AnimatedInventoryAction(
                      tooltip: initialTabIndex == 3
                          ? 'Nueva categoría'
                          : 'Nuevo producto',
                      icon: initialTabIndex == 3
                          ? Icons.create_new_folder_outlined
                          : Icons.add_rounded,
                      onPressed: canEditProducts ? _runCurrentMobileAdd : null,
                    ),
                  if (initialTabIndex != 1)
                    IconButton(
                      tooltip: _mobileSearchOpen ? 'Cerrar búsqueda' : 'Buscar',
                      onPressed: _toggleMobileSearch,
                      icon: Icon(
                        _mobileSearchOpen
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                      ),
                    ),
                  IconButton(
                    tooltip: 'Filtros',
                    onPressed: _openCurrentMobileFilters,
                    icon: const Icon(Icons.filter_alt_outlined),
                  ),
                  if (initialTabIndex == 0)
                    PopupMenuButton<String>(
                      tooltip: 'Más opciones',
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) =>
                          unawaited(_handleMobileOverflow(value)),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'import',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.upload_file_rounded),
                            title: Text('Importar'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.download_rounded),
                            title: Text('Exportar todo'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'export-selected',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.file_download_outlined),
                            title: Text('Exportar selección'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pdf',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.picture_as_pdf_outlined),
                            title: Text('PDF selección'),
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.delete_outline_rounded),
                            title: Text('Eliminar selección'),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(width: 4),
                ],
              )
            : FullTechPageHeader(
                title: desktopTitle,
                actions: [
                  if (initialTabIndex == 0)
                    FilledButton.icon(
                      onPressed: canEditProducts
                          ? () => _openProductEditor()
                          : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Nuevo producto'),
                    ),
                  if (initialTabIndex == 3)
                    FilledButton.icon(
                      onPressed: canEditProducts
                          ? () => _categoriesKey.currentState?.openNewCategory()
                          : null,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      label: const Text('Nueva categoría'),
                    ),
                  if (initialTabIndex == 1)
                    IconButton(
                      tooltip: 'Filtrar recuento',
                      onPressed: () =>
                          _inventoryKey.currentState?.openMobileFilters(),
                      icon: const Icon(Icons.filter_alt_outlined),
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
              ),
        body: Stack(
          children: [
            Positioned.fill(
              child: isMobile ? pages[initialTabIndex] : pages[initialTabIndex],
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
  final fraction = width >= 1200 ? 0.96 : (width >= 760 ? 0.94 : 0.98);
  final contentWidth = (width * fraction).clamp(0.0, 1400.0);
  final horizontal = ((width - contentWidth) / 2).clamp(8.0, 28.0);
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}

class _InventoryMobileSearchField extends StatelessWidget {
  const _InventoryMobileSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(color: _textSecondary, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          suffixIcon: IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _AnimatedInventoryAction extends StatefulWidget {
  const _AnimatedInventoryAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  State<_AnimatedInventoryAction> createState() =>
      _AnimatedInventoryActionState();
}

class _AnimatedInventoryActionState extends State<_AnimatedInventoryAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      lowerBound: 0.96,
      upperBound: 1.06,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _controller,
      child: IconButton.filled(
        tooltip: widget.tooltip,
        onPressed: widget.onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          foregroundColor: Colors.white,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
        ),
        icon: Icon(widget.icon, size: 19),
      ),
    );
  }
}

Future<T?> _showInventoryFilterDrawer<T>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Widget child,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final panelWidth = (width * 0.88).clamp(300.0, 370.0).toDouble();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Filtros',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: panelWidth,
          child: _InventoryFilterShell(
            title: title,
            subtitle: subtitle,
            child: child,
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

class _InventoryFilterShell extends StatelessWidget {
  const _InventoryFilterShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      left: false,
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(22)),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1957E6), Color(0xFF47A3FF)],
                ),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(22)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
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
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF6FAFF), Colors.white],
                  ),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogFilterDraft {
  const _CatalogFilterDraft({
    required this.category,
    required this.lowStock,
    required this.outStock,
    this.clearSearch = false,
  });

  final String? category;
  final bool lowStock;
  final bool outStock;
  final bool clearSearch;
}

class _StockFilterDraft {
  const _StockFilterDraft({
    required this.category,
    required this.stockFilter,
    this.clearSearch = false,
  });

  final String category;
  final _StockFilter stockFilter;
  final bool clearSearch;
}

class _CatalogMobileFilterPanel extends StatefulWidget {
  const _CatalogMobileFilterPanel({
    required this.categories,
    required this.selectedCategory,
    required this.onlyLowStock,
    required this.onlyOutStock,
    required this.canImport,
    required this.onImport,
    required this.onExport,
  });

  final List<String> categories;
  final String? selectedCategory;
  final bool onlyLowStock;
  final bool onlyOutStock;
  final bool canImport;
  final Future<void> Function()? onImport;
  final Future<void> Function() onExport;

  @override
  State<_CatalogMobileFilterPanel> createState() =>
      _CatalogMobileFilterPanelState();
}

class _CatalogMobileFilterPanelState extends State<_CatalogMobileFilterPanel> {
  String? _category;
  late bool _lowStock;
  late bool _outStock;

  @override
  void initState() {
    super.initState();
    _category = widget.selectedCategory;
    _lowStock = widget.onlyLowStock;
    _outStock = widget.onlyOutStock;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        _FilterBlockTitle('Categoría'),
        DropdownButtonFormField<String?>(
          initialValue: _category,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Todas las categorías'),
            ),
            for (final category in widget.categories)
              DropdownMenuItem(value: category, child: Text(category)),
          ],
          onChanged: (value) => setState(() => _category = value),
          decoration: _inventoryTextInputDecoration('Categoría'),
        ),
        const SizedBox(height: 18),
        _FilterBlockTitle('Stock'),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _lowStock,
          onChanged: (value) => setState(() => _lowStock = value),
          title: const Text('Stock bajo'),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _outStock,
          onChanged: (value) => setState(() => _outStock = value),
          title: const Text('Agotados'),
        ),
        const SizedBox(height: 18),
        _FilterBlockTitle('Herramientas'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: widget.canImport && widget.onImport != null
                    ? () {
                        Navigator.of(context).pop();
                        unawaited(widget.onImport!.call());
                      }
                    : null,
                icon: const Icon(Icons.upload_file_rounded, size: 17),
                label: const Text('Importar'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  unawaited(widget.onExport());
                },
                icon: const Icon(Icons.download_rounded, size: 17),
                label: const Text('Exportar'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(
            const _CatalogFilterDraft(
              category: null,
              lowStock: false,
              outStock: false,
              clearSearch: true,
            ),
          ),
          icon: const Icon(Icons.cleaning_services_outlined, size: 17),
          label: const Text('Limpiar todo'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            _CatalogFilterDraft(
              category: _category,
              lowStock: _lowStock,
              outStock: _outStock,
            ),
          ),
          icon: const Icon(Icons.check_rounded, size: 17),
          label: const Text('Aplicar filtros'),
        ),
      ],
    );
  }
}

class _StockMobileFilterPanel extends StatefulWidget {
  const _StockMobileFilterPanel({
    required this.categories,
    required this.categoryFilter,
    required this.stockFilter,
  });

  final List<String> categories;
  final String categoryFilter;
  final _StockFilter stockFilter;

  @override
  State<_StockMobileFilterPanel> createState() =>
      _StockMobileFilterPanelState();
}

class _StockMobileFilterPanelState extends State<_StockMobileFilterPanel> {
  late String _category;
  late _StockFilter _stockFilter;

  @override
  void initState() {
    super.initState();
    _category = widget.categoryFilter;
    _stockFilter = widget.stockFilter;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        _FilterBlockTitle('Categoría'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          isExpanded: true,
          items: [
            const DropdownMenuItem(
              value: 'Todas las categorías',
              child: Text('Todas las categorías'),
            ),
            for (final category in widget.categories)
              DropdownMenuItem(value: category, child: Text(category)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _category = value);
          },
          decoration: _inventoryTextInputDecoration('Categoría'),
        ),
        const SizedBox(height: 18),
        _FilterBlockTitle('Estado de stock'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final filter in _StockFilter.values)
              ChoiceChip(
                label: Text(filter.label),
                selected: _stockFilter == filter,
                onSelected: (_) => setState(() => _stockFilter = filter),
              ),
          ],
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(
            const _StockFilterDraft(
              category: 'Todas las categorías',
              stockFilter: _StockFilter.all,
              clearSearch: true,
            ),
          ),
          icon: const Icon(Icons.cleaning_services_outlined, size: 17),
          label: const Text('Limpiar todo'),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(
            _StockFilterDraft(category: _category, stockFilter: _stockFilter),
          ),
          icon: const Icon(Icons.check_rounded, size: 17),
          label: const Text('Aplicar filtros'),
        ),
      ],
    );
  }
}

class _CategoriesMobileFilterPanel extends StatelessWidget {
  const _CategoriesMobileFilterPanel({
    required this.managedCount,
    required this.visibleCount,
    required this.productCount,
  });

  final int managedCount;
  final int visibleCount;
  final int productCount;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        _FilterBlockTitle('Resumen'),
        _DrawerMetric(label: 'Creadas', value: '$managedCount'),
        _DrawerMetric(label: 'Visibles', value: '$visibleCount'),
        _DrawerMetric(label: 'Productos', value: '$productCount'),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.cleaning_services_outlined, size: 17),
          label: const Text('Limpiar búsqueda'),
        ),
      ],
    );
  }
}

class _FilterBlockTitle extends StatelessWidget {
  const _FilterBlockTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w900,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _DrawerMetric extends StatelessWidget {
  const _DrawerMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
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
    required this.onExportSelection,
    required this.onPdfSelection,
    required this.onBulkDelete,
    required this.onEdit,
    required this.onSetStock,
    required this.canEditProducts,
    required this.canAddStock,
    required this.onDelete,
  });

  final List<ProductModel> products;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;
  final Future<void> Function() onImport;
  final Future<void> Function() onExport;
  final Future<void> Function(List<ProductModel> products) onExportSelection;
  final Future<void> Function(List<ProductModel> products) onPdfSelection;
  final Future<void> Function(List<ProductModel> products) onBulkDelete;
  final ValueChanged<ProductModel> onEdit;
  final Future<void> Function(ProductModel product, double stock) onSetStock;
  final bool canEditProducts;
  final bool canAddStock;
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
        .map((product) => product.categoriaLabel.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  String? _validCategory(List<String> categories) {
    final selected = _category?.trim();
    if (selected == null || selected.isEmpty) return null;
    return categories.contains(selected) ? selected : null;
  }

  List<ProductModel> _visibleFor(String? category) {
    final query = _query.trim().toLowerCase();
    return widget.products.where((product) {
      if (category != null && product.categoriaLabel != category) {
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

  List<ProductModel> get _selectedProducts => widget.products
      .where((product) => _selectedIds.contains(product.id))
      .toList(growable: false);

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void setSearchQuery(String value) {
    _debounce?.cancel();
    if (mounted) setState(() => _query = value);
  }

  Future<void> openMobileFilters() async {
    final result = await _showInventoryFilterDrawer<_CatalogFilterDraft>(
      context,
      title: 'Filtros',
      subtitle: 'Catálogo',
      child: _CatalogMobileFilterPanel(
        categories: _categories,
        selectedCategory: _validCategory(_categories),
        onlyLowStock: _onlyLowStock,
        onlyOutStock: _onlyOutStock,
        canImport: widget.canEditProducts,
        onImport: widget.onImport,
        onExport: widget.onExport,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _category = result.category;
      _onlyLowStock = result.lowStock;
      _onlyOutStock = result.outStock;
      if (result.clearSearch) {
        _searchCtrl.clear();
        _query = '';
      }
    });
  }

  Future<void> exportSelected() => widget.onExportSelection(_selectedProducts);

  Future<void> showSelectedPdf() => widget.onPdfSelection(_selectedProducts);

  Future<void> deleteSelected() async {
    final selected = _selectedProducts;
    await widget.onBulkDelete(selected);
    if (!mounted) return;
    setState(() {
      _selectedIds.removeAll(selected.map((product) => product.id));
    });
  }

  void _openProductDetail(ProductModel product) {
    if (MediaQuery.sizeOf(context).width >= 640) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProductDetailPage(
          product: product,
          onEdit: widget.canEditProducts ? () => widget.onEdit(product) : null,
          onStock: widget.canAddStock
              ? () => _showStockAdjustmentPanel(
                  context,
                  product: product,
                  onSetStock: widget.onSetStock,
                )
              : null,
          onDelete: () => _confirmDelete(product),
        ),
      ),
    );
  }

  void _selectAllVisible(bool selected) {
    final visible = _visibleFor(_validCategory(_categories));
    setState(() {
      if (selected) {
        _selectedIds.addAll(visible.map((product) => product.id));
      } else {
        _selectedIds.removeAll(visible.map((product) => product.id));
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
    final categories = _categories;
    final selectedCategory = _validCategory(categories);
    if (_category != selectedCategory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _category != selectedCategory) {
          setState(() => _category = selectedCategory);
        }
      });
    }
    final visible = _visibleFor(selectedCategory);
    final allSelected =
        visible.isNotEmpty &&
        visible.every((product) => _selectedIds.contains(product.id));

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final mobile = constraints.maxWidth < 640;
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              if (!mobile) ...[
                _CatalogToolbar(
                  controller: _searchCtrl,
                  categories: categories,
                  selectedCategory: selectedCategory,
                  onlyLowStock: _onlyLowStock,
                  onlyOutStock: _onlyOutStock,
                  selectedCount: _selectedIds.length,
                  onSearchChanged: _onSearchChanged,
                  onCategoryChanged: (value) =>
                      setState(() => _category = value),
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
                  onCreate: widget.canEditProducts ? widget.onCreate : null,
                  onImport: widget.canEditProducts ? widget.onImport : null,
                  onExport: widget.onExport,
                ),
                const SizedBox(height: 12),
              ],
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
                  canEditProducts: widget.canEditProducts,
                  canAddStock: widget.canAddStock,
                  onDelete: _confirmDelete,
                  onOpenDetail: _openProductDetail,
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
                  canEditProducts: widget.canEditProducts,
                  canAddStock: widget.canAddStock,
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
  final VoidCallback? onCreate;
  final Future<void> Function()? onImport;
  final Future<void> Function() onExport;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    final categoryOptions =
        categories
            .map((category) => category.trim())
            .where((category) => category.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final safeSelectedCategory =
        selectedCategory != null && categoryOptions.contains(selectedCategory)
        ? selectedCategory
        : null;
    return ProductsSurface(
      padding: EdgeInsets.all(mobile ? 10 : 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: mobile ? double.infinity : 360,
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
            child: SizedBox(
              width: mobile ? double.infinity : null,
              child: DropdownButton<String?>(
                value: safeSelectedCategory,
                isExpanded: mobile,
                hint: const Text('Todas las categorías'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Todas las categorías'),
                  ),
                  for (final category in categoryOptions)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: onCategoryChanged,
              ),
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
          if (mobile)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onImport,
                    icon: const Icon(Icons.upload_file_rounded, size: 17),
                    label: const Text('Importar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onExport,
                    icon: const Icon(Icons.download_rounded, size: 17),
                    label: const Text('Exportar'),
                  ),
                ),
              ],
            )
          else ...[
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
          ],
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
    required this.canEditProducts,
    required this.canAddStock,
    required this.onDelete,
  });

  final List<ProductModel> products;
  final Set<String> selectedIds;
  final bool allSelected;
  final ValueChanged<bool> onToggleAll;
  final void Function(ProductModel product, bool selected) onToggle;
  final ValueChanged<ProductModel> onEdit;
  final Future<void> Function(ProductModel product, double stock) onSetStock;
  final bool canEditProducts;
  final bool canAddStock;
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
                          onPressed: canEditProducts
                              ? () => onEdit(product)
                              : null,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Ajustar stock',
                          onPressed: canAddStock
                              ? () => _showStockAdjustmentPanel(
                                  context,
                                  product: product,
                                  onSetStock: onSetStock,
                                )
                              : null,
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
    required this.canEditProducts,
    required this.canAddStock,
    required this.onDelete,
    required this.onOpenDetail,
  });

  final List<ProductModel> products;
  final Set<String> selectedIds;
  final void Function(ProductModel product, bool selected) onToggle;
  final ValueChanged<ProductModel> onEdit;
  final Future<void> Function(ProductModel product, double stock) onSetStock;
  final bool canEditProducts;
  final bool canAddStock;
  final ValueChanged<ProductModel> onDelete;
  final ValueChanged<ProductModel> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 640;
    return ProductsSurface(
      padding: EdgeInsets.all(mobile ? 8 : 16),
      child: Column(
        children: [
          for (final product in products)
            CompactProductCard(
              product: product,
              selected: selectedIds.contains(product.id),
              onSelected: (value) => onToggle(product, value),
              onTap: () => onOpenDetail(product),
              onEdit: canEditProducts ? () => onEdit(product) : null,
              onStock: canAddStock
                  ? () => _showStockAdjustmentPanel(
                      context,
                      product: product,
                      onSetStock: onSetStock,
                    )
                  : null,
              onDelete: () => onDelete(product),
            ),
        ],
      ),
    );
  }
}

class InventoryTab extends StatefulWidget {
  const InventoryTab({
    super.key,
    required this.products,
    required this.onRefresh,
  });

  final List<ProductModel> products;
  final Future<void> Function() onRefresh;

  @override
  State<InventoryTab> createState() => _InventoryTabState();
}

class _InventoryTabState extends State<InventoryTab> {
  String _query = '';
  String _categoryFilter = 'Todas las categorías';
  _StockFilter _stockFilter = _StockFilter.all;

  List<String> get _categories {
    final values = widget.products
        .map((product) => product.categoriaLabel.trim())
        .where((category) => category.isNotEmpty)
        .toSet()
        .toList();
    values.sort();
    return values;
  }

  String _validCategoryFilter(List<String> categories) {
    if (_categoryFilter == 'Todas las categorías') return _categoryFilter;
    return categories.contains(_categoryFilter)
        ? _categoryFilter
        : 'Todas las categorías';
  }

  List<ProductModel> _visibleProducts(String categoryFilter) {
    final query = _query.trim().toLowerCase();
    return widget.products.where((product) {
      if (!product.activo) return false;
      if (categoryFilter != 'Todas las categorías' &&
          product.categoriaLabel != categoryFilter) {
        return false;
      }
      if (!_matchesStockFilter(product, _stockFilter)) return false;
      if (query.isEmpty) return true;
      return product.nombre.toLowerCase().contains(query) ||
          (product.codigo?.toLowerCase().contains(query) ?? false) ||
          product.categoriaLabel.toLowerCase().contains(query);
    }).toList();
  }

  void setSearchQuery(String value) {
    if (mounted) setState(() => _query = value);
  }

  Future<void> openMobileFilters() async {
    final result = await _showInventoryFilterDrawer<_StockFilterDraft>(
      context,
      title: 'Filtros',
      subtitle: 'Conteo',
      child: _StockMobileFilterPanel(
        categories: _categories,
        categoryFilter: _validCategoryFilter(_categories),
        stockFilter: _stockFilter,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _categoryFilter = result.category;
      _stockFilter = result.stockFilter;
      if (result.clearSearch) _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final categoryFilter = _validCategoryFilter(categories);
    if (_categoryFilter != categoryFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _categoryFilter != categoryFilter) {
          setState(() => _categoryFilter = categoryFilter);
        }
      });
    }
    final active = _visibleProducts(categoryFilter);
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
    final margin = totalCost <= 0 ? 0.0 : (profit / totalCost) * 100;
    final mobile = MediaQuery.sizeOf(context).width < 640;

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (mobile)
                        _InventoryMobileOverview(
                          totalCost: totalCost,
                          totalRevenue: totalRevenue,
                          profit: profit,
                          margin: margin,
                          totalUnits: totalUnits,
                          activeCount: active.length,
                          lowStock: lowStock,
                          outStock: outStock,
                        )
                      else
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InventoryMobileOverview extends StatelessWidget {
  const _InventoryMobileOverview({
    required this.totalCost,
    required this.totalRevenue,
    required this.profit,
    required this.margin,
    required this.totalUnits,
    required this.activeCount,
    required this.lowStock,
    required this.outStock,
  });

  final double totalCost;
  final double totalRevenue;
  final double profit;
  final double margin;
  final double totalUnits;
  final int activeCount;
  final int lowStock;
  final int outStock;

  @override
  Widget build(BuildContext context) {
    final maxMoney = [
      totalCost,
      totalRevenue,
      profit.abs(),
    ].fold<double>(1, (max, value) => value > max ? value : max);
    final alerts = lowStock + outStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Resumen de inventario',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 12),
              _InventoryBar(
                label: 'Costo',
                value: totalCost,
                maxValue: maxMoney,
                color: _primaryBlue,
              ),
              _InventoryBar(
                label: 'Venta',
                value: totalRevenue,
                maxValue: maxMoney,
                color: const Color(0xFF16A34A),
              ),
              _InventoryBar(
                label: 'Ganancia',
                value: profit,
                maxValue: maxMoney,
                color: const Color(0xFF7C3AED),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InventoryStatPill(
                label: 'Unidades',
                value: _stockText(totalUnits),
                icon: Icons.inventory_2_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InventoryStatPill(
                label: 'Activos',
                value: '$activeCount',
                icon: Icons.check_circle_outline,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _InventoryStatPill(
                label: 'Margen',
                value: '${margin.toStringAsFixed(1)}%',
                icon: Icons.percent_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _InventoryStatPill(
                label: 'Alertas',
                value: '$alerts',
                icon: Icons.warning_amber_rounded,
                color: alerts == 0
                    ? const Color(0xFF16A34A)
                    : AppColors.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InventoryBar extends StatelessWidget {
  const _InventoryBar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });

  final String label;
  final double value;
  final double maxValue;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = (value.abs() / maxValue).clamp(0.04, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                formatRdCurrencyAccounting(value),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryStatPill extends StatelessWidget {
  const _InventoryStatPill({
    required this.label,
    required this.value,
    required this.icon,
    this.color = _primaryBlue,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderSoft),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  label,
                  style: const TextStyle(color: _textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StockAdjustmentsPage extends StatefulWidget {
  const StockAdjustmentsPage({
    super.key,
    required this.products,
    required this.onRefresh,
    required this.onSetStock,
    required this.canAddStock,
    this.onClose,
  });

  final List<ProductModel> products;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ProductModel product, double stock) onSetStock;
  final bool canAddStock;
  final VoidCallback? onClose;

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

  String _validCategoryFilter(List<String> categories) {
    if (_categoryFilter == 'Todas las categorías') {
      return _categoryFilter;
    }
    return categories.contains(_categoryFilter)
        ? _categoryFilter
        : 'Todas las categorías';
  }

  List<ProductModel> _filteredProductsFor(String categoryFilter) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _products
        .where((product) {
          final matchesSearch =
              query.isEmpty ||
              product.nombre.toLowerCase().contains(query) ||
              (product.codigo?.toLowerCase().contains(query) ?? false);
          final matchesCategory =
              categoryFilter == 'Todas las categorías' ||
              product.categoriaLabel == categoryFilter;
          return matchesSearch &&
              matchesCategory &&
              _matchesStockFilter(product, _stockFilter);
        })
        .toList(growable: false);
  }

  void setSearchQuery(String value) {
    if (_searchCtrl.text != value) {
      _searchCtrl.text = value;
    }
    if (mounted) setState(() {});
  }

  Future<void> openMobileFilters() async {
    final result = await _showInventoryFilterDrawer<_StockFilterDraft>(
      context,
      title: 'Filtros',
      subtitle: 'Stock',
      child: _StockMobileFilterPanel(
        categories: _categories,
        categoryFilter: _validCategoryFilter(_categories),
        stockFilter: _stockFilter,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _categoryFilter = result.category;
      _stockFilter = result.stockFilter;
      if (result.clearSearch) _searchCtrl.clear();
    });
  }

  bool get _canSubmit {
    final selected =
        _selected ?? (_products.isNotEmpty ? _products.first : null);
    if (!widget.canAddStock ||
        _saving ||
        selected == null ||
        _quantity <= 0 ||
        !_quantity.isFinite) {
      return false;
    }
    return _previewStock(selected) >= 0;
  }

  Future<void> _applyAdjustment() async {
    if (!widget.canAddStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para ajustar stock')),
      );
      return;
    }
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
    final categories = _categories;
    final categoryFilter = _validCategoryFilter(categories);
    if (_categoryFilter != categoryFilter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _categoryFilter != categoryFilter) {
          setState(() => _categoryFilter = categoryFilter);
        }
      });
    }
    final selected =
        _selected ?? (_products.isNotEmpty ? _products.first : null);
    final filtered = _filteredProductsFor(categoryFilter);
    final mobile = MediaQuery.sizeOf(context).width < 640;

    Widget content() {
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
                if (widget.onClose != null)
                  const SingleActivator(LogicalKeyboardKey.escape):
                      widget.onClose!,
              },
              child: Focus(
                autofocus: true,
                child: RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      mobile ? 10 : 18,
                      mobile ? 10 : 18,
                      mobile ? 10 : 18,
                      16,
                    ),
                    children: [
                      if (!mobile) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (_) => setState(() {}),
                                decoration: _inventoryTextInputDecoration(
                                  'Buscar producto',
                                  prefixIcon: Icon(Icons.search_rounded),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(categoryFilter),
                                initialValue: categoryFilter,
                                items: [
                                  const DropdownMenuItem(
                                    value: 'Todas las categorías',
                                    child: Text('Todas las categorías'),
                                  ),
                                  for (final category in categories)
                                    DropdownMenuItem(
                                      value: category,
                                      child: Text(category),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _categoryFilter = value);
                                },
                                decoration: _inventoryTextInputDecoration(
                                  'Categoría',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _SquareSegmentedSelector<_StockFilter>(
                          values: _StockFilter.values,
                          selected: _stockFilter,
                          labelBuilder: (filter) => filter.label,
                          onChanged: (value) =>
                              setState(() => _stockFilter = value),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (selected != null)
                        _SelectedStockProduct(product: selected),
                      if (selected != null) ...[
                        const SizedBox(height: 12),
                        _SquareSegmentedSelector<String>(
                          values: const ['Agregar', 'Disminuir'],
                          selected: _mode,
                          labelBuilder: (value) => '$value stock',
                          iconBuilder: (value) => value == 'Agregar'
                              ? Icons.add_rounded
                              : Icons.remove_rounded,
                          onChanged: (value) => setState(() => _mode = value),
                        ),
                        const SizedBox(height: 10),
                        if (mobile) ...[
                          TextField(
                            controller: _qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: _inventoryTextInputDecoration(
                              'Cantidad',
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _noteCtrl,
                            decoration: _inventoryTextInputDecoration('Motivo'),
                          ),
                        ] else
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _qtyCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (_) => setState(() {}),
                                  decoration: _inventoryTextInputDecoration(
                                    'Cantidad',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _noteCtrl,
                                  decoration: _inventoryTextInputDecoration(
                                    'Motivo',
                                  ),
                                ),
                              ),
                            ],
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
                            onSelected: () =>
                                setState(() => _selected = product),
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
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  minimumSize: const Size.fromHeight(42),
                ),
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

    if (mobile) return content();

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = (constraints.maxWidth - 48)
            .clamp(760.0, 1180.0)
            .toDouble();
        return Center(
          child: SizedBox(
            width: frameWidth,
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 18, 0, 18),
              child: ProductsSurface(
                padding: EdgeInsets.zero,
                child: content(),
              ),
            ),
          ),
        );
      },
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
        border: Border.all(color: const Color(0xFFCFE0FF)),
      ),
      child: Row(
        children: [
          ProductThumbnail(product: product, size: 48, radius: 0),
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
                    color: AppColors.textPrimary,
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

class _SquareSegmentedSelector<T> extends StatelessWidget {
  const _SquareSegmentedSelector({
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onChanged,
    this.iconBuilder,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelBuilder;
  final IconData? Function(T value)? iconBuilder;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _borderSoft),
      ),
      child: Row(
        children: [
          for (var index = 0; index < values.length; index++) ...[
            if (index > 0) Container(width: 1, height: 34, color: _borderSoft),
            Expanded(
              child: _SquareSegmentButton<T>(
                selected: values[index] == selected,
                label: labelBuilder(values[index]),
                icon: iconBuilder?.call(values[index]),
                onTap: () => onChanged(values[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SquareSegmentButton<T> extends StatelessWidget {
  const _SquareSegmentButton({
    required this.selected,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final foreground = selected
        ? const Color(0xFF0F6170)
        : AppColors.textPrimary;
    return Material(
      color: selected ? const Color(0xFFD8F0F6) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: Color(0xFF0F6170),
                ),
                const SizedBox(width: 5),
              ] else if (icon != null) ...[
                Icon(icon, size: 15, color: foreground),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
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
        child: InkWell(
          onTap: onSelected,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? _primaryBlue : _borderSoft,
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: [
                ProductThumbnail(product: product, size: 38, radius: 0),
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
                          color: AppColors.textPrimary,
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
                    OutlinedButton(
                      onPressed: onSelected,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 26),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: const RoundedRectangleBorder(),
                        side: const BorderSide(color: _borderSoft),
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
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.editProducts,
      reason: category == null ? 'Crear categoría' : 'Editar categoría',
    );
    if (!allowed || !mounted) return;
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

  void setSearchQuery(String value) {
    if (mounted) setState(() => _query = value);
  }

  void openNewCategory() {
    unawaited(_openEditor());
  }

  Future<void> openMobileFilters() async {
    final result = await _showInventoryFilterDrawer<bool>(
      context,
      title: 'Filtros',
      subtitle: 'Categorías',
      child: _CategoriesMobileFilterPanel(
        managedCount: ref.read(inventoryCategoriesProvider).items.length,
        visibleCount: _mergedCategories(
          ref.read(inventoryCategoriesProvider).items,
        ).length,
        productCount: _productCounts.values.fold<int>(
          0,
          (sum, value) => sum + value,
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() => _query = '');
    }
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
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.editProducts,
      reason: 'Eliminar categoría',
    );
    if (!allowed || !mounted) return;
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

  void _openCategoryDetail(InventoryCategoryModel category) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CategoryDetailPage(
          category: category,
          productCount: _productCounts[category.name] ?? 0,
          managed: !category.id.startsWith('derived-'),
          onEdit: () => _openEditor(category: category),
          onDelete: () => _deleteCategory(category),
        ),
      ),
    );
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
        final mobile = constraints.maxWidth < 640;
        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView(
            padding: productsResponsivePagePadding(constraints),
            children: [
              if (mobile)
                if (categoryState.error != null)
                  _InlineWarning(message: categoryState.error!)
                else if (rows.isEmpty)
                  const ProductsEmptyState(
                    icon: Icons.category_outlined,
                    title: 'Sin categorías',
                    message: 'Crea tu primera categoría con nombre e imagen.',
                  )
                else
                  for (final category in rows)
                    _CategoryManagementCard(
                      width: double.infinity,
                      category: category,
                      productCount: _productCounts[category.name] ?? 0,
                      managed: !category.id.startsWith('derived-'),
                      onEdit: () => _openEditor(category: category),
                      onDelete: () => _deleteCategory(category),
                      onOpenDetail: () => _openCategoryDetail(category),
                    )
              else
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
                                    managed: !category.id.startsWith(
                                      'derived-',
                                    ),
                                    onEdit: () =>
                                        _openEditor(category: category),
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
    this.onOpenDetail,
  });

  final double width;
  final InventoryCategoryModel category;
  final int productCount;
  final bool managed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodeCategoryImage(category.imageBase64);
    final mobile = MediaQuery.sizeOf(context).width < 640;
    final content = Row(
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
        if (mobile)
          _ProductActionsMenu(onEdit: onEdit, onDelete: onDelete)
        else ...[
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
      ],
    );

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(mobile ? 8 : 14),
        child: InkWell(
          onTap: mobile ? onOpenDetail : null,
          borderRadius: BorderRadius.circular(mobile ? 8 : 14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(mobile ? 8 : 14),
              border: Border.all(color: _borderSoft),
              boxShadow: mobile
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            padding: EdgeInsets.all(mobile ? 10 : 12),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _CategoryDetailPage extends StatelessWidget {
  const _CategoryDetailPage({
    required this.category,
    required this.productCount,
    required this.managed,
    required this.onEdit,
    required this.onDelete,
  });

  final InventoryCategoryModel category;
  final int productCount;
  final bool managed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final imageBytes = _decodeCategoryImage(category.imageBase64);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        title: 'Categoría',
        showLogo: false,
        showDepartmentLabel: false,
        trailing: SizedBox.shrink(),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderSoft),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageBytes == null
                  ? const Icon(
                      Icons.category_outlined,
                      size: 78,
                      color: _primaryBlue,
                    )
                  : Image.memory(imageBytes, fit: BoxFit.contain),
            ),
            const SizedBox(height: 14),
            Text(
              category.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _DetailInfoGrid(
              rows: [
                ('Productos', '$productCount'),
                ('Estado', managed ? 'Administrada' : 'Detectada'),
                ('Creada', _formatShortDate(category.createdAt)),
                ('Actualizada', _formatShortDate(category.updatedAt)),
              ],
            ),
            const SizedBox(height: 18),
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
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Eliminar',
                  onPressed: () {
                    Navigator.of(context).pop();
                    onDelete();
                  },
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatShortDate(DateTime value) {
  if (value.millisecondsSinceEpoch == 0) return 'No registrada';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
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
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 640;
    final cardWidth = mobile ? double.infinity : 214.0;
    return SizedBox(
      width: cardWidth,
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
    this.onTap,
    this.onEdit,
    this.onStock,
    this.onDelete,
  });

  final ProductModel product;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback? onTap;
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

    final mobile = MediaQuery.sizeOf(context).width < 640;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: mobile ? 3 : 5),
      child: Material(
        color: selected ? _lightBlueHover : Colors.white,
        borderRadius: BorderRadius.circular(mobile ? 8 : 12),
        child: InkWell(
          onTap: mobile ? onTap : null,
          borderRadius: BorderRadius.circular(mobile ? 8 : 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(mobile ? 8 : 12),
              border: Border.all(color: selected ? _primaryBlue : _borderSoft),
            ),
            padding: EdgeInsets.all(mobile ? 7 : 0),
            child: mobile
                ? Row(
                    children: [
                      Container(width: 3, height: 66, color: statusColor),
                      Transform.scale(
                        scale: 0.86,
                        child: Checkbox(
                          value: selected,
                          onChanged: (v) => onSelected(v ?? false),
                        ),
                      ),
                      ProductThumbnail(product: product, size: 46, radius: 8),
                      const SizedBox(width: 9),
                      Expanded(child: _CompactProductInfo(product: product)),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _CompactMiniValue(
                            label: 'Stock',
                            value: _stockText(product.stock),
                            color: statusColor,
                          ),
                          const SizedBox(height: 3),
                          _CompactMiniValue(
                            label: 'Valor',
                            value: formatRdCurrencyAccounting(
                              _stockOf(product) * product.precio,
                            ),
                          ),
                        ],
                      ),
                      _ProductActionsMenu(
                        onEdit: onEdit,
                        onStock: onStock,
                        onDelete: onDelete,
                      ),
                    ],
                  )
                : IntrinsicHeight(
                    child: Row(
                      children: [
                        Container(width: 3, color: statusColor),
                        Checkbox(
                          value: selected,
                          onChanged: (v) => onSelected(v ?? false),
                        ),
                        ProductThumbnail(product: product, size: 42),
                        const SizedBox(width: 10),
                        Expanded(child: _CompactProductInfo(product: product)),
                        _CompactMetric(
                          label: 'Stock',
                          value: _stockText(product.stock),
                        ),
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
                          TextButton(
                            onPressed: onStock,
                            child: const Text('Stock'),
                          ),
                        if (onDelete != null)
                          IconButton(
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ProductActionsMenu extends StatelessWidget {
  const _ProductActionsMenu({this.onEdit, this.onStock, this.onDelete});

  final VoidCallback? onEdit;
  final VoidCallback? onStock;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Acciones',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
            break;
          case 'stock':
            onStock?.call();
            break;
          case 'delete':
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit_outlined),
              title: Text('Editar'),
            ),
          ),
        if (onStock != null)
          const PopupMenuItem(
            value: 'stock',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.tune_outlined),
              title: Text('Ajustar stock'),
            ),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline_rounded),
              title: Text('Eliminar'),
            ),
          ),
      ],
    );
  }
}

class _CompactMiniValue extends StatelessWidget {
  const _CompactMiniValue({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 74),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: _textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 9.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactProductInfo extends StatelessWidget {
  const _CompactProductInfo({required this.product});

  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return Column(
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
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        Text(
          product.categoriaLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _ProductDetailPage extends StatelessWidget {
  const _ProductDetailPage({
    required this.product,
    this.onEdit,
    this.onStock,
    this.onDelete,
  });

  final ProductModel product;
  final VoidCallback? onEdit;
  final VoidCallback? onStock;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final level = _resolveStockLevel(product);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomAppBar(
        title: 'Detalle',
        showLogo: false,
        showDepartmentLabel: false,
        trailing: SizedBox.shrink(),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Container(
              height: 230,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _borderSoft),
              ),
              clipBehavior: Clip.antiAlias,
              child: ProductNetworkImage(
                imageUrl: normalizeProductImageUrl(
                  imageUrl: product.displayFotoUrl,
                ),
                productId: product.id,
                productName: product.nombre,
                originalUrl: product.displayFotoUrl,
                fit: BoxFit.contain,
                fallback: const Icon(
                  Icons.inventory_2_outlined,
                  size: 72,
                  color: _primaryBlue,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              product.nombre,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              product.categoriaLabel,
              style: const TextStyle(
                color: _textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _DetailInfoGrid(
              rows: [
                (
                  'Código',
                  product.codigo?.trim().isNotEmpty == true
                      ? product.codigo!.trim()
                      : 'Sin SKU',
                ),
                ('Stock', _stockText(product.stock)),
                ('Estado', _stockLevelLabel(level)),
                ('Costo', formatRdCurrencyAccounting(product.costo)),
                ('Precio', formatRdCurrencyAccounting(product.precio)),
                (
                  'Valor inventario',
                  formatRdCurrencyAccounting(
                    _stockOf(product) * product.precio,
                  ),
                ),
                (
                  'Ganancia unidad',
                  formatRdCurrencyAccounting(_profitOf(product)),
                ),
                ('Margen', '${_marginOf(product).toStringAsFixed(1)}%'),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (onEdit != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onEdit?.call();
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar'),
                    ),
                  ),
                if (onStock != null) ...[
                  if (onEdit != null) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onStock?.call();
                      },
                      icon: const Icon(Icons.tune_outlined),
                      label: const Text('Stock'),
                    ),
                  ),
                ],
                if (onDelete != null) ...[
                  const SizedBox(width: 10),
                  IconButton.outlined(
                    tooltip: 'Eliminar',
                    onPressed: () {
                      Navigator.of(context).pop();
                      onDelete?.call();
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppColors.error,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailInfoGrid extends StatelessWidget {
  const _DetailInfoGrid({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final row in rows)
          Container(
            width: (MediaQuery.sizeOf(context).width - 32) / 2,
            padding: mobile
                ? const EdgeInsets.symmetric(horizontal: 2, vertical: 8)
                : const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: mobile ? Colors.transparent : Colors.white,
              borderRadius: BorderRadius.circular(mobile ? 0 : 10),
              border: mobile ? null : Border.all(color: _borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.$1,
                  style: const TextStyle(
                    color: _textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  row.$2,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ProductThumbnail extends StatelessWidget {
  const ProductThumbnail({
    super.key,
    required this.product,
    this.size = 44,
    this.radius = 10,
  });

  final ProductModel product;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.displayFotoUrl;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
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
            builder: (dialogContext, setPanelState) => CallbackShortcuts(
              bindings: {
                if (!saving)
                  const SingleActivator(LogicalKeyboardKey.enter): () =>
                      submit(dialogContext, setPanelState),
                if (!saving)
                  const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
                      submit(dialogContext, setPanelState),
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(dialogContext).maybePop(),
              },
              child: Focus(
                autofocus: true,
                child: Material(
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
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
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _InlineInfo(
                            icon: Icons.inventory_2_outlined,
                            message:
                                'Stock actual: ${_stockText(product.stock)} · Valor: ${formatRdCurrencyAccounting(_stockOf(product) * product.precio)}',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SegmentedButton<String>(
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
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setPanelState(() {}),
                          decoration: _inventoryTextInputDecoration('Cantidad'),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _InlineInfo(
                            icon: Icons.preview_outlined,
                            message: 'Nuevo stock: ${_stockText(preview())}',
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                              label: const Text('Guardar ajuste'),
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
      );
    },
  ).whenComplete(qtyCtrl.dispose);
}

class ProductFormResult {
  const ProductFormResult({required this.saved});

  final bool saved;
}

InputDecoration _inventoryTextInputDecoration(
  String label, {
  String? hintText,
  Widget? prefixIcon,
}) {
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: Color(0xFFD3E0E7)),
  );
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    prefixIcon: prefixIcon,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.3),
    ),
  );
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
                            border: Border.all(color: _borderSoft),
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
          _InventorySidePanelBackdrop(
            onTap: () => Navigator.of(dialogContext).maybePop(),
          ),
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
          _InventorySidePanelBackdrop(
            onTap: () => Navigator.of(dialogContext).maybePop(),
          ),
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
                  canAddStock: true,
                  onClose: () => Navigator.of(dialogContext).pop(),
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
  const _InventorySidePanelBackdrop({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2.4, sigmaY: 2.4),
          child: ColoredBox(color: Colors.white.withValues(alpha: 0.05)),
        ),
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
  late final TextEditingController _codeCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _stockCtrl;
  late final TextEditingController _categoryCtrl;
  late final FocusNode _nameFocus;
  late final FocusNode _codeFocus;
  late final FocusNode _priceFocus;
  late final FocusNode _costFocus;
  late final FocusNode _stockFocus;
  late final FocusNode _categoryFocus;

  Uint8List? _imageBytes;
  String? _imageName;
  Future<String?>? _imageUploadFuture;
  String? _uploadedImagePath;
  int _imageUploadToken = 0;
  bool _isSaving = false;
  bool _isPickingImage = false;
  String? _formError;

  ProductModel? get _product => widget.product;

  String _newSaveOperationId(ProductModel? product) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final action = product == null ? 'create' : 'update-${product.id}';
    return 'inventory-$action-$now-$hashCode';
  }

  @override
  void initState() {
    super.initState();
    debugPrint('[ProductForm#$hashCode] initState');
    final product = widget.product;
    _nameCtrl = TextEditingController(text: product?.nombre ?? '');
    _codeCtrl = TextEditingController(text: product?.codigo ?? '');
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
    _codeFocus = FocusNode();
    _priceFocus = FocusNode();
    _costFocus = FocusNode();
    _stockFocus = FocusNode();
    _categoryFocus = FocusNode();
  }

  @override
  void dispose() {
    debugPrint('[ProductForm#$hashCode] dispose');
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _priceCtrl.dispose();
    _costCtrl.dispose();
    _stockCtrl.dispose();
    _categoryCtrl.dispose();
    _nameFocus.dispose();
    _codeFocus.dispose();
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
        _uploadedImagePath = null;
      });
      _startSelectedImageUpload(bytes: bytes, filename: file.name);
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

  void _startSelectedImageUpload({
    required Uint8List bytes,
    required String filename,
  }) {
    final token = ++_imageUploadToken;
    final repo = ref.read(catalogRepositoryProvider);
    final upload = _uploadSelectedImageWithRetry(
      repo: repo,
      bytes: bytes,
      filename: filename,
    );
    _imageUploadFuture = upload;
    unawaited(
      upload.then((path) {
        if (!mounted || token != _imageUploadToken || path == null) return;
        setState(() => _uploadedImagePath = path);
      }),
    );
  }

  Future<String?> _uploadSelectedImageWithRetry({
    required CatalogRepository repo,
    required Uint8List bytes,
    required String filename,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final path = await repo.uploadImage(bytes: bytes, filename: filename);
        final cachedUrl = buildProductImageUrl(
          imageUrl: path,
          baseUrl: Env.apiBaseUrl,
        );
        unawaited(
          FulltechImageCacheManager.putImageBytes(
            url: cachedUrl,
            bytes: bytes,
            filename: filename,
          ),
        );
        return path;
      } catch (e) {
        debugPrint(
          '[ProductForm#$hashCode] image upload attempt ${attempt + 1} failed: $e',
        );
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 450 * (attempt + 1)),
          );
        }
      }
    }
    return null;
  }

  void _attachImageAfterUpload({
    required CatalogRepository repo,
    required ProductModel saved,
    required Future<String?> upload,
    required String name,
    required String code,
    required double price,
    required double cost,
    required double stock,
    required String category,
  }) {
    unawaited(
      upload.then((path) async {
        final normalizedPath = (path ?? '').trim();
        if (normalizedPath.isEmpty) return;
        try {
          await repo.updateProduct(
            id: saved.id,
            nombre: name,
            codigo: code.isEmpty ? null : code,
            precio: price,
            costo: cost,
            stock: stock,
            categoria: category,
            fotoUrl: normalizedPath,
            operationId: _newSaveOperationId(saved),
            skipLoader: true,
          );
        } catch (e) {
          debugPrint(
            '[ProductForm#$hashCode] silent background image attach failed: $e',
          );
        }
      }),
    );
  }

  Future<void> _save() async {
    if (_isSaving) return;
    debugPrint('[ProductForm#$hashCode] save start mounted=$mounted');
    FocusManager.instance.primaryFocus?.unfocus();

    final name = _nameCtrl.text.trim();
    final code = _codeCtrl.text.trim();
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

    final product = _product;
    final operationId = _newSaveOperationId(product);
    try {
      final repo = ref.read(catalogRepositoryProvider);
      final readyImagePath = _uploadedImagePath;
      final pendingImageUpload = _imageUploadFuture;
      ProductModel saved;

      if (product == null) {
        saved = await repo.createProduct(
          nombre: name,
          codigo: code.isEmpty ? null : code,
          precio: price,
          costo: cost,
          stock: stock,
          categoria: category,
          fotoUrl: readyImagePath,
          operationId: operationId,
          skipLoader: true,
        );
      } else {
        saved = await repo.updateProduct(
          id: product.id,
          nombre: name,
          codigo: code.isEmpty ? null : code,
          precio: price,
          costo: cost,
          stock: stock,
          categoria: category,
          fotoUrl: readyImagePath,
          operationId: operationId,
          skipLoader: true,
        );
      }

      if ((readyImagePath ?? '').trim().isEmpty && pendingImageUpload != null) {
        _attachImageAfterUpload(
          repo: repo,
          saved: saved,
          upload: pendingImageUpload,
          name: name,
          code: code,
          price: price,
          cost: cost,
          stock: stock,
          category: category,
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

  void _advanceFormOrSave() {
    if (_isSaving || _isPickingImage) return;
    if (_nameFocus.hasFocus) {
      _codeFocus.requestFocus();
      return;
    }
    if (_codeFocus.hasFocus) {
      _priceFocus.requestFocus();
      return;
    }
    if (_priceFocus.hasFocus) {
      _costFocus.requestFocus();
      return;
    }
    if (_costFocus.hasFocus) {
      _stockFocus.requestFocus();
      return;
    }
    if (_stockFocus.hasFocus) {
      _categoryFocus.requestFocus();
      return;
    }
    if (_categoryFocus.hasFocus) {
      _save();
      return;
    }
    _nameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final existingImageUrl = product?.displayFotoUrl?.trim() ?? '';

    return _InventorySidePanelScaffold(
      title: product == null ? 'Nuevo producto' : 'Editar producto',
      icon: product == null ? Icons.add_box_outlined : Icons.edit_outlined,
      onClose: _isSaving ? null : _close,
      onSubmit: _isSaving || _isPickingImage ? null : _advanceFormOrSave,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_formError != null) ...[
              _FormErrorBanner(message: _formError!),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              enabled: !_isSaving,
              textInputAction: TextInputAction.next,
              decoration: _inventoryTextInputDecoration('Nombre del producto'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _codeCtrl,
              focusNode: _codeFocus,
              enabled: !_isSaving,
              textInputAction: TextInputAction.next,
              decoration: _inventoryTextInputDecoration(
                'Código / código de barra (opcional)',
                hintText: 'Escanea o escribe el código del producto',
                prefixIcon: Icon(Icons.qr_code_2_outlined),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _priceCtrl,
                    focusNode: _priceFocus,
                    enabled: !_isSaving,
                    textInputAction: TextInputAction.next,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inventoryTextInputDecoration('Precio'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    focusNode: _costFocus,
                    enabled: !_isSaving,
                    textInputAction: TextInputAction.next,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _inventoryTextInputDecoration('Costo'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _stockCtrl,
              focusNode: _stockFocus,
              enabled: !_isSaving,
              textInputAction: TextInputAction.next,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: _inventoryTextInputDecoration('Stock disponible'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _categoryCtrl,
              focusNode: _categoryFocus,
              enabled: !_isSaving,
              textInputAction: TextInputAction.done,
              decoration: _inventoryTextInputDecoration('Categoría'),
            ),
            if (widget.categories.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final category in widget.categories)
                    _InventoryCategoryChoiceChip(
                      label: category,
                      selected: _categoryCtrl.text.trim() == category,
                      onTap: _isSaving
                          ? null
                          : () => setState(() {
                              _categoryCtrl.text = category;
                            }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
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
              style: OutlinedButton.styleFrom(
                shape: const RoundedRectangleBorder(),
                minimumSize: const Size.fromHeight(36),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _lightBlueHover,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: _borderSoft),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageBytes != null
                    ? Image.memory(
                        _imageBytes!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
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

class _InventoryCategoryChoiceChip extends StatelessWidget {
  const _InventoryCategoryChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : AppColors.textPrimary;
    return Material(
      color: selected ? const Color(0xFF0F6170) : Colors.white,
      shape: const RoundedRectangleBorder(side: BorderSide(color: _borderSoft)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
