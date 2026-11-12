// Entrypoint EXCLUSIVO de vista previa.
//
// No lo importa la app: sirve para levantar un servidor de preview aislado que
// muestra únicamente la pantalla de bienvenida del onboarding, con el tema real,
// de modo que se pueda iterar el diseño con hot reload sin navegar el flujo.
//
// Uso:
//   flutter run -d web-server --web-port=4601 \
//     -t lib/features/onboarding/presentation/preview/welcome_preview.dart
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const _WelcomePreviewApp());
}

class _WelcomePreviewApp extends StatelessWidget {
  const _WelcomePreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FullPOS · Bienvenida (preview)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: OnboardingWelcomePreview(
        // Fecha ficticia: permite ver la píldora de prueba sin depender del
        // backend.
        trialEndsAt: DateTime(2026, 11, 25),
      ),
    );
  }
}
