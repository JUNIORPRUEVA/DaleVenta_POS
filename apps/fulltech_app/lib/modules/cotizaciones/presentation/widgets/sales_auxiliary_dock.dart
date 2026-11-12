import 'package:flutter/material.dart';

/// El borde derecho coincide con el límite del catálogo y la factura.
class SalesAuxiliaryDock extends StatelessWidget {
  const SalesAuxiliaryDock({
    super.key,
    required this.visible,
    required this.width,
    required this.child,
  });
  final bool visible;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPositioned(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    right: visible ? 0 : -width,
    top: 0,
    bottom: 0,
    width: width,
    child: child,
  );
}
