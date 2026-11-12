import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter/widgets.dart' as widgets;

/// `GestureDetector` con cursor de mano.
///
/// Flutter no expone `mouseCursor` en `GestureDetector`, así que las tarjetas,
/// filas y mosaicos construidos con él mostraban la flecha del sistema aunque
/// fueran pulsables. Este envoltorio replica la API que usa la app y añade un
/// `MouseRegion` con `SystemMouseCursors.click` cuando el gesto tiene acción,
/// de modo que el puntero se comporta igual que en un `InkWell`.
///
/// Uso en el archivo que lo necesite:
/// `import 'package:flutter/material.dart' hide GestureDetector;`
/// seguido del import de este archivo. Los sitios existentes no cambian.
class GestureDetector extends StatelessWidget {
  const GestureDetector({
    super.key,
    this.child,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onTapDown,
    this.onTapUp,
    this.onTapCancel,
    this.onSecondaryTap,
    this.onPanDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onPanCancel,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragEnd,
    this.onHorizontalDragCancel,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onVerticalDragCancel,
    this.onScaleStart,
    this.onScaleUpdate,
    this.onScaleEnd,
    this.behavior = HitTestBehavior.deferToChild,
    this.excludeFromSemantics = false,
  });

  final Widget? child;
  final GestureTapCallback? onTap;
  final GestureTapCallback? onDoubleTap;
  final GestureLongPressCallback? onLongPress;
  final GestureTapDownCallback? onTapDown;
  final GestureTapUpCallback? onTapUp;
  final GestureTapCancelCallback? onTapCancel;
  final GestureTapCallback? onSecondaryTap;
  final GestureDragDownCallback? onPanDown;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureDragCancelCallback? onPanCancel;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragCancelCallback? onHorizontalDragCancel;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureDragCancelCallback? onVerticalDragCancel;
  final GestureScaleStartCallback? onScaleStart;
  final GestureScaleUpdateCallback? onScaleUpdate;
  final GestureScaleEndCallback? onScaleEnd;
  final HitTestBehavior behavior;
  final bool excludeFromSemantics;

  /// Solo los gestos de pulsación convierten el puntero en mano; arrastrar o
  /// escalar no debe sugerir que el elemento es pulsable.
  bool get _isActionable =>
      onTap != null ||
      onDoubleTap != null ||
      onLongPress != null ||
      onSecondaryTap != null ||
      onTapDown != null;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      // `opaque: false`: el envoltorio solo aporta la anotación de cursor. Con
      // el valor por defecto (`true`) el MouseRegion participaría en el
      // hit-test aunque el hijo no fuese alcanzado, lo que puede alterar la
      // prioridad del cursor entre capas solapadas (Stack/Overlay).
      opaque: false,
      cursor: _isActionable ? SystemMouseCursors.click : MouseCursor.defer,
      child: widgets.GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        onTapDown: onTapDown,
        onTapUp: onTapUp,
        onTapCancel: onTapCancel,
        onSecondaryTap: onSecondaryTap,
        onPanDown: onPanDown,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: onPanEnd,
        onPanCancel: onPanCancel,
        onHorizontalDragStart: onHorizontalDragStart,
        onHorizontalDragUpdate: onHorizontalDragUpdate,
        onHorizontalDragEnd: onHorizontalDragEnd,
        onHorizontalDragCancel: onHorizontalDragCancel,
        onVerticalDragStart: onVerticalDragStart,
        onVerticalDragUpdate: onVerticalDragUpdate,
        onVerticalDragEnd: onVerticalDragEnd,
        onVerticalDragCancel: onVerticalDragCancel,
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        onScaleEnd: onScaleEnd,
        behavior: behavior,
        excludeFromSemantics: excludeFromSemantics,
        child: child,
      ),
    );
  }
}
