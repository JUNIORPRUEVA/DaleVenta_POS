import 'dart:convert';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/registrar_venta_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del camino paginado del POS (hotfix Large Dataset).
///
/// Regla del incidente: el catalogo NO se descarga completo ni se filtra en
/// memoria. La pantalla pide la pagina 1 al servidor, agrega paginas con
/// loadMore, busca en el servidor con debounce y, si la red falla, cae al
/// snapshot local COMPLETO avisando que esta en modo offline.
void main() {
  testWidgets(
    'POS pide SOLO la pagina 1 y no descarga el catalogo completo',
    (tester) async {
      final server = _PagedProductsServer(_catalog80);
      await _pumpPos(tester, server: server);

      final productRequests = server.requestsFor(ApiRoutes.catalogProducts);
      expect(productRequests.length, 1, reason: 'abrir el POS = 1 peticion');
      expect(productRequests.single.queryParameters['page'], 1);
      expect(productRequests.single.queryParameters['limit'], 50);
      expect(
        _hasParameterCalled(productRequests.single, 'search'),
        isFalse,
        reason: 'sin busqueda no se envia search',
      );

      expect(find.text('PROD 01'), findsOneWidget);
      expect(
        find.text('PROD 79'),
        findsNothing,
        reason: 'la pagina 2 aun no se ha pedido',
      );
    },
  );

  testWidgets('POS loadMore al final agrega la pagina 2 sin duplicar', (
    tester,
  ) async {
    final server = _PagedProductsServer(_catalog80);
    await _pumpPos(tester, server: server);

    await tester.drag(find.byType(GridView).first, const Offset(0, -6000));
    await tester.pumpAndSettle();

    final pages = server
        .requestsFor(ApiRoutes.catalogProducts)
        .map((request) => request.queryParameters['page'])
        .toList();
    expect(pages, contains(2), reason: 'se pidio la pagina 2');

    await tester.drag(find.byType(GridView).first, const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(find.text('PROD 79'), findsOneWidget);
  });

  testWidgets('POS busca en el SERVIDOR con debounce (no por pulsacion)', (
    tester,
  ) async {
    final server = _PagedProductsServer(_catalog80);
    await _pumpPos(tester, server: server);

    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'PROD 07');
    // La busqueda remota tiene debounce: se avanza el reloj de la prueba.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final searches = server
        .requestsFor(ApiRoutes.catalogProducts)
        .where((request) => request.queryParameters['search'] == 'PROD 07')
        .toList();
    expect(searches, hasLength(1), reason: 'debounce: una sola peticion');
    expect(searches.single.queryParameters['page'], 1);
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('PROD 07'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('PROD 01'),
      ),
      findsNothing,
      reason: 'el servidor filtro, no la memoria del telefono',
    );
  });

  testWidgets(
    'POS agrega por codigo escaneado aunque el producto no este en la pagina 1',
    (tester) async {
      final server = _PagedProductsServer(_catalog80);
      await _pumpPos(tester, server: server);

      expect(
        find.text('Zapato de seguridad'),
        findsNothing,
        reason: 'vive en la pagina 2',
      );

      await tester.tap(find.byTooltip('Buscar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'ZAP-999');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(
        server
            .requestsFor(ApiRoutes.catalogProducts)
            .any((request) => request.queryParameters['search'] == 'ZAP-999'),
        isTrue,
        reason: 'el codigo se busca en el servidor',
      );
      expect(
        find.text('Zapato de seguridad'),
        findsOneWidget,
        reason: 'quedo agregado al carrito por su id real',
      );
    },
  );

  testWidgets('POS aplica las categorias seleccionadas en el servidor', (
    tester,
  ) async {
    final server = _PagedProductsServer(_catalog80);
    await _pumpPos(tester, server: server);

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();
    for (final category in const ['Bebidas', 'Snacks']) {
      await tester.tap(
        find.ancestor(
          of: find.text(category).last,
          matching: find.byType(CheckboxListTile),
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();

    final filtered = server
        .requestsFor(ApiRoutes.catalogProducts)
        .where((request) => request.queryParameters['categories'] != null)
        .toList();
    expect(filtered, isNotEmpty, reason: 'el filtro viaja al servidor');
    final sent = '${filtered.last.queryParameters['categories']}'.split(',');
    expect(sent, containsAll(const ['Bebidas', 'Snacks']));
    expect(find.text('PROD 04'), findsOneWidget);
  });

  testWidgets('POS no oculta resultados que el servidor devolvio por categoria', (
    tester,
  ) async {
    final server = _PagedProductsServer(_catalog80);
    await _pumpPos(tester, server: server);

    await tester.tap(find.byTooltip('Buscar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Limpieza');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('PROD 02'),
      ),
      findsOneWidget,
      reason: 'el backend busca por categoria; la UI no debe filtrarla de nuevo',
    );
  });

  testWidgets('POS sin conexion usa el snapshot local y lo avisa', (
    tester,
  ) async {
    final server = _PagedProductsServer(
      _catalog80,
      offline: true,
    );
    await _pumpPos(
      tester,
      server: server,
      localSnapshot: [_beverageProduct, _snackProduct],
    );

    expect(
      find.text('Sin conexión: mostrando los productos guardados en este dispositivo'),
      findsOneWidget,
      reason: 'la UI no debe fingir que son datos del servidor',
    );
    expect(find.text('Coca Cola'), findsOneWidget);
    expect(find.text('Galletas'), findsOneWidget);
    expect(
      find.text('No se pudieron cargar los productos.'),
      findsNothing,
      reason: 'el fallback offline evita el estado de error',
    );
  });
}

Future<void> _pumpPos(
  WidgetTester tester, {
  required _PagedProductsServer server,
  List<ProductModel> localSnapshot = const <ProductModel>[],
  Size surfaceSize = const Size(390, 820),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final settings = CompanySettings.empty().copyWith(
    inventoryEnabled: false,
    measurementUnitsEnabled: false,
    multiWarehouseEnabled: false,
    taxEnabled: false,
    ncfEnabled: false,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _TestAuthController(ref, userId: 'user-1', companyId: 'c-1'),
        ),
        companySettingsProvider.overrideWith((ref) async => settings),
        productTaxUiConfigProvider.overrideWith(
          (ref) async =>
              ProductTaxUiConfig(settings: settings, activeTaxes: const []),
        ),
        catalogRepositoryProvider.overrideWithValue(
          _FakeCatalogRepository(localSnapshot, server.categoryCounts),
        ),
        dioProvider.overrideWithValue(server.dio),
        warehousesProvider.overrideWith((ref) async => const []),
        warehouseTerminalsProvider.overrideWith((ref) async => const []),
        posNcfSequencesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: RegistrarVentaScreen()),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

bool _hasParameterCalled(RequestOptions request, String name) {
  return request.queryParameters.containsKey(name);
}

/// Doble del API de productos: implementa el contrato paginado real y registra
/// cada peticion para poder comprobar QUE se pidio (pagina, limite, busqueda,
/// categorias) y que NO se descarga el catalogo completo.
class _PagedProductsServer {
  _PagedProductsServer(this.products, {this.offline = false}) {
    dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        final path = options.path;
        if (path.endsWith(ApiRoutes.productCategories)) {
          return _jsonResponse({
            'items': [
              for (final entry in categoryCounts.entries)
                {'name': entry.key, 'count': entry.value},
            ],
          });
        }
        if (path.endsWith(ApiRoutes.catalogProducts)) {
          requests.add(options);
          if (offline) {
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'sin conexion (prueba)',
            );
          }
          return _jsonResponse(_page(options));
        }
        return ResponseBody.fromString(
          '{}',
          404,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
  }

  final List<ProductModel> products;
  final bool offline;
  final List<RequestOptions> requests = <RequestOptions>[];
  late final Dio dio;

  Map<String, int> get categoryCounts {
    final counts = <String, int>{};
    for (final product in products) {
      counts.update(
        product.categoriaLabel,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  List<RequestOptions> requestsFor(String path) {
    return requests.where((request) => request.path.endsWith(path)).toList();
  }

  Map<String, dynamic> _page(RequestOptions options) {
    final query = options.queryParameters;
    final search = '${query['search'] ?? ''}'.trim().toLowerCase();
    final filters =
        <String>{
              ...'${query['categories'] ?? ''}'.split(','),
              '${query['category'] ?? ''}',
            }
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet();
    final filtered = products.where((product) {
      if (filters.isNotEmpty && !filters.contains(product.categoriaLabel)) {
        return false;
      }
      if (search.isEmpty) return true;
      // Mismo criterio que el backend: nombre, codigo y categoria.
      return product.nombre.toLowerCase().contains(search) ||
          (product.codigo ?? '').toLowerCase().contains(search) ||
          product.categoriaLabel.toLowerCase().contains(search);
    }).toList(growable: false);

    final limit = int.tryParse('${query['limit'] ?? 50}') ?? 50;
    final page = int.tryParse('${query['page'] ?? 1}') ?? 1;
    final start = (page - 1) * limit;
    final slice = start >= filtered.length
        ? const <ProductModel>[]
        : filtered.sublist(start, (start + limit).clamp(0, filtered.length));
    final hasMore = start + slice.length < filtered.length;

    return {
      'items': [
        for (final product in slice)
          () {
            final encoded = product.toJson();
            // `ProductModel.fromJson` prioriza `stockDecimal` sobre `stock`:
            // el doble emite la pareja coherente, como hace el backend.
            encoded['stockDecimal'] = product.stock?.toString() ?? '0';
            return encoded;
          }(),
      ],
      'page': page,
      'limit': limit,
      'total': filtered.length,
      'hasMore': hasMore,
      'nextPage': hasMore ? page + 1 : null,
    };
  }
}

ResponseBody _jsonResponse(Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository(this.snapshot, this.categoryCounts) : super(Dio());

  final List<ProductModel> snapshot;
  final Map<String, int> categoryCounts;

  @override
  Future<List<ProductModel>> getCachedProducts({Duration? maxAge}) async {
    return snapshot;
  }

  @override
  Future<Map<String, int>> fetchProductCategories({
    bool includeArchived = false,
  }) async {
    return categoryCounts;
  }

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    return snapshot;
  }

  @override
  Future<List<UnitOfMeasureModel>> fetchUnitOfMeasures() async {
    return const [UnitOfMeasureModel.unit];
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(
    super.ref, {
    required String userId,
    required String companyId,
  }) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: userId,
        email: '$userId@example.test',
        nombreCompleto: 'Usuario $userId',
        telefono: '',
        role: 'ADMIN',
        companyId: companyId,
      ),
    );
  }
}

const _categoryCycle = ['Bebidas', 'Snacks', 'Limpieza'];

/// Catalogo de 80 productos: la pagina 1 (limite 50) nunca incluye el ultimo,
/// de modo que cualquier producto de la pagina 2 demuestra paginacion real.
final _catalog80 = <ProductModel>[
  for (var index = 1; index <= 79; index += 1)
    ProductModel(
      id: '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
      nombre: 'PROD ${index.toString().padLeft(2, '0')}',
      codigo: 'SKU-${index.toString().padLeft(3, '0')}',
      precio: 10 + index.toDouble(),
      costo: 5,
      stock: 50,
      categoria: _categoryCycle[index % _categoryCycle.length],
    ),
  ProductModel(
    id: '00000000-0000-4000-8000-000000009999',
    nombre: 'Zapato de seguridad',
    codigo: 'ZAP-999',
    precio: 500,
    costo: 250,
    stock: 8,
    categoria: 'Calzado',
  ),
];

final _beverageProduct = ProductModel(
  id: '44444444-4444-4444-8444-444444444444',
  nombre: 'Coca Cola',
  precio: 75,
  costo: 40,
  stock: 10,
  categoria: 'Bebidas',
);

final _snackProduct = ProductModel(
  id: '55555555-5555-4555-8555-555555555555',
  nombre: 'Galletas',
  precio: 35,
  costo: 15,
  stock: 12,
  categoria: 'Snacks',
);
