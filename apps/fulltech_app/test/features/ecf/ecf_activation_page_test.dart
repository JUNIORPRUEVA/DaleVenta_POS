import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_activation_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests de la pantalla de ACTIVACIÓN e-CF.
///
/// La pantalla no decide qué está hecho: lo copia del motor del backend. Aquí se
/// fija la regla que evita prometer trabajo inexistente — el botón solo se
/// habilita cuando el backend declara algún paso `executable`, y los pasos que
/// dependen del cliente remiten al asistente.

/// Devuelve respuestas enlatadas según el path pedido y registra las llamadas.
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
      return ResponseBody.fromString('{}', 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _step({
  required String key,
  required String label,
  required String className,
  required String status,
  required bool resolved,
  required bool executable,
  String? awaiting,
}) {
  return <String, dynamic>{
    'key': key,
    'stepKey': key,
    'label': label,
    'mandatory': true,
    'className': className,
    'status': status,
    'resolved': resolved,
    'executable': executable,
    'awaiting': awaiting,
  };
}

/// Vista con tres pasos: uno resuelto, uno del cliente y uno del proveedor.
/// `providerExecutable` decide si el motor tiene algo que ejecutar por su cuenta.
Map<String, dynamic> _view({
  required String stage,
  required bool providerExecutable,
}) {
  return <String, dynamic>{
    'companyId': 'company-a',
    'transport': 'SIMULATED',
    'realTransportEnabled': false,
    'summary': <String, dynamic>{
      'total': 3,
      'resolvedCount': 1,
      'percent': 33,
      'awaitingClient': <String>['REQUIREMENTS'],
      'awaitingAuthority': <String>[],
      'stage': stage,
    },
    'steps': <Map<String, dynamic>>[
      _step(
        key: 'FISCAL_CONFIG',
        label: 'Datos fiscales de la empresa',
        className: 'AUTOMATIC_LOCAL',
        status: 'COMPLETED',
        resolved: true,
        executable: false,
      ),
      _step(
        key: 'REQUIREMENTS',
        label: 'Requisitos y documentación',
        className: 'CLIENT_ACTION',
        status: 'PENDING',
        resolved: false,
        executable: false,
        awaiting: 'Necesitamos un dato o un acto tuyo para continuar.',
      ),
      _step(
        key: 'SERVICE_URLS',
        label: 'URLs de servicio',
        className: 'PROVIDER_WAIT',
        status: 'PENDING',
        resolved: false,
        executable: providerExecutable,
        awaiting: 'En manos del proveedor. El sistema reintenta solo.',
      ),
    ],
  };
}

Widget _harness(Dio dio) {
  return ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: const MaterialApp(home: EcfActivationPage()),
  );
}

Dio _dio(_CannedAdapter adapter) => Dio()..httpClientAdapter = adapter;

FilledButton _buttonOf(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Activar facturación electrónica'),
  );
}

void main() {
  testWidgets(
    'bloqueado en el cliente: no ofrece ejecutar y remite al asistente',
    (tester) async {
      final adapter = _CannedAdapter({
        '/ecf/dgii/activation': _view(
          stage: 'BLOCKED_ON_CLIENT',
          providerExecutable: false,
        ),
      });

      await tester.pumpWidget(_harness(_dio(adapter)));
      await tester.pumpAndSettle();

      expect(find.text('Necesita tu intervención'), findsOneWidget);
      expect(find.text('1 de 3 pasos · 33 %'), findsOneWidget);

      // Nada que avanzar: el botón no promete una acción que el backend no hará.
      expect(_buttonOf(tester).onPressed, isNull);
      expect(
        find.textContaining('no hay ningún paso que el sistema'),
        findsOneWidget,
      );

      // El paso del cliente sí ofrece el camino para resolverlo.
      expect(find.widgetWithText(TextButton, 'Completar'), findsOneWidget);
      expect(adapter.calls, <String>['GET /ecf/dgii/activation']);
    },
  );

  testWidgets(
    'con un paso ejecutable: activa de verdad y refresca el avance',
    (tester) async {
      final adapter = _CannedAdapter({
        '/ecf/dgii/activation': _view(
          stage: 'RUNNING',
          providerExecutable: true,
        ),
        '/ecf/dgii/activation/start': _view(
          stage: 'BLOCKED_ON_PROVIDER',
          providerExecutable: true,
        ),
      });

      await tester.pumpWidget(_harness(_dio(adapter)));
      await tester.pumpAndSettle();

      expect(find.text('En proceso'), findsOneWidget);
      expect(_buttonOf(tester).onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Activar facturación electrónica'));
      await tester.pumpAndSettle();

      expect(adapter.calls, <String>[
        'GET /ecf/dgii/activation',
        'POST /ecf/dgii/activation/start',
      ]);
      expect(find.text('En manos del proveedor'), findsOneWidget);
    },
  );
}
