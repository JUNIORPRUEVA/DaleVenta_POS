import 'package:daleventa_pos/features/products/ui/product_lifecycle_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'corner notice retains working actions without a bottom snackbar',
    (tester) async {
      late BuildContext host;
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      ProductLifecycleFeedback.notice(
        host,
        'Permite el acceso a las imágenes.',
        warning: true,
        actionLabel: 'Configuración',
        onAction: () => opened++,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('Configuración'));
      expect(opened, 1);
      ProductLifecycleFeedback.dismissNotice();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'notices hide technical identifiers and use the upper right corner',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      ProductLifecycleFeedback.notice(
        host,
        'Producto 12345678-1234-4234-8234-123456789abc archivado',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('12345678-1234'), findsNothing);
      expect(find.textContaining('Producto archivado'), findsOneWidget);
      final rect = tester.getRect(
        find.byKey(const ValueKey('persistent_feedback_card')),
      );
      expect(rect.top, closeTo(12, 1));
      expect(1200 - rect.right, closeTo(12, 1));
      ProductLifecycleFeedback.dismissNotice();
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'a notice replaced before the first frame leaves only the latest',
    (tester) async {
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      ProductLifecycleFeedback.notice(host, 'Primer aviso');
      ProductLifecycleFeedback.notice(host, 'Último aviso');
      await tester.pumpAndSettle();
      expect(find.textContaining('Primer aviso'), findsNothing);
      expect(find.textContaining('Último aviso'), findsOneWidget);
      ProductLifecycleFeedback.dismissNotice();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('persistent_feedback_card')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'closing the screen before first paint allows safe repeated cleanup',
    (tester) async {
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold();
            },
          ),
        ),
      );
      ProductLifecycleFeedback.notice(host, 'Guardado');
      await tester.pumpWidget(const SizedBox.shrink());
      ProductLifecycleFeedback.dismissNotice();
      ProductLifecycleFeedback.dismissNotice();
      expect(tester.takeException(), isNull);
    },
  );
}
