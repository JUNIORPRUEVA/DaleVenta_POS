import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/tax/product_tax_options_provider.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/modules/ventas/registrar_venta_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'inventory ON shows stock only for tracked products and keeps sale action',
    (tester) async {
      await _pumpPos(tester, inventoryEnabled: true, products: _products);

      expect(find.text('DISP'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('SIN STOCK'), findsNothing);
      expect(find.textContaining('Agregar stock'), findsNothing);

      await tester.tap(find.text('Café').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('RD\$ 120.00'), findsWidgets);
    },
  );

  testWidgets(
    'inventory OFF hides stock badges, no-stock states and keeps products sellable',
    (tester) async {
      await _pumpPos(
        tester,
        inventoryEnabled: false,
        products: [_trackedOutOfStockProduct],
      );

      expect(find.text('DISP'), findsNothing);
      expect(find.text('SIN STOCK'), findsNothing);
      expect(find.textContaining('Sin stock'), findsNothing);
      expect(find.textContaining('Agregar stock'), findsNothing);

      await tester.tap(find.text('Café').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('RD\$ 120.00'), findsWidgets);
      expect(find.textContaining('agrega stock'), findsNothing);
    },
  );

  testWidgets('settings reload updates POS stock UI', (tester) async {
    await _pumpPos(
      tester,
      inventoryEnabled: true,
      products: [_trackedOutOfStockProduct],
    );

    expect(find.text('SIN STOCK'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await _pumpPos(
      tester,
      inventoryEnabled: false,
      products: [_trackedOutOfStockProduct],
    );

    expect(find.text('SIN STOCK'), findsNothing);
    expect(find.text('DISP'), findsNothing);
    expect(find.textContaining('Agregar stock'), findsNothing);
  });
}

Future<void> _pumpPos(
  WidgetTester tester, {
  required bool inventoryEnabled,
  required List<ProductModel> products,
}) async {
  final settings = CompanySettings.empty().copyWith(
    inventoryEnabled: inventoryEnabled,
    taxEnabled: false,
    ncfEnabled: false,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(_TestAuthController.new),
        companySettingsProvider.overrideWith((ref) async => settings),
        productTaxUiConfigProvider.overrideWith(
          (ref) async =>
              ProductTaxUiConfig(settings: settings, activeTaxes: const []),
        ),
        catalogRepositoryProvider.overrideWithValue(
          _FakeCatalogRepository(products),
        ),
        posNcfSequencesProvider.overrideWith((ref) async => const []),
      ],
      child: const MaterialApp(home: RegistrarVentaScreen()),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

final _trackedProduct = ProductModel(
  id: '11111111-1111-4111-8111-111111111111',
  nombre: 'Café',
  precio: 120,
  costo: 60,
  stock: 5,
);

final _trackedOutOfStockProduct = _trackedProduct.copyWith(stock: 0);

final _nonInventoryProduct = ProductModel(
  id: '22222222-2222-4222-8222-222222222222',
  nombre: 'Tarjeta regalo',
  precio: 500,
  costo: 0,
  stock: 0,
  trackInventory: false,
);

final _service = ProductModel(
  id: '33333333-3333-4333-8333-333333333333',
  nombre: 'Instalación',
  precio: 1500,
  costo: 0,
  stock: 0,
  itemType: 'SERVICE',
  trackInventory: false,
);

final _products = [_trackedProduct, _nonInventoryProduct, _service];

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository(this.products) : super(Dio());

  final List<ProductModel> products;

  @override
  Future<List<ProductModel>> getCachedProducts({Duration? maxAge}) async {
    return const [];
  }

  @override
  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    return products;
  }
}

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'user-1',
        email: 'user@example.test',
        nombreCompleto: 'Usuario Test',
        telefono: '',
        role: 'ADMIN',
        companyId: 'company-1',
      ),
    );
  }
}
