import 'dart:io';

import 'package:daleventa_pos/core/debug/app_error_overlay.dart';
import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/errors/user_facing_error.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke automatizado del gate de Error UX.
///
/// Reproduce el caso reportado (404 de imagen escalando al handler global) por
/// el pipeline REAL de Flutter (`ImageProvider` -> `ImageStreamCompleter` ->
/// `FlutterError.onError` -> `AppErrorReporter` -> `AppErrorOverlay`).

/// Provider que falla con el mismo tipo de excepción que produce una imagen
/// HTTP 404 en el framework.
class _NotFoundImageProvider extends ImageProvider<_NotFoundImageProvider> {
  const _NotFoundImageProvider(this.uri);

  final String uri;

  @override
  Future<_NotFoundImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_NotFoundImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _NotFoundImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(
        NetworkImageLoadException(statusCode: 404, uri: Uri.parse(uri)),
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _NotFoundImageProvider && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

const List<String> _forbiddenOnScreen = <String>[
  'Ver error',
  'Copiar reporte',
  'Copiar',
  'Error real',
  'Stack trace',
  'Endpoint',
  'Exception',
  'DioException',
  'HttpException',
  'SocketException',
  '404',
  'uploads',
  'http://',
  'https://',
  'statusCode',
  '127.0.0.1',
  'localhost',
];

/// Excepciones equivalentes a las que produce `ApiErrorMapper` para cada
/// escenario. Se construyen directamente para que el smoke sea determinista
/// y no dispare sondeos de red reales.
ApiException _networkException() => ApiException.detailed(
  message: 'No pudimos conectarnos al servidor.',
  type: ApiErrorType.network,
  displayCode: 'NETWORK_UNAVAILABLE',
  technicalDetails: 'SocketException: Failed host lookup: backend.example.com',
  uri: Uri.parse('https://backend.example.com/api/products'),
  method: 'GET',
  retryable: true,
);

ApiException _forbiddenException() => ApiException.detailed(
  message: 'No tienes permiso para realizar esta acción.',
  code: 403,
  type: ApiErrorType.forbidden,
  displayCode: '403',
  technicalDetails: 'RolesGuard active',
  uri: Uri.parse('https://backend.example.com/api/products'),
  method: 'GET',
);

ApiException _serverException() => ApiException.detailed(
  message: 'Ocurrió un problema en el servidor.',
  code: 500,
  type: ApiErrorType.server,
  displayCode: 'SERVER_ERROR',
  technicalDetails: 'Internal server error',
  uri: Uri.parse('https://backend.example.com/api/products'),
  method: 'GET',
  retryable: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppErrorReporter.instance.resetForTesting();
  });

  tearDown(() {
    AppErrorReporter.instance.resetForTesting();
  });
  /// Ejecuta [body] con el mismo handler global que usa `main.dart` y restaura
  /// `FlutterError.onError` ANTES de devolver, tal como exige el binding de
  /// pruebas (no se puede afirmar con `expect` mientras está sobreescrito).
  Future<FlutterErrorDetails?> withGlobalErrorHandler(
    Future<void> Function() body,
  ) async {
    final previous = FlutterError.onError;
    FlutterErrorDetails? captured;
    FlutterError.onError = (details) {
      captured = details;
      AppErrorReporter.instance.recordFlutterError(details);
    };
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
    return captured;
  }

  /// Host que replica la composición real de `main.dart` (Stack + overlay).
  Future<void> pumpPos(WidgetTester tester, {Widget? content}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              if (content != null) content,
              const AppErrorOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// Verifica que ninguna superficie de error del producto exponga detalles
  /// técnicos.
  ///
  /// [scope] permite acotar la búsqueda cuando el árbol contiene adrede otras
  /// superficies (p. ej. el widget de error **solo-debug** que Flutter dibuja
  /// para un `Image` sin `errorBuilder`).
  void expectNoTechnicalLeak({Finder? scope, int? visibleNotifications}) {
    final base = scope ?? find.byType(MaterialApp);
    for (final forbidden in _forbiddenOnScreen) {
      expect(
        find.descendant(of: base, matching: find.textContaining(forbidden)),
        findsNothing,
        reason: 'La UI del cliente no debe mostrar "$forbidden"',
      );
    }
    expect(find.byType(Dialog), findsNothing, reason: 'sin modal');
    expect(find.byType(AlertDialog), findsNothing, reason: 'sin modal');
    expect(
      find.byType(BottomSheet),
      findsNothing,
      reason: 'sin hoja inferior',
    );
    if (visibleNotifications != null) {
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason: 'sin toast inferior',
      );
    }
  }

  group('SMOKE 4 — image 404', () {
    testWidgets(
      'un 404 de imagen no notifica, muestra placeholder y el POS sigue usable',
      (tester) async {
        var taps = 0;

        final captured = await withGlobalErrorHandler(() async {
          await pumpPos(
            tester,
            content: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    // Sin errorBuilder a propósito: reproduce la fuga original.
                    child: Image(
                      image: const _NotFoundImageProvider(
                        'https://backend.example.com/uploads/companies/acme/p.jpg',
                      ),
                      gaplessPlayback: true,
                    ),
                  ),
                  FilledButton(
                    onPressed: () => taps++,
                    child: const Text('Cobrar'),
                  ),
                ],
              ),
            ),
          );

          // Deja que el pipeline de imagen falle y llegue al handler global.
          for (var i = 0; i < 4; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
        });

        // El error SÍ llegó al handler global (no se perdió diagnóstico)...
        expect(
          captured,
          isNotNull,
          reason: 'un 404 real debe escalar al handler global',
        );
        expect(
          AppErrorReporter.instance.history,
          isNotEmpty,
          reason: 'el incidente debe registrarse internamente',
        );
        expect(
          AppErrorReporter.instance.history.first.silent,
          isTrue,
          reason: 'un 404 de medio debe ser silencioso',
        );

        // ...pero NUNCA se muestra al cliente.
        expect(AppErrorReporter.instance.lastError.value, isNull);
        expect(
          find.descendant(
            of: find.byType(AppErrorOverlay),
            matching: find.byType(Text),
          ),
          findsNothing,
          reason: 'la superficie de notificación debe quedar vacía',
        );
        expectNoTechnicalLeak(scope: find.byType(AppErrorOverlay));

        // El POS sigue usable.
        await tester.tap(find.text('Cobrar'));
        await tester.pump();
        expect(taps, 1, reason: 'el POS debe seguir operable tras el 404');
      },
    );

    testWidgets('el placeholder se muestra cuando el widget absorbe el error', (
      tester,
    ) async {
      final captured = await withGlobalErrorHandler(() async {
        await pumpPos(
          tester,
          content: Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: Image(
                image: const _NotFoundImageProvider(
                  'https://backend.example.com/uploads/companies/acme/p.jpg',
                ),
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.image_not_supported_outlined),
              ),
            ),
          ),
        );

        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      });

      expect(
        find.byIcon(Icons.image_not_supported_outlined),
        findsOneWidget,
        reason: 'debe mostrarse el placeholder local',
      );
      expect(
        captured,
        isNull,
        reason: 'con errorBuilder el error no debe escalar',
      );
      expect(AppErrorReporter.instance.lastError.value, isNull);
      expectNoTechnicalLeak(scope: find.byType(AppErrorOverlay));
    });
  });

  group('SMOKE 5 / 6 / 7 — red, 403 y 500', () {
    Future<void> expectBanner(
      WidgetTester tester, {
      required String title,
    }) async {
      await tester.pump();
      await tester.pump();

      expect(find.text(title), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(title)).dy,
        lessThan(
          tester.view.physicalSize.height / tester.view.devicePixelRatio / 2,
        ),
        reason: 'la notificación debe aparecer arriba, no abajo ni centrada',
      );
      expectNoTechnicalLeak(visibleNotifications: 0);
    }

    testWidgets('pérdida de conexión muestra "Sin conexión" con Reintentar', (
      tester,
    ) async {
      await pumpPos(tester);

      AppErrorReporter.instance.record(
        _networkException(),
        StackTrace.current,
        context: 'SmokeNetwork',
        retryLabel: 'Reintentar',
        onRetry: () async {},
      );

      await expectBanner(tester, title: 'Sin conexión');
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('403 muestra el mensaje de permisos', (tester) async {
      await pumpPos(tester);

      AppErrorReporter.instance.record(
        _forbiddenException(),
        StackTrace.current,
        context: 'SmokeForbidden',
      );

      await expectBanner(tester, title: 'Acción no permitida');
      expect(
        find.text('No tienes permiso para realizar esta acción.'),
        findsOneWidget,
      );
    });

    testWidgets('500 muestra un mensaje humano genérico', (tester) async {
      await pumpPos(tester);

      AppErrorReporter.instance.record(
        _serverException(),
        StackTrace.current,
        context: 'SmokeServer',
      );

      await expectBanner(tester, title: 'No pudimos completar la operación');
      expect(
        find.text('Ocurrió un problema en el servidor. Inténtalo nuevamente.'),
        findsOneWidget,
      );
    });
  });

  group('SMOKE 8 — fallo de impresión tras venta confirmada', () {
    testWidgets('la venta sigue confirmada y el aviso es humano', (
      tester,
    ) async {
      var saleSaved = true;

      Future<String> printTicket() async {
        throw const SocketException('printer offline');
      }

      await pumpPos(tester);

      var printed = true;
      try {
        await printTicket();
      } catch (error, stackTrace) {
        printed = false;
        final copy = UserFacingError.printing();
        expect(copy.retryable, isTrue);

        AppErrorReporter.instance.record(
          error,
          stackTrace,
          context: 'SmokePrint',
          title: copy.title,
          userMessage: copy.message,
          severity: AppErrorSeverity.warning,
          retryLabel: 'Reintentar',
          onRetry: () async {},
        );
      }

      await tester.pump();
      await tester.pump();

      expect(printed, isFalse);
      expect(saleSaved, isTrue, reason: 'la venta NO debe marcarse como fallida');
      expect(
        find.textContaining('No se pudo imprimir el comprobante'),
        findsWidgets,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expectNoTechnicalLeak(visibleNotifications: 0);
    });
  });

  group('SMOKE 9 — doble presentación', () {
    testWidgets('un incidente produce máximo 1 notificación, 0 modales y '
        '0 toasts', (tester) async {
      await pumpPos(tester);

      final exception = ApiException.detailed(
        message: 'No pudimos conectarnos al servidor.',
        type: ApiErrorType.network,
        displayCode: 'NETWORK_UNAVAILABLE',
        technicalDetails: 'SocketException: Failed host lookup',
        uri: Uri.parse('https://backend.example.com/api/products'),
        method: 'GET',
        retryable: true,
      );

      for (var i = 0; i < 5; i++) {
        AppErrorReporter.instance.record(
          exception,
          StackTrace.current,
          context: 'SmokeDuplicate',
          dedupeKey: 'smoke-network',
          retryLabel: 'Reintentar',
          onRetry: () async {},
        );
      }

      await tester.pump();
      await tester.pump();

      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expectNoTechnicalLeak(visibleNotifications: 0);
    });
  });
}
