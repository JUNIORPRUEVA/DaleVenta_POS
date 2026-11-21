import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/products/ui/product_lifecycle_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../preview/product_lifecycle_design_preview.dart';

const _id = '12345678-1234-4234-8234-123456789abc';

class _Repository extends DesignCatalogRepository {
  _Repository() : super('history');
  @override
  Future<List<Map<String, dynamic>>> archivedProducts({
    String search = '',
    int page = 1,
  }) async => [
    {'id': _id, 'codigo': _id, 'nombre': 'Auriculares $_id'},
  ];
}

void main() {
  for (final archived in [false, true]) {
    testWidgets(
      'technical identifiers stay hidden in ${archived ? 'archived list' : 'product details'}',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogRepositoryProvider.overrideWithValue(_Repository()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: archived
                    ? ArchivedProductsDialog(onChanged: () async {})
                    : ProductLifecycleDialog(
                        productId: _id,
                        name: 'Auriculares $_id',
                        onChanged: () async {},
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(_id), findsNothing);
        expect(find.text('Auriculares'), findsOneWidget);
        if (archived) expect(find.textContaining('Sin código'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
