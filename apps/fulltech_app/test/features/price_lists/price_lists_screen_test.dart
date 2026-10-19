import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/price_lists/data/price_lists_repository.dart';
import 'package:daleventa_pos/features/price_lists/ui/price_lists_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Lists extends PriceListsRepository {
  _Lists() : super(Dio());
  String name = 'Mayorista';
  bool active = true;
  List<PriceListTierDraft>? savedTiers;
  final List<String> searches = [];
  int creates = 0;
  @override
  Future<PriceListModel> createPriceList({
    required String name,
    String description = '',
  }) async {
    creates++;
    this.name = name;
    return (await fetchPriceLists()).single;
  }

  @override
  Future<List<PriceListModel>> fetchPriceLists() async => [
    PriceListModel(
      id: 'list-a',
      name: name,
      active: active,
      priority: 0,
      rules: const [
        PriceListRuleModel(
          id: 'rule-a',
          productId: 'cable',
          productName: 'Cable',
          referencePrice: 100,
          mode: 'FIXED_PRICE',
          minQuantity: 1,
          fixedPrice: 80,
          tiers: [PriceListTierModel(minQuantity: 5, fixedPrice: 70)],
        ),
      ],
    ),
  ];
  @override
  Future<PriceListModel> updatePriceList({
    required String id,
    String? name,
    String? description,
    bool? active,
  }) async {
    this.name = name ?? this.name;
    this.active = active ?? this.active;
    return (await fetchPriceLists()).single;
  }

  @override
  Future<PriceListRuleModel> upsertRule({
    required String priceListId,
    required String productId,
    required String mode,
    double? fixedPrice,
    double? discountPercent,
    double minQuantity = 1,
    List<PriceListTierDraft> tiers = const [],
  }) async {
    savedTiers = List.of(tiers);
    return (await fetchPriceLists()).single.rules.single;
  }
}

Future<_Lists> _pump(
  WidgetTester tester, {
  bool enabled = true,
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _Lists();
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        repository.searches.add('${request.queryParameters['search'] ?? ''}');
        handler.resolve(
          Response(
            requestOptions: request,
            data: {
              'items': [
                {
                  'id': 'cable',
                  'nombre': 'Cable',
                  'precio': 100,
                  'costo': 40,
                  'categoria': 'Prueba',
                },
              ],
              'page': 1,
              'limit': 50,
              'total': 1,
              'hasMore': false,
            },
          ),
        );
      },
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companySettingsProvider.overrideWith(
          (_) async => CompanySettings.empty().copyWith(
            wholesalePriceListsEnabled: enabled,
          ),
        ),
        priceListsRepositoryProvider.overrideWithValue(repository),
        dioProvider.overrideWithValue(dio),
      ],
      child: const MaterialApp(home: PriceListsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('creates a list through its form', (tester) async {
    final repository = await _pump(tester);
    await tester.tap(find.text('Nueva lista'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Lista nueva',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repository.creates, 1);
    expect(repository.name, 'Lista nueva');
    expect(tester.takeException(), isNull);
  });

  testWidgets('list administration returns to billing', (tester) async {
    final router = GoRouter(
      initialLocation: '/price-lists-test',
      routes: [
        GoRoute(
          path: '/price-lists-test',
          builder: (_, __) => const PriceListsScreen(),
        ),
        GoRoute(
          path: Routes.cotizaciones,
          builder: (_, __) => const Scaffold(body: Text('Facturación')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companySettingsProvider.overrideWith(
            (_) async => CompanySettings.empty().copyWith(
              wholesalePriceListsEnabled: true,
            ),
          ),
          priceListsRepositoryProvider.overrideWithValue(_Lists()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Facturación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'product picker searches server instead of filtering first page',
    (tester) async {
      final repository = await _pump(tester);
      await tester.tap(find.text('Elegir producto'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar producto por nombre o código'),
        'otro producto',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repository.searches, contains('otro producto'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('disabled company cannot administer wholesale lists', (
    tester,
  ) async {
    await _pump(tester, enabled: false);
    expect(
      find.text('Mayoreo no está activo para esta empresa.'),
      findsOneWidget,
    );
    expect(find.text('Nueva lista'), findsNothing);
  });

  testWidgets('edits existing list without creating another list', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await tester.tap(find.byTooltip('Editar lista'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre'),
      'Distribuidor',
    );
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(repository.name, 'Distribuidor');
    expect(find.text('Mayorista'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deactivates list from administration', (tester) async {
    final repository = await _pump(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repository.active, isFalse);
  });

  testWidgets('editing product rule preserves existing quantity tiers', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await tester.tap(find.text('Elegir producto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cable').last);
    await tester.pumpAndSettle();
    expect(find.text('5.0'), findsNothing);
    expect(find.text('Desde 5.0'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardar regla'));
    await tester.tap(find.text('Guardar regla'));
    await tester.pumpAndSettle();
    expect(repository.savedTiers, hasLength(1));
    expect(repository.savedTiers!.single.fixedPrice, 70);
    expect(tester.takeException(), isNull);
  });

  testWidgets('administration fits narrow screens', (tester) async {
    await _pump(tester, width: 390);
    expect(find.text('Nueva lista'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
