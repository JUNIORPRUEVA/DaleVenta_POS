import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/errors/app_error_policy.dart';
import 'package:daleventa_pos/core/errors/user_facing_error.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for `HttpExceptionWithStatus` thrown by
/// `flutter_cache_manager` when a media file returns a non-2xx status.
class _MediaLoadFailure implements Exception {
  _MediaLoadFailure(this.statusCode);

  final int statusCode;

  @override
  String toString() =>
      'HttpException: Invalid statusCode: $statusCode, '
      'uri = https://backend.example.com/uploads/companies/acme/products/x.jpg';
}

FlutterErrorDetails _imageDetails(Object exception) {
  return FlutterErrorDetails(
    exception: exception,
    library: 'image resource service',
    context: ErrorDescription('image failed to load'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppErrorReporter.instance.resetForTesting());

  group('AppErrorPolicy', () {
    test('classifies media 404 as silent', () {
      final text =
          'HttpException: Invalid statusCode: 404, uri = https://host/uploads/a.jpg';

      expect(AppErrorPolicy.isMediaFailure(text), isTrue);
      expect(AppErrorPolicy.isSilent(null, text), isTrue);
    });

    test('classifies NetworkImageLoadException as silent', () {
      const text =
          'NetworkImageLoadException: HTTP request failed, statusCode: 404, '
          'https://host/media/products/1';

      expect(AppErrorPolicy.isSilent(null, text), isTrue);
    });

    test('classifies transient network failures as silent', () {
      const text = 'SocketException: Failed host lookup: backend.example.com';

      expect(AppErrorPolicy.isTransientNetworkFailure(text), isTrue);
      expect(AppErrorPolicy.isSilent(null, text), isTrue);
    });

    test('never treats business API errors as silent', () {
      final error = ApiException.detailed(
        message: 'Stock insuficiente para completar la venta.',
        type: ApiErrorType.badRequest,
      );

      expect(AppErrorPolicy.isSilent(error, 'Stock insuficiente'), isFalse);
    });
  });

  group('UserFacingError', () {
    test('maps status codes to human messages without technical text', () {
      final forbidden = <String>[
        'http',
        'statuscode',
        'exception',
        'endpoint',
        'prisma',
      ];

      final cases = <ApiException, String>{
        ApiException.detailed(
          message: 'boom',
          type: ApiErrorType.forbidden,
        ): 'No tienes permiso para realizar esta acción.',
        ApiException.detailed(
          message: 'boom',
          type: ApiErrorType.unauthorized,
        ): 'Tu sesión expiró. Inicia sesión nuevamente.',
        ApiException.detailed(
          message: 'boom',
          type: ApiErrorType.server,
        ): 'Ocurrió un problema en el servidor. Inténtalo nuevamente.',
        ApiException.detailed(
          message: 'boom',
          type: ApiErrorType.network,
        ): 'No pudimos conectarnos al servidor. Revisa tu conexión.',
      };

      for (final entry in cases.entries) {
        final copy = UserFacingError.from(entry.key);
        expect(copy.message, entry.value);
        expect(copy.title.toLowerCase(), isNot(contains('algo salio mal')));
        for (final marker in forbidden) {
          expect(copy.message.toLowerCase(), isNot(contains(marker)));
          expect(copy.title.toLowerCase(), isNot(contains(marker)));
        }
      }
    });

    test('media copy is marked as silent', () {
      expect(UserFacingError.media().silent, isTrue);
      expect(UserFacingError.media().kind, AppErrorKind.media);
    });
  });

  group('AppErrorReporter', () {
    test('records a media 404 without notifying the user', () {
      AppErrorReporter.instance.recordFlutterError(
        _imageDetails(_MediaLoadFailure(404)),
      );

      expect(AppErrorReporter.instance.lastError.value, isNull);

      final recorded = AppErrorReporter.instance.history.single;
      expect(recorded.silent, isTrue);
      expect(recorded.title, isNot(contains('404')));
      expect(recorded.userMessage, isNot(contains('https://')));
      expect(recorded.endpointUrl, isNull);
    });

    test('many missing images never produce a user notification', () {
      for (var index = 0; index < 20; index++) {
        AppErrorReporter.instance.recordFlutterError(
          _imageDetails(_MediaLoadFailure(404)),
        );
      }

      expect(AppErrorReporter.instance.lastError.value, isNull);
      expect(AppErrorReporter.instance.history.length, 1);
    });

    test('network failure notifies with human copy only once', () {
      final error = ApiException.detailed(
        message: 'No pudimos conectarnos al servidor.',
        type: ApiErrorType.network,
        displayCode: 'NETWORK_UNAVAILABLE',
        technicalDetails:
            'SocketException: Failed host lookup: backend.example.com',
        uri: Uri.parse('https://backend.example.com/api/products'),
        method: 'GET',
        retryable: true,
      );

      AppErrorReporter.instance.record(
        error,
        StackTrace.current,
        context: 'Test',
        dedupeKey: 'network-unavailable',
        retryLabel: 'Reintentar',
      );
      AppErrorReporter.instance.record(
        error,
        StackTrace.current,
        context: 'Test',
        dedupeKey: 'network-unavailable',
        retryLabel: 'Reintentar',
      );

      final details = AppErrorReporter.instance.lastError.value;
      expect(details, isNotNull);
      expect(details!.title, 'Sin conexión');
      expect(details.silent, isFalse);
      expect(details.retryLabel, 'Reintentar');
      expect(details.eventId, 1);
      expect(details.userMessage, isNot(contains('http')));
      expect(details.userMessage, isNot(contains('SocketException')));
      // Technical context stays available for diagnostics only.
      expect(details.technicalDetails, contains('SocketException'));
      expect(details.endpointUrl, contains('https://'));
    });

    test('unknown flutter error uses generic human copy', () {
      AppErrorReporter.instance.recordFlutterError(
        FlutterErrorDetails(
          exception: StateError('unexpected boom'),
          stack: StackTrace.current,
        ),
      );

      final details = AppErrorReporter.instance.lastError.value;
      expect(details, isNotNull);
      expect(details!.title, 'No pudimos completar la operación');
      expect(details.title.toLowerCase(), isNot(contains('algo salio mal')));
    });

    test('render overflow stays silent', () {
      AppErrorReporter.instance.recordFlutterError(
        FlutterErrorDetails(
          exception: FlutterError('A RenderFlex overflowed by 12 pixels'),
          stack: StackTrace.current,
        ),
      );

      expect(AppErrorReporter.instance.lastError.value, isNull);
      expect(AppErrorReporter.instance.history.single.silent, isTrue);
    });
  });
}
