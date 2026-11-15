import 'package:daleventa_pos/core/support/support_config.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_managed_setup_offer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usa el contacto del asistente y conserva el mensaje y precio', () {
    final uri = EcfManagedSetupOffer.contactUri;
    expect(uri.scheme, 'https');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/${SupportConfig.whatsappNumber}');
    expect(uri.queryParameters['text'], EcfManagedSetupOffer.message);
    expect(uri.queryParameters['text'], contains('US\$150'));
  });

  for (final width in [320.0, 700.0]) {
    testWidgets('oferta legible y accionable a $width con texto ampliado', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var contacts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: const TextScaler.linear(1.4),
            ),
            child: Scaffold(
              body: EcfManagedSetupOffer(onContact: () => contacts++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Pago único de US\$150'), findsOneWidget);
      await tester.tap(find.text('Consultar por WhatsApp'));
      expect(contacts, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('respeta movimiento reducido sin animación pendiente', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: EcfManagedSetupOffer()),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
