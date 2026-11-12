import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Registro de anclas del recorrido guiado.
///
/// Las pantallas reales registran sus controles con `Anchor(id, child: ...)` o
/// pasando `ActivationTourTargets.keyFor('pos.collect')` como `key`. El tour
/// calcula el rectángulo global en el momento de pintar, así que funciona con
/// cualquier layout, rotación o cambio de tamaño.
class ActivationTourTargets {
  ActivationTourTargets._();

  static final Map<String, GlobalKey> _keys = <String, GlobalKey>{};

  static GlobalKey keyFor(String id) {
    return _keys.putIfAbsent(
      id,
      () => GlobalKey(debugLabel: 'activation-anchor-$id'),
    );
  }

  /// Rectángulo global del ancla, o `null` si no está montada.
  static Rect? rectFor(String id) {
    final key = _keys[id];
    final context = key?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    final rect = offset & box.size;
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }

  /// Última interacción registrada por un control anclado.
  ///
  /// El recorrido la escucha para cerrarse en cuanto el usuario usa el control
  /// real (por ejemplo «Nuevo producto»), sin robarle el clic: el toque llega al
  /// botón y el formulario existente se abre con sus validaciones intactas.
  static final ValueNotifier<String?> interactions = ValueNotifier<String?>(
    null,
  );

  static void notifyInteraction(String id) => interactions.value = id;

  @visibleForTesting
  static void reset() {
    _keys.clear();
    interactions.value = null;
  }
}

/// Ancla declarativa para un control real de la interfaz.
class ActivationAnchor extends StatelessWidget {
  const ActivationAnchor({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: ActivationTourTargets.keyFor(id), child: child);
  }
}

@immutable
class ActivationTourStep {
  const ActivationTourStep({
    required this.title,
    required this.body,
    this.targetId,
  });

  final String title;
  final String body;

  /// `null` = paso conceptual: se muestra centrado, sin foco.
  final String? targetId;
}

/// Pasos del recorrido por tarea. Si una tarea no tiene recorrido, el panel no
/// muestra la opción «Ver cómo».
List<ActivationTourStep> activationTourStepsFor(String taskKey) {
  switch (taskKey) {
    case 'products':
      return const [
        ActivationTourStep(
          title: 'Registra tu primer producto',
          body:
              'Pulsa «Nuevo producto» para abrir el formulario real. Guarda el producto y la tarea se completará sola: la marcamos cuando exista en tu catálogo, no antes.',
          targetId: 'products.create',
        ),
      ];
    case 'firstSale':
      return const [
        ActivationTourStep(
          title: 'Aquí cobras',
          body:
              'Agrega productos a la venta y pulsa Cobrar. El monto total siempre está a la vista.',
          targetId: 'pos.collect',
        ),
        ActivationTourStep(
          title: 'Elige cómo paga tu cliente',
          body:
              'Efectivo, transferencia, crédito o mixto. FullPOS calcula el cambio y deja el comprobante listo.',
        ),
        ActivationTourStep(
          title: 'Listo, ya vendiste',
          body:
              'La venta queda registrada con su comprobante y descuenta el inventario automáticamente.',
        ),
      ];
    default:
      return const [];
  }
}

/// Superposición del recorrido guiado con foco sobre el control real.
class ActivationTourOverlay extends StatefulWidget {
  const ActivationTourOverlay({
    super.key,
    required this.taskKey,
    required this.steps,
    required this.onFinished,
    required this.onDismissed,
  });

  final String taskKey;
  final List<ActivationTourStep> steps;
  final ValueChanged<int> onFinished;
  final VoidCallback onDismissed;

  @override
  State<ActivationTourOverlay> createState() => _ActivationTourOverlayState();
}

class _ActivationTourOverlayState extends State<ActivationTourOverlay> {
  int _index = 0;
  int _measureRetries = 0;

  @override
  void initState() {
    super.initState();
    ActivationTourTargets.interactions.addListener(_handleInteraction);
  }

  @override
  void dispose() {
    ActivationTourTargets.interactions.removeListener(_handleInteraction);
    super.dispose();
  }

  /// El control real fue usado: el recorrido ya cumplió su función y se retira
  /// dejando el flujo normal (formulario de producto) en manos del usuario.
  void _handleInteraction() {
    if (!mounted) return;
    final step = widget.steps[_index.clamp(0, widget.steps.length - 1)];
    final target = step.targetId;
    if (target == null) return;
    if (ActivationTourTargets.interactions.value != target) return;
    _finish();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDismissed());
      return const SizedBox.shrink();
    }

    final step = widget.steps[_index.clamp(0, widget.steps.length - 1)];
    var targetRect = step.targetId == null
        ? null
        : ActivationTourTargets.rectFor(step.targetId!);

    // El ancla puede no estar maquetada todavía (por ejemplo, justo después de
    // cerrar el panel). Se reintenta medir en el siguiente frame antes de caer
    // al modo centrado.
    if (step.targetId != null && targetRect == null && _measureRetries < 3) {
      _measureRetries++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    final size = MediaQuery.sizeOf(context);
    final isLast = _index >= widget.steps.length - 1;

    final card = _TourCard(
      title: step.title,
      body: step.body,
      counter: '${_index + 1} de ${widget.steps.length}',
      isLast: isLast,
      onNext: isLast ? _finish : _advance,
      onClose: widget.onDismissed,
    );

    return Stack(
      children: [
        // Oscurecido con hueco: cuatro bandas alrededor del objetivo. Evita
        // depender de CustomPainter y mantiene el foco perfectamente alineado.
        if (targetRect == null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismissed,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            ),
          )
        else ...[
          _band(top: 0, left: 0, right: 0, height: targetRect.top),
          _band(
            top: targetRect.bottom,
            left: 0,
            right: 0,
            bottom: 0,
            height: null,
          ),
          Positioned(
            top: targetRect.top,
            left: 0,
            width: targetRect.left,
            height: targetRect.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismissed,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Positioned(
            top: targetRect.top,
            left: targetRect.right,
            right: 0,
            height: targetRect.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismissed,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          // Hueco del objetivo: NO intercepta el toque. El clic llega al
          // control real (el recorrido se cierra vía `notifyInteraction`) y el
          // borde azul solo señala dónde está el botón.
          Positioned(
            top: targetRect.top,
            left: targetRect.left,
            width: targetRect.width,
            height: targetRect.height,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.28),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          _cardPositioned(targetRect, size, card),
        ],
        if (targetRect == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: card,
              ),
            ),
          ),
      ],
    );
  }

  Widget _band({
    double? top,
    double? left,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onDismissed,
        child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
      ),
    );
  }

  Widget _cardPositioned(Rect target, Size size, Widget card) {
    const cardWidth = 320.0;
    final belowSpace = size.height - target.bottom;
    final showBelow = belowSpace > 190 || target.top < 190;
    final maxLeft = size.width - cardWidth - 12;
    final left = maxLeft <= 12
        ? 12.0
        : (target.center.dx - cardWidth / 2).clamp(12.0, maxLeft).toDouble();
    return Positioned(
      top: showBelow ? target.bottom + 12 : null,
      bottom: showBelow ? null : size.height - target.top + 12,
      left: left,
      width: cardWidth,
      child: card,
    );
  }

  void _advance() {
    setState(() {
      _index++;
      _measureRetries = 0;
    });
  }

  void _finish() {
    widget.onFinished(widget.steps.length);
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.title,
    required this.body,
    required this.counter,
    required this.isLast,
    required this.onNext,
    required this.onClose,
  });

  final String title;
  final String body;
  final String counter;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E5FF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260B2A3A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF123A75),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD7E5FF),
                      ),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: Color(0xFF123A75),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: const Color(0xFFE8EEF5), height: 1),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                height: 1.45,
                color: Color(0xFF52667C),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  counter,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7A8B9F),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  height: 28,
                  child: TextButton(
                    onPressed: onNext,
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(isLast ? 'Entendido' : 'Siguiente'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
