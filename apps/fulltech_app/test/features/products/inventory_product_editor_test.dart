import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/products/ui/inventory_module_pages.dart';

class _FakeCatalogRepository extends CatalogRepository {
  _FakeCatalogRepository() : super(Dio());

  int creates = 0;
  int updates = 0;

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
  }) async {
    creates += 1;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ProductModel(
      id: 'created-$creates',
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria,
      fotoUrl: fotoUrl,
    );
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
  }) async {
    updates += 1;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ProductModel(
      id: id,
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      categoria: categoria,
      fotoUrl: fotoUrl,
    );
  }
}

Future<ProductFormResult?> _pumpEditor(
  WidgetTester tester, {
  required _FakeCatalogRepository repo,
  ProductModel? product,
}) async {
  ProductFormResult? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context)
                        .push<ProductFormResult>(
                          MaterialPageRoute<ProductFormResult>(
                            builder: (_) => InventoryProductEditorPage(
                              product: product,
                              categories: const ['General', 'Herramientas'],
                            ),
                          ),
                        );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets(
    'crear producto cierra el formulario sin errores de EditableText',
    (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      final repo = _FakeCatalogRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(find.byType(TextField).at(0), 'Producto prueba');
      await tester.enterText(find.byType(TextField).at(1), 'ABC-001');
      await tester.enterText(find.byType(TextField).at(2), '100');
      await tester.enterText(find.byType(TextField).at(3), '60');
      await tester.enterText(find.byType(TextField).at(4), '5');
      await tester.enterText(find.byType(TextField).at(5), 'General');
      await tester.tap(find.text('Crear producto'));
      await tester.pumpAndSettle();

      expect(repo.creates, 1);
      expect(find.text('Nuevo producto'), findsNothing);
      expect(
        errors.map((e) => e.exceptionAsString()).join('\n'),
        isNot(contains('EditableText')),
      );
      expect(
        errors.map((e) => e.exceptionAsString()).join('\n'),
        isNot(contains('wrong build scope')),
      );
    },
  );

  testWidgets('editar conserva imagen si no se selecciona una nueva', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    final product = ProductModel(
      id: 'p-1',
      nombre: 'Taladro',
      precio: 500,
      costo: 300,
      stock: 2,
      categoria: 'Herramientas',
      fotoUrl: '/uploads/existing.png',
    );
    await _pumpEditor(tester, repo: repo, product: product);

    await tester.enterText(find.byType(TextField).at(0), 'Taladro Pro');
    await tester.enterText(find.byType(TextField).at(2), '650');
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();

    expect(repo.updates, 1);
    expect(repo.creates, 0);
    expect(find.text('Editar producto'), findsNothing);
  });

  testWidgets('escribir letras en código no guarda automáticamente', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(1), 'ABC');
    await tester.pump();

    expect(repo.creates, 0);
    expect(repo.updates, 0);
  });

  testWidgets('escribir números en código no guarda automáticamente', (
    tester,
  ) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(1), '1234567890');
    await tester.pump();

    expect(repo.creates, 0);
    expect(repo.updates, 0);
  });

  testWidgets('Enter en el campo código no crea producto', (tester) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(0), 'Producto scanner');
    await tester.enterText(find.byType(TextField).at(1), 'SCN-001');
    await tester.enterText(find.byType(TextField).at(2), '100');
    await tester.enterText(find.byType(TextField).at(3), '60');
    await tester.enterText(find.byType(TextField).at(4), '5');
    await tester.enterText(find.byType(TextField).at(5), 'General');
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 80));

    expect(repo.creates, 0);
    expect(repo.updates, 0);
  });

  testWidgets('doble click en guardar crea una sola vez', (tester) async {
    final repo = _FakeCatalogRepository();
    await _pumpEditor(tester, repo: repo);

    await tester.enterText(find.byType(TextField).at(0), 'Producto doble');
    await tester.enterText(find.byType(TextField).at(1), 'DBL-001');
    await tester.enterText(find.byType(TextField).at(2), '100');
    await tester.enterText(find.byType(TextField).at(3), '60');
    await tester.enterText(find.byType(TextField).at(4), '5');
    await tester.enterText(find.byType(TextField).at(5), 'General');
    final save = find.text('Crear producto');
    await tester.tap(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repo.creates, 1);
    expect(repo.updates, 0);
  });

  testWidgets('abrir y cerrar repetidamente no deja EditableText activo', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previousOnError);

    final repo = _FakeCatalogRepository();
    for (var i = 0; i < 10; i++) {
      await _pumpEditor(tester, repo: repo);
      await tester.enterText(find.byType(TextField).first, 'Producto $i');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
    }

    final messages = errors.map((e) => e.exceptionAsString()).join('\n');
    expect(messages, isNot(contains('EditableText')));
    expect(messages, isNot(contains('Duplicate GlobalKeys')));
    expect(messages, isNot(contains('deactivated widget')));
  });
}
