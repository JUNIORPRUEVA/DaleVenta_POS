import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_sequence_range_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Declaración del rango de numeración (e-NCF).
///
/// Sin este dato el backend responde `ECF_SEQUENCE_EXHAUSTED` al preparar un
/// comprobante, y el cliente no tiene forma de saber que le falta declarar la
/// numeración. Se prueba lo que puede fallar: que pida el dato cuando falta, que
/// no lo pida dos veces, que no envíe rangos incoherentes y que traduzca los
/// rechazos del servidor.
class _FakeRepository extends EcfRepository {
  _FakeRepository() : super(Dio());

  List<EcfSequenceInfo> existing = const [];
  Object? failure;
  int saves = 0;
  String? lastDocumentType;
  int? lastFrom;
  int? lastTo;

  @override
  Future<List<EcfSequenceInfo>> sequences() async => existing;

  @override
  Future<void> registerSequence({
    required String documentType,
    required int startNumber,
    required int endNumber,
    String? validUntil,
  }) async {
    saves++;
    lastDocumentType = documentType;
    lastFrom = startNumber;
    lastTo = endNumber;
    if (failure != null) throw failure!;
    existing = [
      EcfSequenceInfo(
        id: 'seq-1',
        documentType: documentType,
        prefix: documentType,
        startNumber: startNumber,
        nextNumber: startNumber,
        endNumber: endNumber,
        active: true,
        consumed: 0,
        remaining: endNumber - startNumber + 1,
      ),
    ];
  }
}

EcfSequenceInfo _range({
  String documentType = 'E31',
  int remaining = 10,
  bool active = true,
}) => EcfSequenceInfo(
  id: 'seq-x',
  documentType: documentType,
  prefix: documentType,
  startNumber: 1,
  nextNumber: 2,
  endNumber: 1 + remaining,
  active: active,
  consumed: 1,
  remaining: remaining,
);

Future<_FakeRepository> _pump(
  WidgetTester tester, {
  List<EcfSequenceInfo> existing = const [],
  Object? failure,
  bool canManage = true,
}) async {
  final repository = _FakeRepository()
    ..existing = existing
    ..failure = failure;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [ecfRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: EcfSequenceRangeSection(canManage: canManage),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('sin numeración pide los dos números', (tester) async {
    await _pump(tester);

    expect(find.text('Numeración de facturas'), findsOneWidget);
    expect(find.byKey(const ValueKey('ecf_sequence_from')), findsOneWidget);
    expect(find.byKey(const ValueKey('ecf_sequence_to')), findsOneWidget);
  });

  testWidgets('con numeración disponible no pide nada', (tester) async {
    await _pump(tester, existing: [_range()]);

    expect(find.text('Numeración de facturas'), findsNothing);
  });

  testWidgets('una numeración agotada sí pide declarar otra', (tester) async {
    await _pump(tester, existing: [_range(remaining: 0)]);

    expect(find.text('Numeración de facturas'), findsOneWidget);
  });

  testWidgets('una numeración de otro tipo no cubre las facturas', (
    tester,
  ) async {
    await _pump(tester, existing: [_range(documentType: 'E34')]);

    expect(find.text('Numeración de facturas'), findsOneWidget);
  });

  testWidgets('guardar envía el rango y la sección desaparece', (tester) async {
    final repository = await _pump(tester);

    await tester.enterText(find.byKey(const ValueKey('ecf_sequence_from')), '1');
    await tester.enterText(
      find.byKey(const ValueKey('ecf_sequence_to')),
      '500',
    );
    await tester.tap(find.byKey(const ValueKey('ecf_sequence_save')));
    await tester.pumpAndSettle();

    expect(repository.saves, 1);
    // El prefijo lo pone el backend: solo se envían los números.
    expect(repository.lastDocumentType, 'E31');
    expect(repository.lastFrom, 1);
    expect(repository.lastTo, 500);
    expect(find.text('Numeración de facturas'), findsNothing);
  });

  testWidgets('un rango incoherente no se envía', (tester) async {
    final repository = await _pump(tester);

    await tester.enterText(find.byKey(const ValueKey('ecf_sequence_from')), '500');
    await tester.enterText(find.byKey(const ValueKey('ecf_sequence_to')), '10');
    await tester.tap(find.byKey(const ValueKey('ecf_sequence_save')));
    await tester.pumpAndSettle();

    expect(repository.saves, 0);
    expect(find.textContaining('el final no puede ser'), findsOneWidget);
  });

  testWidgets('un rango vacío no se envía', (tester) async {
    final repository = await _pump(tester);

    await tester.tap(find.byKey(const ValueKey('ecf_sequence_save')));
    await tester.pumpAndSettle();

    expect(repository.saves, 0);
  });

  testWidgets('traduce los rechazos del servidor', (tester) async {
    await _pump(
      tester,
      failure: DioException(
        requestOptions: RequestOptions(),
        message: 'ECF_SEQUENCE_REUSE_BLOCKED',
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('ecf_sequence_from')), '1');
    await tester.enterText(find.byKey(const ValueKey('ecf_sequence_to')), '10');
    await tester.tap(find.byKey(const ValueKey('ecf_sequence_save')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('un número que ya usaste'),
      findsOneWidget,
    );
  });

  testWidgets('sin permiso no consulta ni muestra el formulario', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ecfRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: EcfSequenceRangeSection(canManage: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Numeración de facturas'), findsNothing);
    expect(find.byKey(const ValueKey('ecf_sequence_from')), findsNothing);
  });
}
