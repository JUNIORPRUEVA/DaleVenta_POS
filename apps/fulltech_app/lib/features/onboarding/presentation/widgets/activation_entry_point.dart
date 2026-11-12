import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_provider.dart';
import '../../../../core/routing/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/activation_controller.dart';
import '../../data/activation_models.dart';
import 'activation_guide_column.dart';
import 'activation_panel.dart';
import 'activation_segmented_progress.dart';
import 'activation_steps.dart';
import 'activation_welcome_card.dart';

/// Punto de entrada global del onboarding de activación.
///
/// Se monta por encima del árbol autenticado, igual que el asistente de IA, de
/// modo que el acceso al panel está disponible en cualquier pantalla sin tocar
/// cada una de ellas.
class ActivationEntryPoint extends ConsumerStatefulWidget {
  const ActivationEntryPoint({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ActivationEntryPoint> createState() =>
      _ActivationEntryPointState();
}

class _ActivationEntryPointState extends ConsumerState<ActivationEntryPoint> {
  bool _welcomeDismissedThisSession = false;
  bool _autoOpenEvaluated = false;

  /// Se escucha al router para saber cuándo cambia la ruta: sin esto, el panel
  /// no podría reabrirse al volver de otra pantalla.
  Listenable? _routeListenable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _routeListenable = ref.read(routerProvider).routerDelegate;
        _routeListenable!.addListener(_onRouteChanged);
      } catch (_) {
        // Router no disponible todavía: el retorno queda inactivo.
      }
    });
  }

  void _onRouteChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _routeListenable?.removeListener(_onRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final async = ref.watch(activationControllerProvider);
    final state = async.value;
    final panelOpen = ref.watch(activationPanelOpenProvider);
    final tourKey = ref.watch(activationTourProvider);
    final returnRoute = ref.watch(activationReturnRouteProvider);
    final returnArmed = ref.watch(activationReturnArmedProvider);

    if (!auth.isAuthenticated || state == null) return widget.child;

    // El usuario abrió una pantalla desde el asistente. Primero se confirma que
    // ya está en el destino (se «arma» el retorno) y solo después, al volver a
    // la ruta de origen, se reabre el panel donde estaba.
    if (returnRoute != null) {
      final path = _currentPath(ref);
      if (!returnArmed && path.isNotEmpty && path != returnRoute) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(activationReturnArmedProvider.notifier).state = true;
        });
      } else if (returnArmed && path == returnRoute && !panelOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(activationReturnRouteProvider.notifier).state = null;
          ref.read(activationReturnArmedProvider.notifier).state = false;
          ref.read(activationPanelOpenProvider.notifier).state = true;
          // Los datos pueden haber cambiado en la pantalla de destino: al
          // volver se relee el avance para que el paso guardado aparezca hecho.
          unawaited(ref.read(activationControllerProvider.notifier).refresh());
        });
      }
    }

    // Auto-apertura única: el backend recuerda que el usuario ya cerró el panel.
    if (!_autoOpenEvaluated) {
      _autoOpenEvaluated = true;
      final shouldOpen = state.shouldAutoOpen && !state.shouldWelcome;
      if (shouldOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(activationPanelOpenProvider.notifier).state = true;
        });
      }
    }

    // El asistente se retira en cuanto no queda ningún apartado pendiente. Se
    // usa el mismo criterio que el panel (`activationStepGroups`) y no el
    // `allResolved` del backend: cuando solo faltaban partes recomendadas de un
    // apartado ya resuelto (logo, impuestos), el botón seguía en pantalla
    // anunciando «0 pasos pendientes» y el asistente no terminaba nunca.
    final pendingSteps = activationPendingSteps(state);

    final showWelcome =
        state.shouldWelcome &&
        pendingSteps > 0 &&
        !_welcomeDismissedThisSession &&
        !panelOpen &&
        tourKey == null;

    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 900;
    // En ventanas bajas (p. ej. 1264x681 con escalado al 200 % → 340 px
    // lógicos) el carrito ocupa el pie de la pantalla y la píldora tapaba una
    // fila de productos. Se reduce a un anillo de 36 px anclado al borde
    // izquierdo, centrado en vertical: zona de margen del grid, nunca sobre el
    // carrito, el cobro ni la barra de tickets. Las posiciones se derivan del
    // tamaño disponible, no de coordenadas fijas.
    final compactTrigger = size.height < 480;

    return Stack(
      children: [
        widget.child,
        if (!panelOpen && !showWelcome && pendingSteps > 0 && tourKey == null)
          Positioned(
            left: compactTrigger ? 8 : null,
            right: compactTrigger ? null : (isMobile ? 12 : 16),
            top: compactTrigger
                ? (size.height * 0.5 - 18).clamp(8.0, double.infinity)
                : null,
            bottom: compactTrigger ? null : (isMobile ? 84 : 16),
            child: _ActivationTrigger(
              state: state,
              compact: compactTrigger,
              onTap: () {
                ref.read(activationPanelOpenProvider.notifier).state = true;
                unawaited(
                  ref.read(activationControllerProvider.notifier).reopen(),
                );
              },
            ),
          ),
        if (panelOpen)
          Positioned.fill(
            child: ActivationPanel(
              onClose: () {
                ref.read(activationPanelOpenProvider.notifier).state = false;
              },
            ),
          ),
        if (showWelcome) Positioned.fill(child: _buildWelcome(pendingSteps)),
        // La ayuda se abre como columna pegada al borde izquierdo, sin fondo
        // oscuro ni desenfoque: la pantalla sigue visible e interactiva para
        // poder ejecutar los pasos mientras se leen.
        if (tourKey != null)
          Builder(
            builder: (context) {
              final task = _taskByKey(state, tourKey);
              return ActivationGuideColumn(
                taskKey: tourKey,
                task: task,
                fallbackDestination: task?.destination,
                onOpenDestination: (destination) {
                  final route = activationRouteFor(destination);
                  if (route == null) return;
                  // Cierra la guía y abre la pantalla real del paso. Al volver,
                  // el asistente se reabre donde estaba.
                  ref.read(activationReturnRouteProvider.notifier).state = ref
                      .read(routerProvider)
                      .routerDelegate
                      .currentConfiguration
                      .uri
                      .path;
                  ref.read(activationReturnArmedProvider.notifier).state =
                      false;
                  ref.read(activationTourProvider.notifier).state = null;
                  ref.read(activationPanelOpenProvider.notifier).state = false;
                  ref.read(routerProvider).go(route);
                },
                onClose: () {
                  ref.read(activationTourProvider.notifier).state = null;
                },
              );
            },
          ),
      ],
    );
  }

  /// Tarea real del estado, para que la guía muestre su título y su
  /// descripción cuando no tenga un recorrido escrito a mano.
  ActivationTask? _taskByKey(ActivationState state, String key) {
    for (final phase in state.phases) {
      for (final task in phase.tasks) {
        if (task.key == key) return task;
      }
    }
    return null;
  }

  /// Ruta actual según el router. Devuelve cadena vacía si no está listo.
  String _currentPath(WidgetRef ref) {
    try {
      final router = ref.watch(routerProvider);
      return router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  Widget _buildWelcome(int pendingSteps) {
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
        ),
        Positioned.fill(
          child: ActivationWelcomeCard(
            companyName:
                ref.read(authStateProvider).user?.companyName ?? 'tu negocio',
            remainingTasks: pendingSteps,
            onStart: () {
              setState(() => _welcomeDismissedThisSession = true);
              unawaited(
                ref
                    .read(activationControllerProvider.notifier)
                    .markWelcomeSeen(),
              );
              ref.read(activationPanelOpenProvider.notifier).state = true;
            },
            onLater: () {
              setState(() => _welcomeDismissedThisSession = true);
              unawaited(
                ref
                    .read(activationControllerProvider.notifier)
                    .markWelcomeSeen()
                    .then(
                      (_) => ref
                          .read(activationControllerProvider.notifier)
                          .dismiss(),
                    ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Acceso visible y permanente mientras queden pasos.
class _ActivationTrigger extends StatelessWidget {
  const _ActivationTrigger({
    required this.state,
    required this.onTap,
    this.compact = false,
  });

  final ActivationState state;
  final VoidCallback onTap;

  /// Versión reducida para ventanas con poco espacio vertical: solo el anillo
  /// de progreso en un círculo de 36 px.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pendingSteps = activationPendingSteps(state);
    final groups = activationStepGroups(state);
    final doneSteps = groups.where((group) => group.isDone).length;
    final totalSteps = groups.length;
    if (compact) {
      return Semantics(
        button: true,
        label:
            'Activa tu FullPOS, $pendingSteps pasos pendientes. Abrir el asistente.',
        // Sin `onTap` el nodo se anuncia como botón pero deja de ser accionable
        // (ni lector de pantalla ni automatización podían abrir el panel).
        onTap: onTap,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: AppColors.shadow,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              // El indicador aporta su propio nodo `progressbar`; se excluye
              // para que el accesible sea el botón contenedor con su etiqueta.
              child: ExcludeSemantics(
                child: ActivationProgressRing(
                  done: doneSteps,
                  total: totalSteps,
                  size: 18,
                  strokeWidth: 2.2,
                  animated: true,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label:
          'Activa tu FullPOS, $pendingSteps pasos pendientes. Abrir el asistente.',
      // Ver nota de la variante compacta: sin `onTap` el botón no responde.
      onTap: onTap,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        elevation: 3,
        shadowColor: AppColors.shadow,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.fromLTRB(9, 0, 13, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: ActivationProgressRing(
                    done: doneSteps,
                    total: totalSteps,
                    size: 15,
                    strokeWidth: 2,
                    animated: true,
                  ),
                ),
                const SizedBox(width: 7),
                const Text(
                  'Activa tu FullPOS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$pendingSteps',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
