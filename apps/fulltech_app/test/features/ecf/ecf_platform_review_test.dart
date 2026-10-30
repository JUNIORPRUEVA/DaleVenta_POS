import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_platform_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_platform_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_platform_review_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Superficie de PLATAFORMA: cola de expedientes para el equipo de Fulltech.
///
/// Lo que se comprueba aquí es el límite de seguridad, no la estética:
///
///  * Un usuario que no es personal de plataforma no ve ningún dato de otras
///    empresas (`403` ⇒ sin acceso).
///  * Un fallo de red no se disfraza de "sin acceso": se propaga como error.
///  * No existe ninguna acción para declarar una aprobación oficial.

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

EcfPlatformRepository _repositoryWith(
  Future<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio()..httpClientAdapter = _FakeHttpClientAdapter(handler);
  return EcfPlatformRepository(dio);
}

const _applicationJson = {
  'companyId': 'c-1',
  'companyName': 'Ferretería Central',
  'state': 'APPLICATION_PENDING',
  'reviewState': 'PENDING_FULLTECH_REVIEW',
  'observations': null,
  'updatedAt': '2026-10-19T10:00:00.000Z',
  'hasOfficialAuthorization': false,
};

Widget _harness({required bool isStaff, List<Map<String, dynamic>> items = const []}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: [
      ecfPlatformStaffProvider.overrideWith((ref) async => isStaff),
      ecfPlatformApplicationsProvider.overrideWith(
        (ref, state) async => EcfPlatformApplicationPage(
          items: items
              .map(EcfPlatformApplication.fromJson)
              .toList(growable: false),
          total: items.length,
          take: 50,
          skip: 0,
        ),
      ),
    ],
    child: const MaterialApp(home: EcfPlatformReviewPage()),
  );
}

void main() {
  group('cliente de plataforma', () {
    test('una respuesta afirmativa del backend confirma la pertenencia', () async {
      final repo = _repositoryWith(
        (options) async {
          expect(options.path, '/ecf/platform/me');
          return _json({'isPlatformStaff': true});
        },
      );
      expect(await repo.isPlatformStaff(), isTrue);
    });

    test('un 403 significa "no es personal", no un error', () async {
      final repo = _repositoryWith(
        (_) async => _json({'message': 'PLATFORM_STAFF_REQUIRED'}, 403),
      );
      expect(await repo.isPlatformStaff(), isFalse);
    });

    test('un 500 no se disfraza de "sin acceso"', () async {
      final repo = _repositoryWith((_) async => _json({'message': 'boom'}, 500));
      await expectLater(repo.isPlatformStaff(), throwsA(isA<DioException>()));
    });

    test('la bandeja envía el filtro de estado y usa el total del servidor', () async {
      final repo = _repositoryWith(
        (options) async {
          expect(options.path, '/ecf/platform/dgii/applications');
          expect(options.queryParameters['state'], 'APPLICATION_PENDING');
          expect(options.queryParameters['take'], 50);
          return _json({
            'total': 1,
            'take': 50,
            'skip': 0,
            'items': [_applicationJson],
          });
        },
      );
      final page = await repo.listApplications(state: 'APPLICATION_PENDING');
      expect(page.total, 1);
      expect(page.items.single.companyName, 'Ferretería Central');
      expect(page.items.single.hasOfficialAuthorization, isFalse);
    });

    test('sin filtro no se envía el parámetro state', () async {
      final repo = _repositoryWith(
        (options) async {
          expect(options.queryParameters.containsKey('state'), isFalse);
          return _json({'total': 0, 'items': <Object>[]});
        },
      );
      final page = await repo.listApplications();
      expect(page.items, isEmpty);
    });

    test('la decisión hace PATCH y no incluye un campo de aprobación', () async {
      late RequestOptions captured;
      final repo = _repositoryWith(
        (options) async {
          captured = options;
          return _json({'state': 'REQUIRES_CORRECTION'});
        },
      );
      await repo.decide(
        companyId: 'c-1',
        state: 'REQUIRES_CORRECTION',
        observations: 'Falta el certificado',
      );
      expect(captured.method, 'PATCH');
      expect(captured.path, '/ecf/platform/dgii/applications/c-1');
      final body = captured.data as Map<String, dynamic>;
      expect(body['state'], 'REQUIRES_CORRECTION');
      expect(body['observations'], 'Falta el certificado');
      expect(body.keys.any((key) => key.toLowerCase().contains('approv')), isFalse);
    });
  });

  group('pantalla de revisión', () {
    testWidgets('sin pertenencia no se muestra ningún expediente', (tester) async {
      await tester.pumpWidget(
        _harness(isStaff: false, items: const [_applicationJson]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sección del equipo de Fulltech'), findsOneWidget);
      expect(find.text('Ferretería Central'), findsNothing);
    });

    testWidgets('con pertenencia se listan los expedientes pendientes', (tester) async {
      await tester.pumpWidget(
        _harness(isStaff: true, items: const [_applicationJson]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ferretería Central'), findsOneWidget);
      expect(find.text('Solicitud enviada'), findsOneWidget);
      // Ninguna acción de aprobación en la cola.
      expect(find.textContaining('Aprobar'), findsNothing);
    });

    testWidgets('una cola vacía lo dice sin inventar filas', (tester) async {
      await tester.pumpWidget(_harness(isStaff: true));
      await tester.pumpAndSettle();

      expect(find.text('No hay expedientes'), findsOneWidget);
    });
  });
}
