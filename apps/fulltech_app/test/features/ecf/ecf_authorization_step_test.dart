import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_authorization_step.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Último paso del recorrido: la empresa firma la autorización para emitir.
///
/// La DGII ya aprobó la postulación, así que aquí no se pide ningún documento:
/// lo único que falta es el consentimiento de la empresa, registrado con su
/// usuario.
class _FakeRepository extends EcfRepository {
  _FakeRepository() : super(Dio());

  int calls = 0;
  String? lastSource;
  Object? failure;

  @override
  Future<void> recordDgiiAuthorization({
    required String source,
    String? evidenceId,
    String? externalId,
  }) async {
    calls++;
    lastSource = source;
    if (failure != null) throw failure!;
  }
}

Future<_FakeRepository> _pump(
  WidgetTester tester, {
  bool alreadySigned = false,
  bool canAuthorize = true,
}) async {
  final repository = _FakeRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ecfRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: EcfAuthorizationStep(
                canAuthorize: canAuthorize,
                alreadySigned: alreadySigned,
                onSigned: () {},
              ),
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
  testWidgets('explica qué se autoriza y no pide documentos', (tester) async {
    await _pump(tester);

    expect(find.text('Autorización para emitir'), findsOneWidget);
    expect(find.textContaining('Autorizo a FullPOS Cloud'), findsOneWidget);
    // No debe pedir subir nada: la aprobación ya la dio la DGII.
    expect(find.textContaining('evidencia'), findsNothing);
  });

  testWidgets('el botón queda bloqueado hasta aceptar la autorización', (
    tester,
  ) async {
    final repository = await _pump(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ecf_authorization_sign')),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('ecf_authorization_check')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ecf_authorization_sign')));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.lastSource, 'MANUAL_OPERATOR_DECLARATION');
  });

  testWidgets('si ya está firmada muestra el estado y no repite la firma', (
    tester,
  ) async {
    await _pump(tester, alreadySigned: true);

    expect(
      find.byKey(const ValueKey('ecf_authorization_sign')),
      findsNothing,
    );
    expect(find.textContaining('autorizó a FullPOS Cloud'), findsOneWidget);
  });

  testWidgets('sin permiso no deja firmar y lo explica', (tester) async {
    await _pump(tester, canAuthorize: false);

    expect(
      find.textContaining('Solo un administrador'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('ecf_authorization_sign')),
    );
    expect(button.onPressed, isNull);
  });
}
