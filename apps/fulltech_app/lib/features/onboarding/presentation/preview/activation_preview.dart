// Entrypoint EXCLUSIVO de vista previa del panel de activación.
//
// No lo importa la app: monta el panel real (el mismo widget que usa la
// aplicación) con un estado de onboarding ficticio, para medir su ancho y
// comprobar el flujo «Ver cómo → columna de ayuda a la izquierda».
//
// Uso:
//   flutter run -d web-server --web-port=4604 \
//     -t lib/features/onboarding/presentation/preview/activation_preview.dart
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/onboarding/application/activation_controller.dart';
import 'package:daleventa_pos/features/onboarding/data/activation_models.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_guide_column.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  // `?done=1` monta todos los apartados completados y abre el panel: sirve para
  // revisar el cierre del asistente (felicitación final) sin tocar datos reales.
  final allDone = Uri.base.queryParameters['done'] == '1';
  runApp(
    ProviderScope(
      overrides: [
        activationControllerProvider.overrideWith(
          _FakeActivationController.new,
        ),
        if (allDone) activationPanelOpenProvider.overrideWith((ref) => true),
      ],
      child: const _ActivationPreviewApp(),
    ),
  );
}

class _FakeActivationController extends ActivationController {
  @override
  Future<ActivationState?> build() async => _fakeState();

  @override
  Future<void> dismiss() async {}

  @override
  Future<void> reopen() async {}

  @override
  Future<void> markWelcomeSeen() async {}

  @override
  Future<void> skipTask(String key) async {}

  @override
  Future<void> restoreTask(String key) async {}

  @override
  Future<void> setTourStep(String key, int step) async {}
}

ActivationTask _task({
  required String key,
  required String title,
  required String description,
  required String actionLabel,
  required String icon,
  required String destination,
  ActivationTaskState state = ActivationTaskState.pending,
}) {
  return ActivationTask(
    key: key,
    phase: 'start',
    title: title,
    description: description,
    minutes: 2,
    actionLabel: actionLabel,
    destination: destination,
    icon: icon,
    optional: false,
    tourSteps: 0,
    tourStep: 0,
    tourSeen: false,
    state: state,
  );
}

ActivationState _fakeState() {
  final allDone = Uri.base.queryParameters['done'] == '1';
  final taskState = allDone
      ? ActivationTaskState.done
      : ActivationTaskState.pending;
  final tasks = [
    _task(
      key: 'products',
      title: 'Registra tus productos',
      description: 'Con tu catálogo cargado, cobrar una venta toma segundos.',
      actionLabel: 'Registrar productos',
      icon: 'box',
      destination: 'catalog',
      state: taskState,
    ),
    _task(
      key: 'firstSale',
      title: 'Haz tu primera venta',
      description: 'Registra una venta de prueba y comprueba el cobro.',
      actionLabel: 'Ir a facturar',
      icon: 'cart',
      destination: 'pos',
      state: taskState,
    ),
    _task(
      key: 'business',
      title: 'Completa los datos de tu empresa',
      description: 'Nombre comercial, RNC y dirección para tus facturas.',
      actionLabel: 'Abrir empresa',
      icon: 'building',
      destination: 'company',
      state: taskState,
    ),
    _task(
      key: 'taxes',
      title: 'Configura impuestos',
      description: 'Define si tus precios llevan ITBIS y con qué tasa.',
      actionLabel: 'Configurar',
      icon: 'percent',
      destination: 'company',
      state: taskState,
    ),
    _task(
      key: 'tickets',
      title: 'Personaliza tus tickets con tu logo',
      description: 'Sube el logo que aparece impreso en cada ticket.',
      actionLabel: 'Personalizar',
      icon: 'printer',
      destination: 'company',
      state: taskState,
    ),
    _task(
      key: 'ecf',
      title: 'Activa la facturación electrónica',
      description: 'Emite comprobantes válidos para la DGII desde el POS.',
      actionLabel: 'Activar',
      icon: 'shield',
      destination: 'ecf',
      state: taskState,
    ),
  ];
  return ActivationState(
    companyId: 'preview',
    required: false,
    welcomeSeen: true,
    dismissed: false,
    allResolved: allDone,
    total: tasks.length,
    done: allDone ? tasks.length : 0,
    skipped: 0,
    pending: allDone ? 0 : tasks.length,
    percent: allDone ? 100 : 0,
    phases: [
      ActivationPhase(
        key: 'start',
        title: 'Primeros pasos',
        subtitle: 'Lo mínimo para empezar a vender',
        total: tasks.length,
        done: allDone ? tasks.length : 0,
        skipped: 0,
        resolved: allDone ? tasks.length : 0,
        complete: allDone,
        tasks: tasks,
      ),
    ],
    tasks: tasks,
    nextTaskKey: allDone ? null : 'products',
  );
}

class _ActivationPreviewApp extends StatelessWidget {
  const _ActivationPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FullPOS · Activación (preview)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _ActivationPreview(),
    );
  }
}

class _ActivationPreview extends ConsumerWidget {
  const _ActivationPreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panelOpen = ref.watch(activationPanelOpenProvider);
    final tourKey = ref.watch(activationTourProvider);
    final state = ref.watch(activationControllerProvider).value;

    ActivationTask? taskByKey(String key) {
      for (final task in state?.tasks ?? const <ActivationTask>[]) {
        if (task.key == key) return task;
      }
      return null;
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: _FakeAppScreen()),
          if (!panelOpen)
            Positioned(
              right: 16,
              bottom: 16,
              child: FilledButton(
                onPressed: () =>
                    ref.read(activationPanelOpenProvider.notifier).state = true,
                child: const Text('Abrir panel'),
              ),
            ),
          if (panelOpen)
            Positioned.fill(
              child: ActivationPanel(
                onClose: () =>
                    ref.read(activationPanelOpenProvider.notifier).state =
                        false,
              ),
            ),
          if (tourKey != null)
            ActivationGuideColumn(
              taskKey: tourKey,
              task: taskByKey(tourKey),
              fallbackDestination: taskByKey(tourKey)?.destination,
              onOpenDestination: (_) =>
                  ref.read(activationTourProvider.notifier).state = null,
              onClose: () =>
                  ref.read(activationTourProvider.notifier).state = null,
            ),
        ],
      ),
    );
  }
}

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
                    'Detalle de la venta (520 px)',
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
