// Entrypoint EXCLUSIVO de vista previa de la guía lateral del onboarding.
//
// No lo importa la app: levanta un servidor de preview aislado que monta la
// columna de ayuda sobre un fondo que simula la pantalla real, para comprobar
// que no hay desenfoque, que la app sigue visible y que la columna ocupa al
// menos el 15 % del ancho.
//
// Uso:
//   flutter run -d web-server --web-port=4603 \
//     -t lib/features/onboarding/presentation/preview/guide_preview.dart
//
//   http://127.0.0.1:4603/                Guía de «Tu primer producto»
//   http://127.0.0.1:4603/?guide=firstSale Guía de «Haz tu primera venta»
//   http://127.0.0.1:4603/?guide=other     Guía genérica de una tarea
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/onboarding/data/activation_models.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_guide_column.dart';
import 'package:flutter/material.dart';

void main() {
  final key = Uri.base.queryParameters['guide'] ?? 'products';
  runApp(_GuidePreviewApp(taskKey: key));
}

ActivationTask _fakeTask(String key, String title, String description) {
  return ActivationTask(
    key: key,
    phase: 'start',
    title: title,
    description: description,
    minutes: 3,
    actionLabel: 'Empezar',
    destination: 'pos',
    icon: 'cart',
    optional: false,
    tourSteps: 0,
    tourStep: 0,
    tourSeen: false,
    state: ActivationTaskState.pending,
  );
}

class _GuidePreviewApp extends StatelessWidget {
  const _GuidePreviewApp({required this.taskKey});

  final String taskKey;

  @override
  Widget build(BuildContext context) {
    final task = switch (taskKey) {
      'firstSale' => _fakeTask(
        'firstSale',
        'Haz tu primera venta',
        'Registra una venta de prueba para confirmar que el cobro funciona.',
      ),
      'products' => _fakeTask(
        'products',
        'Registra tu primer producto',
        'Crea un producto en tu catálogo para poder venderlo.',
      ),
      _ => _fakeTask(
        'company',
        'Completa los datos de tu empresa',
        'Nombre comercial, RNC y dirección para que tus facturas salgan bien.',
      ),
    };

    return MaterialApp(
      title: 'FullPOS · Guía (preview)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: _GuidePreview(taskKey: taskKey, task: task),
    );
  }
}

class _GuidePreview extends StatefulWidget {
  const _GuidePreview({required this.taskKey, required this.task});

  final String taskKey;
  final ActivationTask task;

  @override
  State<_GuidePreview> createState() => _GuidePreviewState();
}

class _GuidePreviewState extends State<_GuidePreview> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _FakeAppScreen()),
          if (_open)
            ActivationGuideColumn(
              taskKey: widget.taskKey,
              task: widget.task,
              onClose: () => setState(() => _open = false),
            ),
          if (!_open)
            Positioned(
              left: 16,
              bottom: 16,
              child: FilledButton(
                onPressed: () => setState(() => _open = true),
                child: const Text('Abrir guía'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fondo que imita la pantalla de Facturación: sirve para comprobar que la
/// guía no difumina ni oscurece la aplicación que queda detrás.
class _FakeAppScreen extends StatelessWidget {
  const _FakeAppScreen();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF1F5F9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            alignment: Alignment.centerLeft,
            child: const Text(
              'Facturación',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (var i = 0; i < 9; i++)
                          Container(
                            width: 168,
                            height: 132,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: const Center(
                              child: Text(
                                'Producto',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 520,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Text(
                    'Detalle de la venta',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
