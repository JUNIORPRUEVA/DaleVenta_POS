import 'package:daleventa_pos/core/auth/public_website_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'public route requests document navigation once instead of displaying the legacy landing',
    (tester) async {
      var visits = 0;
      await tester.pumpWidget(
        MaterialApp(home: PublicWebsiteEntry(navigate: () => visits++)),
      );
      await tester.pump();
      await tester.pump();
      expect(visits, 1);
      expect(find.text('Abriendo FullPOS Cloud…'), findsOneWidget);
    },
  );
}
