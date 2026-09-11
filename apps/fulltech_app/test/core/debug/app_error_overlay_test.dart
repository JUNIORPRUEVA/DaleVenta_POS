import 'package:daleventa_pos/core/debug/app_error_overlay.dart';
import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Technical strings that must never be present in the customer surface.
const List<String> _forbiddenInUi = <String>[
  'Ver error',
  'Copiar reporte',
  'Error real',
  'Stack trace',
  'Endpoint',
  'HttpException',
  'DioException',
  'statusCode',
  'https://',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppErrorReporter.instance.resetForTesting());
  tearDown(() => AppErrorReporter.instance.resetForTesting());

  Future<void> pumpOverlay(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(children: const [AppErrorOverlay()]),
        ),
      ),
    );
  }

  void recordNetworkError({Future<void> Function()? onRetry}) {
    AppErrorReporter.instance.record(
      ApiException.detailed(
        message: 'No pudimos conectarnos al servidor.',
        code: null,
        type: ApiErrorType.network,
        displayCode: 'NETWORK_UNAVAILABLE',
        technicalDetails:
            'SocketException: Failed host lookup: backend.example.com',
        uri: Uri.parse('https://backend.example.com/api/products'),
        method: 'GET',
        retryable: true,
      ),
      StackTrace.current,
      context: 'Test',
      retryLabel: 'Reintentar',
      onRetry: onRetry ?? () async {},
    );
  }

  testWidgets('shows one compact notification at the top, without technical '
      'information', (tester) async {
    await pumpOverlay(tester);
    recordNetworkError();
    await tester.pump();
    await tester.pump();

    expect(find.text('Sin conexión'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    final top = tester.getTopLeft(find.text('Sin conexión')).dy;
    expect(
      top,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio / 2),
      reason: 'The notification must appear at the top of the screen',
    );

    for (final forbidden in _forbiddenInUi) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: 'Customer UI must not expose "$forbidden"',
      );
    }
  });

  testWidgets('a single incident produces a single notification', (
    tester,
  ) async {
    await pumpOverlay(tester);
    recordNetworkError();
    await tester.pump();
    await tester.pump();

    expect(find.byType(Material), findsWidgets);
    expect(find.text('Sin conexión'), findsOneWidget);
  });

  testWidgets('close button dismisses the notification', (tester) async {
    await pumpOverlay(tester);
    recordNetworkError();
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sin conexión'), findsNothing);
    expect(AppErrorReporter.instance.lastError.value, isNull);
  });

  testWidgets('ESC dismisses a non-critical notification', (tester) async {
    await pumpOverlay(tester);
    recordNetworkError();
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();

    expect(find.text('Sin conexión'), findsNothing);
  });

  testWidgets('retry runs only the failed operation and clears the '
      'notification', (tester) async {
    var retried = 0;
    await pumpOverlay(tester);
    recordNetworkError(onRetry: () async => retried++);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(retried, 1);
    expect(AppErrorReporter.instance.lastError.value, isNull);
    expect(find.text('Sin conexión'), findsNothing);
  });

  testWidgets('media failures never reach the customer surface', (
    tester,
  ) async {
    await pumpOverlay(tester);
    AppErrorReporter.instance.recordFlutterError(
      FlutterErrorDetails(
        exception: Exception(
          'HttpException: Invalid statusCode: 404, '
          'uri = https://backend.example.com/uploads/companies/acme/p.jpg',
        ),
        library: 'image resource service',
        context: ErrorDescription('image failed to load'),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Sin conexión'), findsNothing);
    expect(find.textContaining('404'), findsNothing);
    expect(find.textContaining('uploads'), findsNothing);
  });
}
