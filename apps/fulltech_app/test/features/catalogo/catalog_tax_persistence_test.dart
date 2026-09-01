import 'dart:async';
import 'dart:convert';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/catalogo/application/catalog_controller.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TaxFakeCatalogRepository extends CatalogRepository {
  _TaxFakeCatalogRepository(this.products) : super(Dio());

  List<ProductModel> products;
  String? lastTaxTreatment;
  double? lastTaxRate;
  String? lastTaxPriceMode;
  String? lastFotoUrl;
  bool dropImageOnUpdateResponse = false;
  List<ProductModel> cachedProducts = const [];
  final List<Completer<List<ProductModel>>> fetchCompleters = [];
  int fetchCalls = 0;
  int createCalls = 0;
  Object? fetchError;
  Object? uploadError;
  final List<List<ProductModel>> savedSnapshots = [];
  final List<String> deletedIds = [];

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    if (fetchError != null) {
      final error = fetchError!;
      fetchError = null;
      throw error;
    }
    if (fetchCalls < fetchCompleters.length) {
      return fetchCompleters[fetchCalls++].future;
    }
    return products;
  }

  @override
  Future<List<ProductModel>> getCachedProducts({Duration? maxAge}) async {
    return cachedProducts.isEmpty ? products : cachedProducts;
  }

  @override
  Future<void> saveProductsSnapshot(List<ProductModel> items) async {
    savedSnapshots.add(List<ProductModel>.from(items));
  }

  @override
  Future<ProductModel> createProduct({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    required String categoria,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
    bool skipLoader = false,
  }) async {
    createCalls += 1;
    lastTaxTreatment = taxTreatment;
    lastTaxRate = taxRate;
    lastTaxPriceMode = taxPriceMode;
    final product = ProductModel(
      id: 'created-${products.length + 1}',
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria,
      fotoUrl: fotoUrl,
      taxTreatment: taxTreatment ?? 'INHERIT',
      taxRate: taxRate,
      taxPriceMode: taxPriceMode,
    );
    products = [product, ...products];
    return product;
  }

  @override
  Future<String> uploadImage({
    List<int>? bytes,
    String? filePath,
    required String filename,
  }) async {
    final error = uploadError;
    if (error != null) throw error;
    return '/media/object?key=uploads%2Fcompanies%2Ftest%2Fproducto.png';
  }

  @override
  Future<ProductModel> updateProduct({
    required String id,
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    String? categoria,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
    bool skipLoader = false,
  }) async {
    lastTaxTreatment = taxTreatment;
    lastTaxRate = taxRate;
    lastTaxPriceMode = taxPriceMode;
    lastFotoUrl = fotoUrl;
    final updated = ProductModel(
      id: id,
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria ?? 'General',
      fotoUrl: dropImageOnUpdateResponse ? null : fotoUrl,
      taxTreatment: taxTreatment ?? 'INHERIT',
      taxRate: taxRate,
      taxPriceMode: taxPriceMode,
    );
    products = [
      for (final product in products)
        if (product.id == id) updated else product,
    ];
    return updated;
  }

  @override
  Future<ProductModel> adjustProductStock({
    required String id,
    double? stock,
    double? delta,
    String? warehouseId,
    String? reason,
    bool skipLoader = false,
  }) async {
    final current = products.firstWhere((product) => product.id == id);
    final updated = current.copyWith(
      stock: stock ?? ((current.stock ?? 0) + (delta ?? 0)),
    );
    products = [
      for (final product in products)
        if (product.id == id) updated else product,
    ];
    return updated;
  }

  @override
  Future<void> deleteProduct(String id, {bool skipLoader = false}) async {
    deletedIds.add(id);
    products = [
      for (final product in products)
        if (product.id != id) product,
    ];
  }
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref, String companyId) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'user-1',
        email: 'test@example.com',
        nombreCompleto: 'Test',
        telefono: '000',
        companyId: companyId,
      ),
    );
  }

  void setCompany(String companyId) {
    state = state.copyWith(
      user: UserModel(
        id: 'user-1',
        email: 'test@example.com',
        nombreCompleto: 'Test',
        telefono: '000',
        companyId: companyId,
      ),
    );
  }
}

ProductModel _product({
  String taxTreatment = 'INHERIT',
  double? taxRate,
  String? taxPriceMode,
  double stock = 1,
  String? fotoUrl,
}) {
  return ProductModel(
    id: 'p-1',
    nombre: 'Producto fiscal',
    precio: 100,
    costo: 60,
    stock: stock,
    categoria: 'General',
    fotoUrl: fotoUrl,
    taxTreatment: taxTreatment,
    taxRate: taxRate,
    taxPriceMode: taxPriceMode,
  );
}

ProviderContainer _containerWith(_TaxFakeCatalogRepository repo) {
  final container = ProviderContainer(
    overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProviderChannel, (call) async {
        return 'C:/tmp';
      });

  test('editar producto INHERIT a EXEMPT reenvia fiscalidad', () async {
    final repo = _TaxFakeCatalogRepository([_product()]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    await controller.update(
      id: 'p-1',
      nombre: 'Producto fiscal',
      precio: 100,
      costo: 60,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'EXEMPT',
      taxRate: null,
      taxPriceMode: null,
    );

    expect(repo.lastTaxTreatment, 'EXEMPT');
    expect(repo.lastTaxRate, isNull);
    expect(repo.lastTaxPriceMode, isNull);
    expect(
      container.read(catalogControllerProvider).items.single.taxTreatment,
      'EXEMPT',
    );
  });

  test('editar producto EXEMPT a INHERIT reenvia fiscalidad', () async {
    final repo = _TaxFakeCatalogRepository([_product(taxTreatment: 'EXEMPT')]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    await controller.update(
      id: 'p-1',
      nombre: 'Producto fiscal',
      precio: 100,
      costo: 60,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'INHERIT',
      taxRate: null,
      taxPriceMode: null,
    );

    expect(repo.lastTaxTreatment, 'INHERIT');
    expect(repo.lastTaxRate, isNull);
    expect(repo.lastTaxPriceMode, isNull);
    expect(
      container.read(catalogControllerProvider).items.single.taxTreatment,
      'INHERIT',
    );
  });

  test('editar producto TAXABLE conserva tasa y modo seleccionados', () async {
    final repo = _TaxFakeCatalogRepository([_product()]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    await controller.update(
      id: 'p-1',
      nombre: 'Producto fiscal',
      precio: 100,
      costo: 60,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'TAXABLE',
      taxRate: 0.18,
      taxPriceMode: 'TAX_ADDED',
    );

    final saved = container.read(catalogControllerProvider).items.single;
    expect(repo.lastTaxTreatment, 'TAXABLE');
    expect(repo.lastTaxRate, 0.18);
    expect(repo.lastTaxPriceMode, 'TAX_ADDED');
    expect(saved.taxTreatment, 'TAXABLE');
    expect(saved.taxRate, 0.18);
    expect(saved.taxPriceMode, 'TAX_ADDED');
  });

  test('adjustStock conserva fiscalidad existente del producto', () async {
    final repo = _TaxFakeCatalogRepository([
      _product(taxTreatment: 'EXEMPT', stock: 2),
    ]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    await controller.adjustStock(product: repo.products.single, stock: 7);

    final saved = container.read(catalogControllerProvider).items.single;
    expect(repo.lastTaxTreatment, isNull);
    expect(repo.lastTaxRate, isNull);
    expect(repo.lastTaxPriceMode, isNull);
    expect(saved.stock, 7);
    expect(saved.taxTreatment, 'EXEMPT');
  });

  test(
    'controller conserva imagen si update fiscal responde sin foto',
    () async {
      final repo = _TaxFakeCatalogRepository([])
        ..dropImageOnUpdateResponse = true;
      final container = _containerWith(repo);
      final controller = container.read(catalogControllerProvider.notifier);

      final updated = await controller.update(
        id: 'p-1',
        nombre: 'Producto fiscal',
        precio: 100,
        costo: 60,
        stock: 1,
        categoria: 'General',
        fotoUrl: '/uploads/existing.png',
        taxTreatment: 'EXEMPT',
        taxRate: null,
        taxPriceMode: null,
      );

      expect(repo.lastTaxTreatment, 'EXEMPT');
      expect(repo.lastFotoUrl, '/uploads/existing.png');
      expect(updated?.displayFotoUrl, isNotNull);
    },
  );

  test(
    'update EXEMPT no puede ser sobrescrito por fetch anterior INHERIT',
    () async {
      final staleFetch = Completer<List<ProductModel>>();
      final freshFetch = Completer<List<ProductModel>>();
      final repo =
          _TaxFakeCatalogRepository([_product(taxTreatment: 'INHERIT')])
            ..cachedProducts = [_product(taxTreatment: 'INHERIT')]
            ..fetchCompleters.addAll([staleFetch, freshFetch]);
      final container = _containerWith(repo);
      final controller = container.read(catalogControllerProvider.notifier);

      final firstLoad = controller.load(forceRemote: true, silent: true);
      await Future<void>.delayed(Duration.zero);

      final updateFuture = controller.update(
        id: 'p-1',
        nombre: 'Producto fiscal',
        precio: 100,
        costo: 60,
        stock: 1,
        categoria: 'General',
        taxTreatment: 'EXEMPT',
        taxRate: null,
        taxPriceMode: null,
      );
      await Future<void>.delayed(Duration.zero);

      staleFetch.complete([_product(taxTreatment: 'INHERIT')]);
      freshFetch.complete([_product(taxTreatment: 'EXEMPT')]);

      await firstLoad;
      await updateFuture;

      expect(
        container.read(catalogControllerProvider).items.single.taxTreatment,
        'EXEMPT',
      );
    },
  );

  test(
    'GET viejo posterior a update no revierte EXEMPT ni borra foto',
    () async {
      final backgroundRefresh = Completer<List<ProductModel>>();
      final laterStaleRefresh = Completer<List<ProductModel>>();
      final repo = _TaxFakeCatalogRepository([
        _product(taxTreatment: 'INHERIT', fotoUrl: '/uploads/old.png'),
      ]);
      final container = _containerWith(repo);
      final controller = container.read(catalogControllerProvider.notifier);

      await controller.load(forceRemote: true, silent: true);
      expect(
        container.read(catalogControllerProvider).items.single.fotoUrl,
        '/uploads/old.png',
      );

      repo.fetchCompleters.add(backgroundRefresh);
      final updated = await controller.update(
        id: 'p-1',
        nombre: 'Producto fiscal',
        precio: 100,
        costo: 60,
        stock: 1,
        categoria: 'General',
        fotoUrl: '/uploads/new.png',
        taxTreatment: 'EXEMPT',
        taxRate: null,
        taxPriceMode: null,
      );
      await Future<void>.delayed(Duration.zero);

      backgroundRefresh.complete([
        _product(taxTreatment: 'INHERIT', fotoUrl: '/uploads/old.png'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(updated?.taxTreatment, 'EXEMPT');
      expect(
        container.read(catalogControllerProvider).items.single.taxTreatment,
        'EXEMPT',
      );
      expect(
        container.read(catalogControllerProvider).items.single.fotoUrl,
        '/uploads/new.png',
      );

      repo.fetchCompleters.add(laterStaleRefresh);
      final laterLoad = controller.load(forceRemote: true, silent: true);
      await Future<void>.delayed(Duration.zero);
      laterStaleRefresh.complete([
        _product(taxTreatment: 'INHERIT', fotoUrl: '/uploads/old.png'),
      ]);
      await laterLoad;

      final product = container.read(catalogControllerProvider).items.single;
      expect(product.taxTreatment, 'EXEMPT');
      expect(product.fotoUrl, '/uploads/new.png');
    },
  );

  test('create no puede desaparecer por GET viejo tardio', () async {
    final staleFetch = Completer<List<ProductModel>>();
    final repo =
        _TaxFakeCatalogRepository([
            ProductModel(
              id: 'a',
              nombre: 'A',
              precio: 10,
              costo: 6,
              stock: 1,
              categoria: 'General',
            ),
            ProductModel(
              id: 'b',
              nombre: 'B',
              precio: 20,
              costo: 12,
              stock: 1,
              categoria: 'General',
            ),
          ])
          ..cachedProducts = List<ProductModel>.from([
            ProductModel(
              id: 'a',
              nombre: 'A',
              precio: 10,
              costo: 6,
              stock: 1,
              categoria: 'General',
            ),
            ProductModel(
              id: 'b',
              nombre: 'B',
              precio: 20,
              costo: 12,
              stock: 1,
              categoria: 'General',
            ),
          ])
          ..fetchCompleters.add(staleFetch);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    final firstLoad = controller.load(forceRemote: true, silent: true);
    await Future<void>.delayed(Duration.zero);

    final createFuture = controller.create(
      nombre: 'C',
      precio: 30,
      costo: 18,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'EXEMPT',
      taxRate: null,
      taxPriceMode: null,
    );
    await Future<void>.delayed(Duration.zero);

    staleFetch.complete(List<ProductModel>.from(repo.cachedProducts));

    await firstLoad;
    await createFuture;

    final items = container.read(catalogControllerProvider).items;
    expect(items.any((item) => item.nombre == 'C'), isTrue);
    expect(
      items.firstWhere((item) => item.nombre == 'C').taxTreatment,
      'EXEMPT',
    );
  });

  test('cache antigua INHERIT pierde contra remoto EXEMPT', () async {
    final remoteFetch = Completer<List<ProductModel>>();
    final repo = _TaxFakeCatalogRepository([])
      ..cachedProducts = [_product(taxTreatment: 'INHERIT')]
      ..fetchCompleters.add(remoteFetch);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    final loadFuture = controller.load(forceRemote: true, silent: true);
    remoteFetch.complete([_product(taxTreatment: 'EXEMPT')]);
    await loadFuture;

    expect(
      container.read(catalogControllerProvider).items.single.taxTreatment,
      'EXEMPT',
    );
  });

  test('dos GET concurrentes: el mas nuevo gana', () async {
    final older = Completer<List<ProductModel>>();
    final newer = Completer<List<ProductModel>>();
    final repo = _TaxFakeCatalogRepository([_product(taxTreatment: 'INHERIT')])
      ..fetchCompleters.addAll([older, newer]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    final get1 = controller.load(forceRemote: true, silent: true);
    await Future<void>.delayed(Duration.zero);
    final get2 = controller.load(forceRemote: true, silent: true);
    await Future<void>.delayed(Duration.zero);

    newer.complete([_product(taxTreatment: 'EXEMPT')]);
    await get2;
    older.complete([_product(taxTreatment: 'INHERIT')]);
    await get1;

    expect(
      container.read(catalogControllerProvider).items.single.taxTreatment,
      'EXEMPT',
    );
  });

  test('update precio confirmado no es revertido por GET viejo', () async {
    final staleFetch = Completer<List<ProductModel>>();
    final repo = _TaxFakeCatalogRepository([_product(taxTreatment: 'INHERIT')])
      ..fetchCompleters.add(staleFetch);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    final firstLoad = controller.load(forceRemote: true, silent: true);
    await Future<void>.delayed(Duration.zero);

    final updateFuture = controller.update(
      id: 'p-1',
      nombre: 'Producto fiscal',
      precio: 2600,
      costo: 60,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'INHERIT',
      taxRate: null,
      taxPriceMode: null,
    );
    await Future<void>.delayed(Duration.zero);

    staleFetch.complete([
      ProductModel(
        id: 'p-1',
        nombre: 'Producto fiscal',
        precio: 2500,
        costo: 60,
        stock: 1,
        categoria: 'General',
        taxTreatment: 'INHERIT',
      ),
    ]);

    await firstLoad;
    await updateFuture;

    expect(container.read(catalogControllerProvider).items.single.precio, 2600);
  });

  test('create con fotoUrl persiste ante GET viejo sin producto', () async {
    final staleFetch = Completer<List<ProductModel>>();
    final repo = _TaxFakeCatalogRepository(const [])
      ..cachedProducts = const []
      ..fetchCompleters.add(staleFetch);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    final firstLoad = controller.load(forceRemote: true, silent: true);
    await Future<void>.delayed(Duration.zero);

    final createFuture = controller.create(
      nombre: 'Con foto',
      precio: 99,
      costo: 50,
      stock: 1,
      categoria: 'General',
      fotoUrl: '/uploads/foto.png',
      taxTreatment: 'EXEMPT',
    );
    await Future<void>.delayed(Duration.zero);

    staleFetch.complete(const []);
    await firstLoad;
    final created = await createFuture;

    final item = container.read(catalogControllerProvider).items.single;
    expect(item.id, created?.id);
    expect(item.fotoUrl, '/uploads/foto.png');
  });

  test('refresh silencioso posterior con EXEMPT mantiene EXEMPT', () async {
    final repo = _TaxFakeCatalogRepository([_product(taxTreatment: 'EXEMPT')]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    await controller.load(forceRemote: true, silent: true);
    await controller.load(forceRemote: true, silent: true);

    expect(
      container.read(catalogControllerProvider).items.single.taxTreatment,
      'EXEMPT',
    );
  });

  test('refresh fallido conserva catalogo visible', () async {
    final repo = _TaxFakeCatalogRepository([_product(taxTreatment: 'EXEMPT')]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    await controller.load(forceRemote: true, silent: true);
    repo.fetchError = ApiException('fallo remoto');

    await controller.load(forceRemote: true, silent: false);

    final state = container.read(catalogControllerProvider);
    expect(state.items, isNotEmpty);
    expect(state.items.single.taxTreatment, 'EXEMPT');
  });

  test('company A request tardio no modifica company B', () async {
    final oldFetch = Completer<List<ProductModel>>();
    final repo = _TaxFakeCatalogRepository([_product()])
      ..fetchCompleters.add(oldFetch);
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(repo),
        authStateProvider.overrideWith(
          (ref) => _FakeAuthController(ref, 'company-a'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(catalogControllerProvider.notifier);
    final auth =
        container.read(authStateProvider.notifier) as _FakeAuthController;

    final loadFuture = controller.load(forceRemote: true, silent: true);
    auth.setCompany('company-b');
    oldFetch.complete([_product(taxTreatment: 'EXEMPT')]);
    await loadFuture;

    expect(container.read(catalogControllerProvider).items, isEmpty);
  });

  test('delete explicito confirmado si elimina producto', () async {
    final repo = _TaxFakeCatalogRepository([_product(taxTreatment: 'EXEMPT')]);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);
    await controller.load();

    await controller.remove('p-1');
    await Future<void>.delayed(Duration.zero);

    final state = container.read(catalogControllerProvider);
    expect(repo.deletedIds, contains('p-1'));
    expect(state.items.where((item) => item.id == 'p-1'), isEmpty);
  });

  test('snapshot escrito tras carrera contiene estado nuevo', () async {
    final staleFetch = Completer<List<ProductModel>>();
    final repo = _TaxFakeCatalogRepository([_product(taxTreatment: 'INHERIT')])
      ..cachedProducts = [_product(taxTreatment: 'INHERIT')]
      ..fetchCompleters.add(staleFetch);
    final container = _containerWith(repo);
    final controller = container.read(catalogControllerProvider.notifier);

    final firstLoad = controller.load(forceRemote: true, silent: true);
    await Future<void>.delayed(Duration.zero);

    final updateFuture = controller.update(
      id: 'p-1',
      nombre: 'Producto fiscal',
      precio: 100,
      costo: 60,
      stock: 1,
      categoria: 'General',
      taxTreatment: 'EXEMPT',
    );
    await Future<void>.delayed(Duration.zero);

    staleFetch.complete([_product(taxTreatment: 'INHERIT')]);
    await firstLoad;
    await updateFuture;

    expect(repo.savedSnapshots, isNotEmpty);
    expect(repo.savedSnapshots.last.single.taxTreatment, 'EXEMPT');
  });

  test(
    'repository envia payload fiscal y conserva respuesta del backend',
    () async {
      Map<String, dynamic>? requestPayload;
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          requestPayload = (options.data as Map).cast<String, dynamic>();
          return ResponseBody.fromString(
            jsonEncode({
              'id': 'p-1',
              'nombre': 'Producto fiscal',
              'precio': 100,
              'costo': 60,
              'stock': 1,
              'categoria': 'General',
              'taxTreatment': 'EXEMPT',
              'taxRate': null,
              'taxPriceMode': null,
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
      final repository = CatalogRepository(dio);

      final product = await repository.updateProduct(
        id: 'p-1',
        nombre: 'Producto fiscal',
        precio: 100,
        costo: 60,
        stock: 1,
        categoria: 'General',
        taxTreatment: 'EXEMPT',
        taxRate: null,
        taxPriceMode: null,
      );

      expect(requestPayload, containsPair('taxTreatment', 'EXEMPT'));
      expect(requestPayload, containsPair('taxRate', null));
      expect(requestPayload, containsPair('taxPriceMode', null));
      expect(requestPayload, isNot(contains('stock')));
      expect(product.taxTreatment, 'EXEMPT');
      expect(product.taxRate, isNull);
      expect(product.taxPriceMode, isNull);
    },
  );

  test('repository envia ajuste de stock solo por endpoint dedicado', () async {
    Map<String, dynamic>? requestPayload;
    String? requestPath;
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        requestPath = options.path;
        requestPayload = (options.data as Map).cast<String, dynamic>();
        return ResponseBody.fromString(
          jsonEncode({
            'id': 'p-1',
            'nombre': 'Producto fiscal',
            'precio': 100,
            'costo': 60,
            'stock': 14.5,
            'categoria': 'General',
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CatalogRepository(dio);

    final product = await repository.adjustProductStock(
      id: 'p-1',
      stock: 14.5,
      reason: 'Inventario fisico',
    );

    expect(requestPath, '/products/p-1/stock');
    expect(requestPayload, containsPair('stock', 14.5));
    expect(requestPayload, containsPair('reason', 'Inventario fisico'));
    expect(product.stock, 14.5);
  });

  test(
    'repository convierte PRODUCT_HAS_HISTORY en accion de archivar',
    () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
          expect(options.method, 'DELETE');
          expect(options.path, '/products/p-1');
          return ResponseBody.fromString(
            jsonEncode({
              'code': 'PRODUCT_HAS_HISTORY',
              'message':
                  'Este producto tiene historial y no puede eliminarse definitivamente.',
              'canArchive': true,
            }),
            409,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
      final repository = CatalogRepository(dio);

      await expectLater(
        repository.deleteProduct('p-1'),
        throwsA(
          isA<ProductDeleteRequiresArchiveException>()
              .having((e) => e.productId, 'productId', 'p-1')
              .having(
                (e) => e.displayCode,
                'displayCode',
                'PRODUCT_HAS_HISTORY',
              ),
        ),
      );
    },
  );

  test('repository archiva usando endpoint canonico', () async {
    String? requestPath;
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        requestPath = options.path;
        return ResponseBody.fromString(
          jsonEncode({
            'ok': true,
            'archived': true,
            'product': {
              'id': 'p-1',
              'nombre': 'Producto fiscal',
              'precio': 100,
              'costo': 60,
              'stock': 1,
              'categoria': 'General',
              'archivedAt': '2026-09-01T12:00:00.000Z',
              'activo': false,
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CatalogRepository(dio);

    final archived = await repository.archiveProduct('p-1');

    expect(requestPath, '/products/p-1/archive');
    expect(archived.activo, isFalse);
    expect(archived.archivedAt, isNotNull);
  });

  test('repository uploadImage prefiere URL servible sobre key cruda', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        expect(options.path, contains('/products/upload'));
        return ResponseBody.fromString(
          jsonEncode({
            'key': 'uploads/companies/company-1/products/images/raw.png',
            'objectKey': 'uploads/companies/company-1/products/images/raw.png',
            'path':
                '/media/object?key=uploads%2Fcompanies%2Fcompany-1%2Fproducts%2Fimages%2Fraw.png',
            'url':
                '/media/object?key=uploads%2Fcompanies%2Fcompany-1%2Fproducts%2Fimages%2Fraw.png',
          }),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final repository = CatalogRepository(dio);

    final uploaded = await repository.uploadImage(
      bytes: const [1, 2, 3],
      filename: 'producto.png',
    );

    expect(uploaded, startsWith('/media/object?key='));
    expect(uploaded, isNot(startsWith('uploads/companies/')));
  });

  test(
    'create con imagen seleccionada no continua si falla la subida',
    () async {
      final repo = _TaxFakeCatalogRepository([])
        ..uploadError = ApiException('Error temporal al subir imagen', 500);
      final container = _containerWith(repo);
      final controller = container.read(catalogControllerProvider.notifier);

      await expectLater(
        controller.create(
          nombre: 'Producto con imagen',
          precio: 100,
          costo: 60,
          stock: 1,
          categoria: 'General',
          imageBytes: const [1, 2, 3],
          filename: 'producto.png',
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_INCLUDED',
        ),
        throwsA(isA<ApiException>()),
      );

      expect(repo.createCalls, 0);
      expect(container.read(catalogControllerProvider).items, isEmpty);
    },
  );
}
