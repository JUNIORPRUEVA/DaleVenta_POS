// Entrypoint EXCLUSIVO de vista previa de los pasos del onboarding.
//
// No lo importa la app: levanta un servidor de preview aislado que muestra
// los pasos 1 a 4 con el tema real y los mismos widgets que la pantalla real.
//
// Uso:
//   flutter run -d web-server --web-port=4602 \
//     -t lib/features/onboarding/presentation/preview/steps_preview.dart
//
//   http://127.0.0.1:4602/?step=1   Datos del negocio
//   http://127.0.0.1:4602/?step=2   Facturación
//   http://127.0.0.1:4602/?step=3   Tu primer producto
//   http://127.0.0.1:4602/?step=4   Listo para vender
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';

void main() {
  final raw = Uri.base.queryParameters['step'];
  final step = int.tryParse(raw ?? '') ?? 1;
  runApp(_StepsPreviewApp(step: step));
}

class _StepsPreviewApp extends StatelessWidget {
  const _StepsPreviewApp({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FullPOS · Onboarding (preview)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: OnboardingStepsPreview(step: step),
    );
  }
}
