import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_fiscal_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final caps = EcfCapabilities.fromJson({
    'environment': 'PRODUCTION',
    'posReady': true,
    'posAvailableTypes': ['E31'],
    'documentTypes': [
      {'documentType': 'E31', 'allowedForCompany': true},
      {'documentType': 'E32', 'allowedForCompany': true},
    ],
  });
  final ranges = [
    EcfSequenceInfo(
      id: 'a',
      documentType: 'E31',
      prefix: 'E31',
      startNumber: 1,
      nextNumber: 3,
      endNumber: 150,
      active: true,
      consumed: 2,
      remaining: 148,
      validUntil: DateTime(2027, 12, 31),
    ),
    const EcfSequenceInfo(
      id: 'b',
      documentType: 'E31',
      prefix: 'E31',
      startNumber: 1,
      nextNumber: 3,
      endNumber: 150,
      active: false,
      consumed: 2,
      remaining: 148,
    ),
  ];

  Future<void> pump(
    WidgetTester tester,
    AsyncValue<List<EcfSequenceInfo>> data, {
    VoidCallback? retry,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: EcfFiscalOverview(
              capabilities: caps,
              sequences: data,
              onRetry: retry ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'real values, inactive history and server availability fit mobile',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pump(tester, AsyncData(ranges));
      expect(find.text('Producción'), findsOneWidget);
      expect(find.text('Crédito fiscal'), findsOneWidget);
      expect(find.text('Consumo · No disponible'), findsOneWidget);
      expect(find.textContaining('Emisión disponible'), findsNothing);
      expect(find.textContaining('Vence: 31/12/2027'), findsOneWidget);
      expect(find.textContaining('· Inactivo'), findsOneWidget);
      expect(
        find.textContaining('2 consumidos · 148 restantes'),
        findsNWidgets(2),
      );
      expect(find.text('Vender sin comprobante'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loading, error retry and empty are distinct from zero availability',
    (tester) async {
      await pump(tester, const AsyncLoading());
      expect(find.text('Consultando numeración…'), findsOneWidget);
      expect(find.text('Todavía no hay rangos registrados.'), findsNothing);
      var retries = 0;
      await pump(
        tester,
        AsyncError(Exception('synthetic'), StackTrace.current),
        retry: () => retries++,
      );
      await tester.tap(find.text('Reintentar'));
      expect(retries, 1);
      await pump(tester, const AsyncData([]));
      expect(find.text('Todavía no hay rangos registrados.'), findsOneWidget);
    },
  );
}
