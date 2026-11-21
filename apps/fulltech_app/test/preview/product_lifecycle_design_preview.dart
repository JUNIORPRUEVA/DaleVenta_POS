// Design gallery only. All data are fictional and every network request fails.
// Never imported by a production entry point.
import 'dart:typed_data';
import 'dart:async';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/catalogo/data/product_lifecycle_snapshot.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:daleventa_pos/features/products/ui/product_lifecycle_dialog.dart';
import 'package:daleventa_pos/features/products/ui/product_lifecycle_feedback.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const designCases = <(String, String)>[
  ('catalog', 'Catálogo activo'),
  ('create', 'Crear producto'),
  ('edit', 'Editar producto'),
  ('stock', 'Ajustar existencias'),
  ('zero', 'Sin existencias ni historial'),
  ('initial', 'Carga inicial que puede anularse'),
  ('history', 'Con historial protegido'),
  ('legacy', 'Existencias antiguas sin Kardex'),
  ('inconsistent', 'Existencias por revisar'),
  ('archived', 'Producto archivado'),
  ('annulled', 'Alta anulada'),
  ('identity', 'Producto encontrado en Archivados'),
  ('nonadmin', 'Usuario sin permiso para anular'),
  ('disabled', 'Anulación deshabilitada'),
  ('loading', 'Comprobando producto'),
  ('offline', 'Servidor no accesible'),
  ('forbidden', 'Acceso rechazado'),
  ('missing', 'Producto no encontrado'),
  ('version', 'Cambio simultáneo al confirmar'),
  ('plan', 'Restauración sin cupo en el plan'),
  ('pending', 'Operaciones locales pendientes'),
  ('uncertain', 'Respuesta incierta'),
  ('archives', 'Lista de archivados'),
  ('empty', 'Sin archivados'),
  ('pages', 'Archivados con más páginas'),
  ('archives-loading', 'Cargando archivados'),
  ('archives-error', 'Error al cargar archivados'),
  ('confirm-archive', 'Confirmar archivo'),
  ('confirm-restore', 'Confirmar restauración'),
  ('confirm-delete', 'Confirmar eliminación'),
  ('confirm-annul', 'Confirmar anulación'),
  ('bulk-archive', 'Confirmar archivo múltiple'),
  ('bulk-delete', 'Confirmar eliminación múltiple'),
  ('results', 'Resultado por producto'),
  ('notice-archive', 'Aviso de producto archivado'),
  ('notice-restore', 'Aviso de producto restaurado'),
  ('notice-delete', 'Aviso de producto eliminado'),
  ('notice-annul', 'Aviso de alta anulada'),
  ('notice-refresh', 'Cambio guardado y actualización pendiente'),
];

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) => Future.error(StateError('Preview blocks HTTP'));
  @override
  void close({bool force = false}) {}
}

class DesignCatalogRepository extends CatalogRepository {
  DesignCatalogRepository(this.scenario)
    : super(Dio()..httpClientAdapter = _NoNetwork());
  final String scenario;
  ProductModel get product => ProductModel(
    id: 'design-product',
    nombre: 'Auriculares profesionales',
    codigo: 'AUD-001',
    precio: 1250,
    costo: 750,
    stock: scenario == 'zero' ? 0 : 7,
    categoria: 'Accesorios',
  );
  @override
  Future<ProductLifecycleSnapshot> productLifecycle(String id) async {
    if (scenario == 'loading') await Completer<void>().future;
    final failure = switch (scenario) {
      'offline' => 'Se necesita conexión para comprobar el producto.',
      'forbidden' => 'No tienes permiso para esta acción.',
      'missing' => 'Producto no encontrado',
      _ => null,
    };
    if (failure != null) throw ApiException(failure);
    final archived = [
      'archived',
      'identity',
      'plan',
      'archives',
      'pages',
    ].contains(scenario);
    final annulled = scenario == 'annulled';
    return ProductLifecycleSnapshot({
      'productId': id,
      'status': annulled
          ? 'ANNULLED'
          : archived
          ? 'ARCHIVED'
          : 'ACTIVE',
      'lifecycleVersion': 3,
      'stock': scenario == 'zero' || annulled ? 0 : 7,
      'canDelete': scenario == 'zero',
      'canArchive': !archived && !annulled,
      'canRestore': archived,
      'canAnnul': scenario == 'initial',
      'reason': switch (scenario) {
        'zero' =>
          'Sin existencias ni historial. Puedes eliminarlo definitivamente.',
        'initial' =>
          'Solo conserva la carga inicial. Puede anularse con confirmación.',
        'inconsistent' => 'Las existencias necesitan revisión.',
        'annulled' => 'El alta ya está anulada.',
        'identity' =>
          'Este producto ya existe en Archivados. Puedes restaurarlo.',
        _ =>
          archived
              ? 'Conserva sus existencias e historial. Puedes restaurarlo.'
              : 'Conserva las existencias y el historial. Puedes archivar el producto.',
      },
    });
  }

  void _mutate() {
    final error = switch (scenario) {
      'version' => 'El producto cambió. Comprueba sus datos antes de anularlo.',
      'plan' => 'Tu plan alcanzó el límite de productos activos.',
      'pending' =>
        'Este producto tiene operaciones locales pendientes. Resuélvelas antes de cambiar su estado.',
      'uncertain' => 'No se pudo confirmar el cambio. Comprueba el estado.',
      _ => null,
    };
    if (error != null) throw ApiException(error, 409);
  }

  @override
  Future<void> deleteProduct(String id, {bool skipLoader = false}) async {
    _mutate();
  }

  @override
  Future<ProductModel> archiveProduct(
    String id, {
    bool skipLoader = false,
    String? resolvingActionId,
  }) async {
    _mutate();
    return product;
  }

  @override
  Future<ProductModel> restoreProduct(String id) async {
    _mutate();
    return product;
  }

  @override
  Future<void> annulProduct(
    String id, {
    required String operationId,
    required int expectedVersion,
    required String reason,
  }) async {
    _mutate();
  }

  @override
  Future<List<Map<String, dynamic>>> archivedProducts({
    String search = '',
    int page = 1,
  }) async {
    if (scenario == 'archives-loading') await Completer<void>().future;
    if (scenario == 'archives-error') {
      throw ApiException('No se pudieron cargar los archivados.');
    }
    if (scenario == 'empty') return [];
    final rows = List.generate(
      scenario == 'pages' ? 50 : 3,
      (i) => {
        'id': 'design-$page-$i',
        'nombre': i == 0 ? 'Auriculares profesionales' : 'Producto ${i + 1}',
        'codigo': 'AUD-${i + 1}',
        'annulledAt': i == 2 ? '2026-11-20' : null,
      },
    );
    return rows
        .where(
          (row) =>
              '${row['nombre']}'.toLowerCase().contains(search.toLowerCase()),
        )
        .toList();
  }
}

void main() => runApp(const ProductLifecycleDesignGallery());

class ProductLifecycleDesignGallery extends StatelessWidget {
  const ProductLifecycleDesignGallery({super.key, this.initialCase});
  final String? initialCase;
  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(Dio()..httpClientAdapter = _NoNetwork()),
      catalogRepositoryProvider.overrideWithValue(
        DesignCatalogRepository('initial'),
      ),
      companySettingsProvider.overrideWith(
        (_) async => CompanySettings.empty(),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _Gallery(initialCase: initialCase),
    ),
  );
}

class _Gallery extends StatefulWidget {
  const _Gallery({this.initialCase});
  final String? initialCase;
  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  @override
  void dispose() {
    ProductLifecycleFeedback.dismissNotice();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final id = widget.initialCase ?? Uri.base.queryParameters['case'];
      if (id != null && designCases.any((c) => c.$1 == id)) _open(id);
    });
  }

  Future<void> _open(String id) async {
    if (id.startsWith('notice-')) {
      final action = id.substring(7);
      ProductLifecycleFeedback.notice(
        context,
        action == 'refresh'
            ? 'Cambio guardado. Actualiza el catálogo.'
            : ProductLifecycleFeedback.success(action),
        warning: action == 'refresh',
      );
      return;
    }
    if (id.startsWith('confirm-')) {
      await ProductLifecycleFeedback.confirm(context, id.substring(8));
      return;
    }
    if (id.startsWith('bulk-')) {
      await ProductLifecycleFeedback.confirmBulk(
        context,
        archive: id.endsWith('archive'),
        eligible: 2,
        total: 4,
      );
      return;
    }
    if (id == 'results') {
      await showDialog<void>(
        context: context,
        builder: (_) => const ProductLifecycleResultsDialog(
          results: [
            'Cable USB: Eliminado',
            'Auriculares: Archivado',
            'Adaptador: Conserva existencias. Sin cambios.',
            'Teclado: Tiene operaciones locales pendientes. Sin cambios.',
          ],
        ),
      );
      return;
    }
    final repo = DesignCatalogRepository(id);
    if (id == 'create' || id == 'edit') {
      await showInventoryProductEditor(
        context,
        product: id == 'edit' ? repo.product : null,
        categories: ['Accesorios', 'General'],
      );
      return;
    }
    if (id == 'stock') {
      await showInventoryStockAdjustmentsPanel(
        context,
        products: [repo.product],
        onRefresh: () async {},
        onSetStock: (_, __, {warehouseId, currentWarehouseStock}) async {},
        canAddStock: true,
        inventoryEnabled: true,
        initialProductId: repo.product.id,
      );
      return;
    }
    if (id == 'catalog') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Productos')),
            body: CatalogTab(
              products: [
                repo.product,
                repo.product.copyWith(
                  id: 'empty',
                  nombre: 'Cable USB',
                  stock: 0,
                ),
              ],
              loading: false,
              error: null,
              onRefresh: () async {},
              onCreate: () => _open('create'),
              onImport: () async {},
              onExport: () async {},
              onExportSelection: (_) async {},
              onPdfSelection: (_) async {},
              onBulkDelete: (_) async {
                await _open('bulk-delete');
              },
              onBulkArchive: (_) async {
                await _open('bulk-archive');
              },
              onBulkChangeCategory: (_, __) async {},
              onEdit: (_) => _open('edit'),
              onSetStock:
                  (_, __, {warehouseId, currentWarehouseStock}) async {},
              canEditProducts: true,
              canAddStock: true,
              onDelete: (_) async {
                await _open('initial');
              },
            ),
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => ProviderScope(
        overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
        child:
            [
              'archives',
              'empty',
              'pages',
              'archives-loading',
              'archives-error',
            ].contains(id)
            ? ArchivedProductsDialog(onChanged: () async {})
            : ProductLifecycleDialog(
                productId: repo.product.id,
                name: repo.product.nombre,
                onChanged: () async {},
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Productos · Revisión de diseño')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${designCases.length} vistas · Datos ficticios · Sin conexión al servidor',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            ...designCases.indexed.map(
              (row) => ListTile(
                dense: true,
                leading: Text('${row.$1 + 1}'.padLeft(2, '0')),
                title: Text(row.$2.$2),
                subtitle: Text(row.$2.$1),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(row.$2.$1),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
