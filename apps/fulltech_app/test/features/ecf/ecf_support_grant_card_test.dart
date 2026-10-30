import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_support_grant_card.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests de la tarjeta de ASISTENCIA a Fulltech.
///
/// Fijan las reglas que el backend también impone, para que la interfaz no
/// prometa algo distinto de lo que ocurre:
///
///  * Sin concesión, la empresa ve explícitamente que Fulltech NO tiene acceso.
///  * Con concesión, se muestra hasta cuándo y qué alcance exacto tiene.
///  * El botón de conceder desaparece cuando ya hay una activa: el backend
///    rechazaría una segunda con `ECF_SUPPORT_GRANT_ALREADY_ACTIVE`.

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  final List<String> calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls.add('${options.method} ${options.path}');
    final body = responses[options.path];
    if (body == null) {
      return ResponseBody.fromString(
        '{}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _grants(List<Map<String, dynamic>> items) {
  return <String, dynamic>{'companyId': 'company-1', 'items': items};
}

Map<String, dynamic> _grant({
  required String id,
  required List<String> scopes,
  required bool active,
  bool revoked = false,
  bool expired = false,
}) {
  final now = DateTime.now().toUtc();
  return <String, dynamic>{
    'id': id,
    'scopes': scopes,
    'reason': null,
    'createdAt': now.subtract(const Duration(days: 1)).toIso8601String(),
    'expiresAt': (active
            ? now.add(const Duration(days: 6))
            : now.subtract(const Duration(days: 1)))
        .toIso8601String(),
    'revokedAt': revoked ? now.toIso8601String() : null,
    'active': active,
    'revoked': revoked,
    'expired': expired,
  };
}

Widget _harness(Dio dio, {bool canManage = true}) {
  return ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: EcfSupportGrantCard(canManage: canManage),
        ),
      ),
    ),
  );
}

Dio _dio(_CannedAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  testWidgets('sin concesión activa: declara que Fulltech no tiene acceso', (
    tester,
  ) async {
    final adapter = _CannedAdapter({
      '/ecf/dgii/support-grants': _grants(const []),
    });

    await tester.pumpWidget(_harness(_dio(adapter)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No hay ninguna asistencia activa'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Conceder asistencia'),
      findsOneWidget,
    );
    expect(find.text('Revocar ahora'), findsNothing);
    expect(adapter.calls, <String>['GET /ecf/dgii/support-grants']);
  });

  testWidgets('con concesión activa: muestra alcance, caducidad y permite revocar', (
    tester,
  ) async {
    final adapter = _CannedAdapter({
      '/ecf/dgii/support-grants': _grants([
        _grant(
          id: 'grant-1',
          scopes: const ['VIEW_DOSSIER', 'REVIEW_EVIDENCE'],
          active: true,
        ),
      ]),
    });

    await tester.pumpWidget(_harness(_dio(adapter)));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Asistencia activa hasta'),
      findsOneWidget,
    );
    // Los alcances se traducen a lenguaje de negocio, no a claves técnicas.
    expect(find.textContaining('Ver el expediente'), findsOneWidget);
    expect(find.textContaining('Revisar evidencias'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Revocar ahora'), findsOneWidget);
    // No se ofrece conceder una segunda: el backend la rechazaría.
    expect(
      find.widgetWithText(FilledButton, 'Conceder asistencia'),
      findsNothing,
    );
  });

  testWidgets('las concesiones cerradas aparecen en el historial como revocadas', (
    tester,
  ) async {
    final adapter = _CannedAdapter({
      '/ecf/dgii/support-grants': _grants([
        _grant(
          id: 'grant-old',
          scopes: const ['VIEW_DOSSIER'],
          active: false,
          revoked: true,
        ),
      ]),
    });

    await tester.pumpWidget(_harness(_dio(adapter)));
    await tester.pumpAndSettle();

    expect(find.text('Ver historial'), findsOneWidget);
    await tester.tap(find.text('Ver historial'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Revocada'), findsOneWidget);
    // Una concesión cerrada no habilita nada: sigue sin haber acceso activo.
    expect(
      find.textContaining('No hay ninguna asistencia activa'),
      findsOneWidget,
    );
  });

  testWidgets('sin permiso de gestión no ofrece conceder ni revocar', (
    tester,
  ) async {
    final adapter = _CannedAdapter({
      '/ecf/dgii/support-grants': _grants(const []),
    });

    await tester.pumpWidget(_harness(_dio(adapter), canManage: false));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Conceder asistencia'),
      findsNothing,
    );
    expect(find.text('Revocar ahora'), findsNothing);
    // El estado sigue siendo visible: informar no es gestionar.
    expect(
      find.textContaining('No hay ninguna asistencia activa'),
      findsOneWidget,
    );
  });

  // ---------------------------------------------------------------------
  // Layout en pantallas estrechas.
  //
  // Las pruebas de arriba solo comprueban contenido. Un desbordamiento de
  // píxeles no rompe ninguna de esas aserciones, pero sí la pantalla: aquí se
  // renderiza a 320 px de ancho y se exige que no se registre ninguna
  // excepción de layout.
  // ---------------------------------------------------------------------

  void useNarrowScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('a 320 px: estado activo + historial no desborda', (tester) async {
    useNarrowScreen(tester, const Size(320, 568));

    final adapter = _CannedAdapter({
      '/ecf/dgii/support-grants': _grants([
        _grant(
          id: 'grant-1',
          scopes: const ['VIEW_DOSSIER', 'REVIEW_EVIDENCE'],
          active: true,
        ),
        _grant(
          id: 'grant-old',
          scopes: const ['VIEW_DOSSIER'],
          active: false,
          revoked: true,
        ),
      ]),
    });

    await tester.pumpWidget(_harness(_dio(adapter)));
    await tester.pumpAndSettle();

    // El caso más poblado: botón de revocar + botón de historial a la vez.
    expect(find.widgetWithText(OutlinedButton, 'Revocar ahora'), findsOneWidget);
    expect(find.text('Ver historial'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Ver historial'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Revocada'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 320 px: el diálogo de concesión no desborda', (tester) async {
    useNarrowScreen(tester, const Size(320, 568));

    final adapter = _CannedAdapter({
      '/ecf/dgii/support-grants': _grants(const []),
    });

    await tester.pumpWidget(_harness(_dio(adapter)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Conceder asistencia'));
    await tester.pumpAndSettle();

    // Los tres alcances, las duraciones y el campo de motivo deben caber.
    expect(find.text('Conceder asistencia a Fulltech'), findsOneWidget);
    expect(find.text('Ver el expediente'), findsOneWidget);
    expect(find.text('30 días'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
