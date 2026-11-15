import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/fulltech_dialog.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/platform_goldens.dart';

class _Categories extends InventoryCategoriesController {
  _Categories() {
    state = InventoryCategoriesState(
      items: [
        for (final name in [
          'COMPUTADORAS Y POS',
          'HERRAMIENTAS',
          'SISTEMA DE VIGILANCIA',
          'SMART Y ACCESORIOS',
        ])
          InventoryCategoryModel(
            id: name,
            name: name,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ),
      ],
    );
  }
  String? savedName;
  @override
  Future<void> load() async {}
  @override
  Future<InventoryCategoryModel> upsert({
    String? id,
    required String name,
    String? imageBase64,
    bool clearImage = false,
  }) async {
    savedName = name;
    return InventoryCategoryModel(
      id: id ?? 'new',
      name: name,
      imageBase64: imageBase64,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
  }
}

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'test',
        email: 'test@test.local',
        nombreCompleto: 'Usuario',
        telefono: '',
        role: 'ADMIN',
        companyId: 'test-company',
      ),
    );
  }
}

Future<_Categories> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = _Categories();
  final key = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryCategoriesProvider.overrideWith((ref) => controller),
        authStateProvider.overrideWith((ref) => _Auth(ref)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Categorías'),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: const RoundedRectangleBorder(),
                ),
                onPressed: () =>
                    (key.currentState as dynamic).openNewCategory(),
                child: const Text('Nueva categoría'),
              ),
            ],
          ),
          body: CategoriesTab(
            key: key,
            products: [
              ProductModel(
                id: 'one',
                nombre: 'Producto',
                precio: 100,
                costo: 50,
                stock: 3,
                categoria: 'HERRAMIENTAS',
              ),
            ],
            onRefresh: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(CategoriesTab));
    for (final name in ['search', 'edit', 'delete']) {
      await precacheImage(AssetImage('assets/image/action_$name.png'), context);
    }
  });
  await tester.pumpAndSettle();
  return controller;
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
    testWidgets('categorías en lista compacta $size', (tester) async {
      await _pump(tester, size);
      expect(find.text('Categorías'), findsOneWidget);
      expect(find.text('Nueva categoría'), findsOneWidget);
      final first = tester.getTopLeft(find.text('COMPUTADORAS Y POS'));
      final second = tester.getTopLeft(find.text('HERRAMIENTAS'));
      expect(first.dx, closeTo(second.dx, 1));
      expect(second.dy - first.dy, closeTo(64, 1));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile(
          platformGolden('goldens/categories_${size.width.toInt()}.png'),
        ),
      );
      if (size.width >= 640) {
        await tester.enterText(find.byType(TextField), 'HERRAMIENTAS');
        await tester.pumpAndSettle();
        expect(find.text('COMPUTADORAS Y POS'), findsNothing);
        expect(
          find.byWidgetPredicate((w) => w is Text && w.data == 'HERRAMIENTAS'),
          findsOneWidget,
        );
      }
    });
    testWidgets('formulario cuadrado compacto $size', (tester) async {
      final controller = await _pump(tester, size);
      await tester.tap(find.text('Nueva categoría'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FullTechDialog>(find.byType(FullTechDialog)).borderRadius,
        0,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('category-image-preview'))),
        const Size(72, 72),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          platformGolden('goldens/category_editor_${size.width.toInt()}.png'),
        ),
      );
      await tester.enterText(
        find.descendant(
          of: find.byType(FullTechDialog),
          matching: find.byType(TextField),
        ),
        '',
      );
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe el nombre de la categoría.'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(FullTechDialog),
          matching: find.byType(TextField),
        ),
        'Nueva prueba',
      );
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(controller.savedName, 'Nueva prueba');
      expect(find.byType(FullTechDialog), findsNothing);
    });
  }
}
