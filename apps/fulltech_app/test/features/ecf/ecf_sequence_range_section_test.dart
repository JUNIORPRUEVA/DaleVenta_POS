import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_authorized_sequence_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_sequence_range_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Declaración de la numeración autorizada por la DGII.
///
/// Se prueba lo que puede fallar de verdad: que pida la declaración cuando
/// falta, que no deje guardar sin aceptarla, que no envíe una cantidad que no
/// cuadra con el rango, que envíe primero la autorización y después el rango, y
/// que traduzca los rechazos del servidor.
class _FakeRepository extends EcfRepository {
  _FakeRepository() : super(Dio());

  List<EcfSequenceInfo> existing = const [];
  List<EcfAuthorizedSequence> declared = const [];
  Object? declarationFailure;
  Object? sequenceFailure;
  int declarations = 0;
  int saves = 0;
  int renews = 0;
  String? lastDocumentType;
  int? lastFrom;
  int? lastTo;
  int? lastApproved;
  String? lastAuthorizationNumber;

  @override
  Future<EcfAuthorizedSequencesView> authorizedSequences() async {
    return EcfAuthorizedSequencesView(
      items: declared,
      supportedTypes: const ['E31', 'E34'],
      declarationVersion: 'v1',
      declarationText: 'Declaro que estos datos son los que la DGII autorizó.',
    );
  }

  @override
  Future<List<EcfSequenceInfo>> sequences() async => existing;

  @override
  Future<void> declareAuthorizedSequence({
    required String documentType,
    required String authorizationNumber,
    required int rangeFrom,
    required int rangeTo,
    required int approvedQuantity,
    String? expiresAt,
    required bool declarationAccepted,
  }) async {
    declarations++;
    lastDocumentType = documentType;
    lastAuthorizationNumber = authorizationNumber;
    lastApproved = approvedQuantity;
    if (declarationFailure != null) throw declarationFailure!;
    declared = [
      EcfAuthorizedSequence(
        documentType: documentType,
        authorizationNumber: authorizationNumber,
        rangeFrom: rangeFrom,
        rangeTo: rangeTo,
        approvedQuantity: approvedQuantity,
        declarationVersion: 'v1',
      ),
    ];
  }

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
    if (sequenceFailure != null) throw sequenceFailure!;
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

  @override
  Future<void> renewSequence({
    required String documentType,
    required int startNumber,
    required int endNumber,
    String? validUntil,
  }) async {
    renews++;
    lastDocumentType = documentType;
    lastFrom = startNumber;
    lastTo = endNumber;
    if (sequenceFailure != null) throw sequenceFailure!;
    existing = [
      EcfSequenceInfo(
        id: 'seq-renewed',
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

EcfAuthorizedSequence _declared({
  String documentType = 'E31',
  int rangeFrom = 1,
  int rangeTo = 150,
}) => EcfAuthorizedSequence(
  documentType: documentType,
  authorizationNumber: '6005190128',
  rangeFrom: rangeFrom,
  rangeTo: rangeTo,
  approvedQuantity: rangeTo - rangeFrom + 1,
  declarationVersion: 'v1',
);

Future<_FakeRepository> _pump(
  WidgetTester tester, {
  List<EcfSequenceInfo> existing = const [],
  List<EcfAuthorizedSequence> declared = const [],
  Object? declarationFailure,
  Object? sequenceFailure,
  bool canManage = true,
}) async {
  final repository = _FakeRepository()
    ..existing = existing
    ..declared = declared
    ..declarationFailure = declarationFailure
    ..sequenceFailure = sequenceFailure;

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

Future<void> _fill(
  WidgetTester tester, {
  String authorization = '6005190128',
  String from = '1',
  String to = '150',
  String approved = '150',
  bool accept = true,
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('ecf_dgii_authorization_number')),
    authorization,
  );
  await tester.enterText(find.byKey(const ValueKey('ecf_dgii_from')), from);
  await tester.enterText(find.byKey(const ValueKey('ecf_dgii_to')), to);
  await tester.enterText(
    find.byKey(const ValueKey('ecf_dgii_approved')),
    approved,
  );
  if (accept) {
    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declaration_check')));
    await tester.pump();
  }
}

void main() {
  testWidgets('sin autorización declarada pide los datos de la DGII', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Numeración autorizada por la DGII'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ecf_dgii_authorization_number')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ecf_dgii_from')), findsOneWidget);
    expect(find.byKey(const ValueKey('ecf_dgii_to')), findsOneWidget);
    expect(find.byKey(const ValueKey('ecf_dgii_approved')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ecf_dgii_declaration_check')),
      findsOneWidget,
    );
  });

  testWidgets('sin aceptar la declaración el botón queda deshabilitado', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await _fill(tester, accept: false);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ecf_dgii_declaration_save')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('ecf_dgii_declaration_save')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(repository.declarations, 0);
  });

  testWidgets('una cantidad que no cuadra con el rango no se envía', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await _fill(tester, from: '1', to: '1000', approved: '150');

    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declaration_save')));
    await tester.pumpAndSettle();

    expect(repository.declarations, 0);
    expect(repository.saves, 0);
    expect(find.textContaining('La DGII aprobó 150'), findsOneWidget);
  });

  testWidgets('guarda primero la autorización y después el rango', (
    tester,
  ) async {
    final repository = await _pump(tester);
    await _fill(tester);

    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declaration_save')));
    await tester.pumpAndSettle();

    expect(repository.declarations, 1);
    expect(repository.lastAuthorizationNumber, '6005190128');
    expect(repository.lastApproved, 150);
    expect(repository.saves, 1);
    expect(repository.lastFrom, 1);
    expect(repository.lastTo, 150);
    expect(repository.lastDocumentType, 'E31');
  });

  testWidgets('con autorización y numeración usables muestra el resumen', (
    tester,
  ) async {
    await _pump(tester, declared: [_declared()], existing: [_range()]);

    expect(find.text('Numeración autorizada por la DGII'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ecf_dgii_authorization_number')),
      findsNothing,
    );
    expect(find.textContaining('6005190128'), findsOneWidget);
  });

  testWidgets('declarado: muestra el resumen y ofrece otro tipo', (
    tester,
  ) async {
    await _pump(tester, declared: [_declared()]);
    // E31 está declarado: no se vuelve a pedir. E34 se ofrece como acción.
    expect(find.text('Numeración autorizada por la DGII'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ecf_dgii_authorization_number')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ecf_dgii_declare_another')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declare_another')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ecf_dgii_authorization_number')),
      findsOneWidget,
    );
  });

  testWidgets('traduce el rechazo del servidor al declarar', (tester) async {
    final repository = await _pump(
      tester,
      declarationFailure: Exception(
        'ECF_DGII_SEQUENCE_QUANTITY_MISMATCH: La DGII aprobó 150 comprobantes '
        'y el rango declara 1500.',
      ),
    );
    await _fill(tester);

    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declaration_save')));
    await tester.pumpAndSettle();

    expect(repository.declarations, 1);
    expect(repository.saves, 0);
    expect(find.textContaining('La DGII aprobó 150'), findsOneWidget);
  });

  testWidgets('traduce el rechazo cuando el rango se sale de lo autorizado', (
    tester,
  ) async {
    await _pump(
      tester,
      sequenceFailure: Exception(
        'ECF_SEQUENCE_EXCEEDS_AUTHORIZED: La DGII autorizó del 1 al 150.',
      ),
    );
    await _fill(tester);

    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declaration_save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('La DGII autorizó del 1 al 150'), findsOneWidget);
  });

  testWidgets('sin permiso de gestión no muestra nada', (tester) async {
    await _pump(tester, canManage: false);

    expect(find.text('Numeración autorizada por la DGII'), findsNothing);
  });

  testWidgets('declarado sin rango ofrece registrarlo con lo autorizado', (
    tester,
  ) async {
    final repository = await _pump(
      tester,
      declared: [_declared(documentType: 'E32')],
    );

    expect(
      find.byKey(const ValueKey('ecf_sequence_register_E32')),
      findsOneWidget,
    );
    expect(find.textContaining('Falta registrar la numeración'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('ecf_sequence_register_E32')),
    );
    await tester.pumpAndSettle();

    expect(repository.saves, 1);
    expect(repository.declarations, 0);
    expect(repository.lastDocumentType, 'E32');
    expect(repository.lastFrom, 1);
    expect(repository.lastTo, 150);
  });

  testWidgets('rango agotado ofrece renovar desde el número consumido', (
    tester,
  ) async {
    final repository = await _pump(
      tester,
      declared: [_declared()],
      existing: [_range(remaining: 0)],
    );

    expect(
      find.byKey(const ValueKey('ecf_sequence_renew_E31')),
      findsOneWidget,
    );
    expect(find.textContaining('Se agotaron los números'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ecf_sequence_renew_E31')));
    await tester.pumpAndSettle();

    expect(repository.renews, 1);
    expect(repository.saves, 0);
    expect(repository.lastDocumentType, 'E31');
    // El rango de prueba empieza en 1 con nextNumber=2: se renueva desde 2.
    expect(repository.lastFrom, 2);
    expect(repository.lastTo, 150);
  });

  testWidgets('un rango usable no ofrece registrar ni renovar', (tester) async {
    await _pump(tester, declared: [_declared()], existing: [_range()]);

    expect(
      find.byKey(const ValueKey('ecf_sequence_register_E31')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('ecf_sequence_renew_E31')),
      findsNothing,
    );
  });

  testWidgets('re-declarar con rango activo renueva en vez de registrar', (
    tester,
  ) async {
    // La DGII autorizó otro cupo para un tipo que ya tiene numeración: al
    // volver a declarar, el rango debe renovarse; `register` lo rechazaría con
    // ECF_SEQUENCE_ALREADY_EXISTS.
    final repository = await _pump(
      tester,
      declared: [_declared()],
      existing: [_range()],
    );

    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declare_another')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ecf_dgii_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Factura de Crédito Fiscal (E31)').last);
    await tester.pumpAndSettle();
    await _fill(tester);

    await tester.tap(find.byKey(const ValueKey('ecf_dgii_declaration_save')));
    await tester.pumpAndSettle();

    expect(repository.declarations, 1);
    expect(repository.renews, 1);
    expect(repository.saves, 0);
    expect(repository.lastDocumentType, 'E31');
    expect(repository.lastFrom, 1);
    expect(repository.lastTo, 150);
  });
}
