import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/features/products/ui/product_artwork.dart';
import '../../preview/product_lifecycle_design_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => 'C:/tmp',
        );
  });
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    for (final scenario in designCases) {
      testWidgets('${scenario.$1} renders at $size without overflow', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProductLifecycleDesignGallery(initialCase: scenario.$1),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final dialog in tester.widgetList<AlertDialog>(
          find.byType(AlertDialog),
        )) {
          expect(
            (dialog.shape as RoundedRectangleBorder).borderRadius,
            BorderRadius.zero,
          );
        }
        if (scenario.$1.startsWith('notice-')) {
          final card = find.byKey(const ValueKey('persistent_feedback_card'));
          expect(card, findsOneWidget);
          expect(find.byType(SnackBar), findsNothing);
          final rect = tester.getRect(card);
          expect(size.width - rect.right, closeTo(12, 1));
          expect(size.height - rect.bottom, closeTo(12, 1));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
  testWidgets(
    'failed archived query has retry and never presents an empty success',
    (tester) async {
      await tester.pumpWidget(
        const ProductLifecycleDesignGallery(initialCase: 'archives-error'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Sin productos archivados'), findsNothing);
    },
  );
  testWidgets(
    'catalog uses supplied filter and delete icons with matching control heights',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProductLifecycleDesignGallery(initialCase: 'catalog'),
      );
      await tester.pumpAndSettle();
      final search = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.hintText == 'Buscar por nombre, código o categoría',
      );
      final filter = find.ancestor(
        of: find.text('Filtro'),
        matching: find.byType(OutlinedButton),
      );
      expect(tester.getSize(search).height, tester.getSize(filter).height);
      expect(
        (tester.widget<OutlinedButton>(filter).style!.shape!.resolve({})
                as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.zero,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is ProductArtwork && w.kind == ProductArtworkKind.filter,
        ),
        findsWidgets,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is ProductArtwork && w.kind == ProductArtworkKind.delete,
        ),
        findsWidgets,
      );
    },
  );
  testWidgets(
    'uncertain mutation removes actions until server state is checked',
    (tester) async {
      await tester.pumpWidget(
        const ProductLifecycleDesignGallery(initialCase: 'uncertain'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Archivar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Archivar'));
      await tester.pumpAndSettle();
      expect(find.text('Archivar'), findsNothing);
      expect(find.text('Comprobar estado'), findsOneWidget);
      expect(
        find.text('No se pudo confirmar el cambio. Comprueba el estado.'),
        findsOneWidget,
      );
    },
  );
  for (final flow in [
    ('zero', 'Eliminar definitivamente', 'Eliminar', 'Producto eliminado'),
    ('history', 'Archivar', 'Archivar', 'Producto archivado'),
    ('archived', 'Restaurar', 'Restaurar', 'Producto restaurado'),
  ]) {
    testWidgets('${flow.$1}: one action and confirmation complete the flow', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProductLifecycleDesignGallery(initialCase: flow.$1),
      );
      await tester.pumpAndSettle();
      if (flow.$1 == 'history') {
        expect(find.text('Eliminar definitivamente'), findsNothing);
        expect(find.text('Anular alta'), findsNothing);
      }
      await tester.tap(find.widgetWithText(OutlinedButton, flow.$2));
      await tester.pumpAndSettle();
      expect(find.text(flow.$4), findsNothing);
      await tester.tap(find.widgetWithText(ElevatedButton, flow.$3));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining(flow.$4), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
  testWidgets('cancel keeps the product dialog without a success notice', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProductLifecycleDesignGallery(initialCase: 'zero'),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Eliminar definitivamente'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Gestionar producto'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('persistent_feedback_card')),
      findsNothing,
    );
    expect(find.text('Eliminar definitivamente'), findsOneWidget);
  });
}
