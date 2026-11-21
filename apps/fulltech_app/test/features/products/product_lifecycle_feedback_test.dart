import 'package:daleventa_pos/features/products/ui/product_lifecycle_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a notice replaced before the first frame leaves only the latest', (tester) async {
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      host = context;
      return const Scaffold();
    })));
    ProductLifecycleFeedback.notice(host, 'Primer aviso');
    ProductLifecycleFeedback.notice(host, 'Último aviso');
    await tester.pumpAndSettle();
    expect(find.textContaining('Primer aviso'), findsNothing);
    expect(find.textContaining('Último aviso'), findsOneWidget);
    ProductLifecycleFeedback.dismissNotice();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('persistent_feedback_card')), findsNothing);
  });

  testWidgets('closing the screen before first paint allows safe repeated cleanup', (tester) async {
    late BuildContext host;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      host = context;
      return const Scaffold();
    })));
    ProductLifecycleFeedback.notice(host, 'Guardado');
    await tester.pumpWidget(const SizedBox.shrink());
    ProductLifecycleFeedback.dismissNotice();
    ProductLifecycleFeedback.dismissNotice();
    expect(tester.takeException(), isNull);
  });
}
