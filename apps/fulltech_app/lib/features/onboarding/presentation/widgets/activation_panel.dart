import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/routing/app_router.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../application/activation_controller.dart';
import '../../data/activation_models.dart';
import 'activation_segmented_progress.dart';
import 'activation_steps.dart';
import 'activation_task_tile.dart';

/// Ruta destino de cada tarea. El backend envía una clave semántica y el
/// cliente decide a qué pantalla propia corresponde.
String? activationRouteFor(String destination) {
  switch (destination) {
    case 'pos':
      return Routes.cotizaciones;
    case 'catalog':
      return Routes.catalogo;
    case 'company':
      return Routes.configuracionEmpresa;
    // Impuestos y el logo se configuran dentro de Configuración › Empresa.
    // «Parámetros» es una ficha informativa y no contiene ninguno de los dos.
    case 'taxes':
    case 'tickets':
      return Routes.configuracionEmpresa;
    case 'ecf':
      return Routes.ecfConfig;
    default:
      return null;
  }
}

/// Onboarding de activación «Activa tu FullPOS».
///
/// Panel de altura completa: rail derecho en escritorio, hoja inferior en
/// móvil. Deliberadamente compacto — cabecera de 56 px, tarjetas de 12 px de
/// radio y filas de 44 px.
class ActivationPanel extends ConsumerStatefulWidget {
  const ActivationPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<ActivationPanel> createState() => _ActivationPanelState();
}

final class _ActivationPanelState extends ConsumerState<ActivationPanel> {
  bool _busy = false;

  /// Apartado abierto. `null` con [_stepTouched] = `true` significa «ninguno».
  String? _openStepKey;
  bool _stepTouched = false;

  /// Tarea abierta dentro del apartado de empresa (tiene varias partes).
  bool _taskTouched = false;
  String? _openTaskKey;

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(activationControllerProvider);
    final state = asyncState.value;
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 900;
    // Mismo criterio que la columna de detalle de ventas de Facturación
    // (`_DesktopQuotePanel`: 31 % del ancho, entre 500 y 550 px). Así el panel
    // de activación deja de ser un riel estrecho y se lee con la misma holgura
    // que el resto de paneles laterales de la aplicación.
    final panelWidth = isMobile
        ? size.width
        : (size.width * 0.31).clamp(500.0, 550.0).clamp(0.0, size.width);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.16)),
          ),
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: panelWidth,
          child: isMobile
              ? _MobileSheetFrame(child: _buildBody(state, asyncState))
              : _DesktopRailFrame(child: _buildBody(state, asyncState)),
        ),
      ],
    );
  }

  void _handleClose() {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onClose();
    unawaited(ref.read(activationControllerProvider.notifier).dismiss());
  }

  Widget _buildBody(
    ActivationState? state,
    AsyncValue<ActivationState?> async,
  ) {
    if (async.isLoading && state == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (state == null) {
      return _EmptyState(onClose: widget.onClose);
    }
    final groups = activationStepGroups(state);
    final pendingSteps = groups.where((group) => group.isPending).length;
    final doneSteps = groups.where((group) => group.isDone).length;

    // Sin pasos pendientes el asistente ya cumplió su función —se completaron o
    // se omitieron—, así que deja de listar apartados, felicita al usuario y se
    // retira solo. Antes se quedaba abierto como si aún faltara trabajo.
    if (pendingSteps == 0) {
      return _CompletionCelebration(groups: groups, onClose: _handleClose);
    }

    // Abierto por defecto: el primer apartado con algo pendiente.
    final firstPending = groups.firstWhere(
      (group) => group.isPending,
      orElse: () => groups.last,
    );
    final openKey = _stepTouched ? _openStepKey : firstPending.key;

    return Column(
      children: [
        _Header(
          pendingSteps: pendingSteps,
          doneSteps: doneSteps,
          totalSteps: groups.length,
          onClose: _handleClose,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              for (final group in groups) ...[
                _StepCard(
                  group: group,
                  expanded: group.key == openKey,
                  isCurrent: group.key == firstPending.key,
                  busy: _busy,
                  openTaskKey: _taskTouched ? _openTaskKey : null,
                  onToggleStep: () => _toggleStep(group.key),
                  onToggleTask: _toggleTask,
                  onAction: (task) => _runAction(task),
                  onSkip: (task) => _skip(task),
                  onRestore: (task) => _restore(task),
                  onTour: (task) => _startTour(task),
                  onOpenEcf: () => _openDestination('company'),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        // En pantallas muy bajas (p. ej. 1264x681 con escalado al 200 %, que
        // son ~340 px lógicos) el pie quita espacio útil a las tareas. Se
        // oculta para que el contenido respire.
        if (MediaQuery.sizeOf(context).height >= 420) _Footer(state: state),
      ],
    );
  }

  void _toggleStep(String key) {
    // Al cambiar de apartado se desmonta contenido con botones que pueden
    // tener el foco; se libera antes de reconstruir.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _stepTouched = true;
      _openStepKey = _openStepKey == key ? null : key;
    });
  }

  void _toggleTask(ActivationTask task) {
    // Al cambiar de tarea se desmonta el cuerpo de la anterior. Si un botón de
    // ese cuerpo tenía el foco, la traversal de foco intenta leer el
    // renderObject de un elemento ya inactivo y lanza
    // "Cannot get renderObject of inactive element". Se libera el foco antes.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _taskTouched = true;
      _openTaskKey = _openTaskKey == task.key ? null : task.key;
    });
  }

  /// Cierra el asistente y abre la pantalla real del paso.
  ///
  /// Marca que el usuario viene del asistente para que, al volver con
  /// «Regresar», el panel se reabra en el mismo punto.
  void _openDestination(String destination) {
    final route = activationRouteFor(destination);
    if (route == null) return;
    // Recuerda la pantalla de origen: al volver a ella, el asistente se reabre
    // en el mismo punto (pero no en la pantalla de destino).
    ref.read(activationReturnRouteProvider.notifier).state = ref
        .read(routerProvider)
        .routerDelegate
        .currentConfiguration
        .uri
        .path;
    ref.read(activationReturnArmedProvider.notifier).state = false;
    widget.onClose();
    if (!mounted) return;
    // El panel se monta fuera del Navigator: se navega con el router del
    // provider, no con `context.go`, que no encontraría el GoRouter.
    ref.read(routerProvider).go(route);
  }

  Future<void> _runAction(ActivationTask task) async {
    _openDestination(task.destination);
  }

  Future<void> _startTour(ActivationTask task) async {
    widget.onClose();
    ref.read(activationTourProvider.notifier).state = task.key;
  }

  Future<void> _skip(ActivationTask task) async {
    setState(() => _busy = true);
    await ref.read(activationControllerProvider.notifier).skipTask(task.key);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore(ActivationTask task) async {
    setState(() => _busy = true);
    await ref.read(activationControllerProvider.notifier).restoreTask(task.key);
    if (mounted) setState(() => _busy = false);
  }
}

class _DesktopRailFrame extends StatelessWidget {
  const _DesktopRailFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.border)),
        ),
        child: child,
      ),
    );
  }
}

class _MobileSheetFrame extends StatelessWidget {
  const _MobileSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.pendingSteps,
    required this.doneSteps,
    required this.totalSteps,
    required this.onClose,
  });

  final int pendingSteps;
  final int doneSteps;
  final int totalSteps;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final progress = totalSteps == 0
        ? 0.0
        : (doneSteps / totalSteps).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.rocket_launch_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activa tu FullPOS',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _subtitle(),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Sin `tooltip`: este panel se monta por encima del Navigator (en
              // el `builder` de MaterialApp), así que no tiene un `Overlay`
              // ancestro y un Tooltip rompería el árbol. La etiqueta accesible
              // se declara con Semantics, que no depende del Overlay.
              Semantics(
                button: true,
                label: 'Cerrar el asistente de activación',
                child: IconButton(
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: AppColors.textMuted,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Avance visible: cuántos pasos ya están hechos.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppColors.primarySoft,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$doneSteps de $totalSteps completados',
            style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              color: AppColors.textMuted.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    if (pendingSteps == 1) return 'Te queda 1 paso para estar listo.';
    return 'Te quedan $pendingSteps pasos para estar listo.';
  }
}

/// Cierre del asistente.
///
/// Cuando ya no queda ningún apartado pendiente —porque se completaron o
/// porque el usuario los omitió— el panel deja de listar pasos: felicita al
/// usuario con lo que realmente consiguió y se retira solo. El texto se deriva
/// del estado real, así que nunca afirma algo que no se hizo.
class _CompletionCelebration extends StatefulWidget {
  const _CompletionCelebration({required this.groups, required this.onClose});

  final List<ActivationStepGroup> groups;
  final VoidCallback onClose;

  @override
  State<_CompletionCelebration> createState() => _CompletionCelebrationState();
}

class _CompletionCelebrationState extends State<_CompletionCelebration>
    with SingleTickerProviderStateMixin {
  /// Tiempo que la felicitación permanece antes de retirar el asistente.
  static const Duration _autoCloseDelay = Duration(seconds: 7);

  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  Timer? _autoClose;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _fade = _entrance.drive(CurveTween(curve: Curves.easeOutCubic));
    _scale = _fade.drive(Tween<double>(begin: 0.88, end: 1));
    _entrance.forward();
    // Es un mensaje informativo: no obliga al usuario a cerrar nada.
    _autoClose = Timer(_autoCloseDelay, widget.onClose);
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = <String, bool>{
      for (final group in widget.groups) group.key: group.isDone,
    };
    final sells = done['products'] == true && done['firstSale'] == true;
    final companyReady = done['company'] == true;

    final achievements = <String>[
      if (done['products'] == true)
        'Ya sabes registrar productos y controlar tu inventario.',
      if (done['firstSale'] == true)
        'Ya sabes cobrar y entregar el comprobante a tus clientes.',
      if (companyReady)
        'Los datos de tu empresa están listos para tus documentos.',
      if (done['ecf'] == true) 'Tu facturación electrónica quedó activada.',
    ];

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
            child: Semantics(
              button: true,
              label: 'Cerrar el asistente de activación',
              child: IconButton(
                onPressed: widget.onClose,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: AppColors.textMuted,
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
        ),
        Expanded(
          // Centrado vertical cuando hay espacio (panel de escritorio) y
          // desplazable cuando la ventana es baja, sin desbordar.
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 32).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: FadeTransition(
                      opacity: _fade,
                      child: ScaleTransition(
                        scale: _scale,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: AppColors.primarySoft,
                                shape: BoxShape.circle,
                              ),
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: <Color>[
                                      AppColors.primary,
                                      AppColors.primaryDark,
                                    ],
                                  ),
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  size: 34,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              sells ? '¡Felicidades!' : 'Asistente completado',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              companyReady
                                  ? 'Tu empresa está preparada para operar.'
                                  : 'Puedes terminar la configuración cuando quieras.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 22),
                            if (achievements.isEmpty)
                              const Text(
                                'Cuando lo necesites puedes crear productos, abrir turno '
                                'y configurar tu empresa desde el menú.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: AppColors.textMuted,
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  10,
                                  14,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  children: [
                                    for (final text in achievements)
                                      _AchievementRow(text: text),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: widget.onClose,
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  sells ? 'Empezar a vender' : 'Continuar',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44),
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: AppColors.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 12,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.group,
    required this.expanded,
    required this.isCurrent,
    required this.busy,
    required this.openTaskKey,
    required this.onToggleStep,
    required this.onToggleTask,
    required this.onAction,
    required this.onSkip,
    required this.onRestore,
    required this.onTour,
    required this.onOpenEcf,
  });

  final ActivationStepGroup group;
  final bool expanded;

  /// Primer apartado con algo pendiente: es donde conviene continuar.
  final bool isCurrent;
  final bool busy;
  final String? openTaskKey;
  final VoidCallback onToggleStep;
  final ValueChanged<ActivationTask> onToggleTask;
  final ValueChanged<ActivationTask> onAction;
  final ValueChanged<ActivationTask> onSkip;
  final ValueChanged<ActivationTask> onRestore;
  final ValueChanged<ActivationTask> onTour;
  final VoidCallback onOpenEcf;

  @override
  Widget build(BuildContext context) {
    final done = group.isDone;
    final inProgress = !done && group.doneCount > 0;
    return Container(
      decoration: BoxDecoration(
        // Los apartados ya completados se distinguen de un vistazo.
        color: done
            ? AppColors.primarySoft.withValues(alpha: 0.35)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: done
              ? AppColors.primary.withValues(alpha: 0.22)
              : isCurrent
              ? AppColors.primary.withValues(alpha: 0.45)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggleStep,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StepNumber(number: group.number, complete: done),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  group.title,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                    color: done
                                        ? AppColors.textSecondary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (done)
                                const _StateChip(
                                  label: 'Completado',
                                  tone: _StateTone.done,
                                )
                              else if (isCurrent)
                                const _StateChip(
                                  label: 'Ahora',
                                  tone: _StateTone.progress,
                                )
                              else if (inProgress)
                                const _StateChip(
                                  label: 'En curso',
                                  tone: _StateTone.progress,
                                )
                              else if (group.optional)
                                const _StateChip(
                                  label: 'Opcional',
                                  tone: _StateTone.neutral,
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            group.summary,
                            maxLines: expanded ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.3,
                              color: AppColors.textMuted,
                            ),
                          ),
                          if (group.tasks.length > 1 &&
                              group.completionKey == null) ...[
                            const SizedBox(height: 8),
                            ActivationSegmentedProgress(
                              tasks: group.tasks
                                  .map(
                                    (task) => task.isDone
                                        ? ActivationTaskVisualState.done
                                        : task.isSkipped
                                        ? ActivationTaskVisualState.skipped
                                        : ActivationTaskVisualState.pending,
                                  )
                                  .toList(growable: false),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Column(
                    children: [
                      if (group.key == 'ecf')
                        _EcfStepBody(
                          task: group.tasks.first,
                          busy: busy,
                          onOpenEcf: onOpenEcf,
                          onTour: () => onTour(group.tasks.first),
                          onSkip: () => onSkip(group.tasks.first),
                          onRestore: () => onRestore(group.tasks.first),
                        )
                      else if (group.key == 'company')
                        _CompanyStepBody(
                          tasks: group.tasks,
                          busy: busy,
                          onAction: () => onAction(
                            group.tasks.firstWhere(
                              (task) => task.isPending,
                              orElse: () => group.tasks.first,
                            ),
                          ),
                          onTour: () => onTour(
                            group.tasks.firstWhere(
                              (task) => task.isPending,
                              orElse: () => group.tasks.first,
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < group.tasks.length;
                                  i++
                                ) ...[
                                  if (i > 0)
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: AppColors.border,
                                    ),
                                  ActivationTaskTile(
                                    task: group.tasks[i],
                                    // Con una sola tarea el cuerpo va abierto; en
                                    // «Datos de tu empresa» se despliega la parte
                                    // que el usuario toque.
                                    expanded:
                                        group.tasks.length == 1 ||
                                        group.tasks[i].key == openTaskKey,
                                    busy: busy,
                                    isNext: group.isPending,
                                    onToggle: () =>
                                        onToggleTask(group.tasks[i]),
                                    onAction: () => onAction(group.tasks[i]),
                                    onSkip: () => onSkip(group.tasks[i]),
                                    onRestore: () => onRestore(group.tasks[i]),
                                    onTour: group.tasks[i].isDone
                                        ? null
                                        : () => onTour(group.tasks[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

enum _StateTone { done, progress, neutral }

/// Distintivo corto del estado del apartado.
class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.tone});

  final String label;
  final _StateTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (tone) {
      _StateTone.done => (
        AppColors.primary.withValues(alpha: 0.12),
        AppColors.primary,
      ),
      _StateTone.progress => (
        const Color(0xFFF59E0B).withValues(alpha: 0.16),
        const Color(0xFFB45309),
      ),
      _StateTone.neutral => (AppColors.primarySoft, AppColors.primary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

/// Un solo apartado para los datos de la empresa.
///
/// El backend lo mide con tres señales (datos, impuestos y logo), pero para el
/// usuario es un único paso: se le explica qué incluye y se le lleva a la
/// misma pantalla, sin subpasos.
class _CompanyStepBody extends StatelessWidget {
  const _CompanyStepBody({
    required this.tasks,
    required this.busy,
    required this.onAction,
    required this.onTour,
  });

  final List<ActivationTask> tasks;
  final bool busy;
  final VoidCallback onAction;
  final VoidCallback onTour;

  @override
  Widget build(BuildContext context) {
    final pending = tasks.where((task) => task.isPending).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Incluye los datos del negocio, el logo y los impuestos.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
            if (pending > 0) ...[
              const SizedBox(height: 4),
              const Text(
                'Al guardar en Empresa, este paso se marca solo.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: FilledButton.icon(
                onPressed: busy ? null : onAction,
                icon: const Icon(Icons.storefront_outlined, size: 16),
                label: const Text('Completar datos de la empresa'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: busy ? null : onTour,
              icon: const Icon(Icons.auto_awesome_rounded, size: 14),
              label: const Text('Ver cómo'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.only(top: 4),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Acción del apartado de facturación electrónica.
///
/// El paso a paso no se repite aquí: vive en la columna de ayuda («Ver cómo»).
/// A la derecha queda un paso normal, con su botón y sus acciones.
class _EcfStepBody extends StatelessWidget {
  const _EcfStepBody({
    required this.task,
    required this.busy,
    required this.onOpenEcf,
    required this.onTour,
    required this.onSkip,
    required this.onRestore,
  });

  final ActivationTask task;
  final bool busy;
  final VoidCallback onOpenEcf;
  final VoidCallback onTour;
  final VoidCallback onSkip;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    if (task.isDone) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
        child: Row(
          children: const [
            Icon(
              Icons.check_circle_rounded,
              size: 14,
              color: AppColors.primary,
            ),
            SizedBox(width: 6),
            Expanded(
              child: Text(
                'Comprobantes electrónicos activados.',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 38,
              child: FilledButton.icon(
                onPressed: busy ? null : onOpenEcf,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Ir a Empresa › Configuración'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                TextButton.icon(
                  onPressed: busy ? null : onTour,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                  label: const Text('Ver cómo'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (task.isSkipped)
                  TextButton(
                    onPressed: busy ? null : onRestore,
                    child: const Text('Restaurar'),
                  )
                else
                  TextButton(
                    onPressed: busy ? null : onSkip,
                    child: const Text('Omitir'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.number, required this.complete});

  final int number;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: complete
          ? const Icon(Icons.check_rounded, size: 13, color: AppColors.primary)
          : Text(
              '$number',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final ActivationState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Text(
        'Puedes retomar estos pasos cuando quieras desde el botón de activación. '
        'Tu avance se guarda automáticamente y se sincroniza con tu empresa.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.35,
          color: AppColors.textMuted.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 28,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 10),
            const Text(
              'No pudimos cargar tu progreso. Revisa la conexión e inténtalo de nuevo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onClose, child: const Text('Cerrar')),
          ],
        ),
      ),
    );
  }
}
