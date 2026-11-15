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
import 'package:flutter/services.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/fulltech_dialog.dart';
import '../../support/platform_goldens.dart';

class _Lists extends PriceListsRepository {
  _Lists() : super(Dio());
  String name = 'Mayorista';
  bool active = true;
  List<PriceListTierDraft>? savedTiers;
  final List<String> searches = [];
  int creates = 0;
  final List<String?> categories = [];
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
  double height = 900,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repository = _Lists();
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        if (request.path.endsWith('/products/categories')) {
          handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'items': [
                  {'name': 'Prueba', 'count': 1},
                  {'name': 'Fuera de primera página', 'count': 20},
                ],
              },
            ),
          );
          return;
        }
        repository.categories.add(
          request.queryParameters['category'] as String?,
        );
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
      child: MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const PriceListsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(PriceListsScreen));
    for (final name in ['add', 'close', 'search']) {
      await precacheImage(AssetImage('assets/image/action_$name.png'), context);
    }
  });
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(390, 844),
    const Size(1024, 600),
    const Size(1920, 1080),
    const Size(2560, 1440),
  ]) {
    testWidgets('diseño, formulario y selector lateral $size', (tester) async {
      final repository = await _pump(
        tester,
        width: size.width,
        height: size.height,
        textScale: size.width == 1024 ? 1.15 : 1,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/price_lists_${size.width.toInt()}.png'),
        ),
      );
      await tester.tap(find.text('Nueva lista'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FullTechDialog>(find.byType(FullTechDialog)).borderRadius,
        0,
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/price_dialog_${size.width.toInt()}.png'),
        ),
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Elegir producto'));
      await tester.tap(find.text('Elegir producto'));
      await tester.pumpAndSettle();
      final drawer = tester.getRect(
        find.byKey(const ValueKey('price-product-drawer')),
      );
      expect(drawer.right, closeTo(size.width, 1));
      expect(drawer.height, closeTo(size.height, 1));
      expect(
        drawer.width,
        closeTo(
          size.width < 640 ? size.width : (size.width * .38).clamp(360, 760),
          1,
        ),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/price_picker_${size.width.toInt()}.png'),
        ),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fuera de primera página').last);
      await tester.pumpAndSettle();
      expect(repository.categories, contains('Fuera de primera página'));
      await tester.tap(find.byTooltip('Cerrar productos'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-product-drawer')), findsNothing);
    });
  }
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
