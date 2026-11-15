import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/core/usage/usage_activity_boundary.dart';

void main() {
  testWidgets('default disabled reporting needs no auth provider and preserves the POS child', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UsageActivityBoundary(child: Text('POS disponible'))));
    await tester.pump(const Duration(minutes: 10));
    expect(find.text('POS disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
