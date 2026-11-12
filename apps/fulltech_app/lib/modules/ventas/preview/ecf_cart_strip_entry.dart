// Punto de entrada SOLO para verificación visual del selector de comprobante.
//
// No lo usa la app: `lib/main.dart` no lo importa, así que no entra en el
// build de producción. Sirve para ver el widget REAL dentro de un contenedor
// que reproduce la franja superior del carrito de `/cotizaciones`, sin
// levantar los 22 providers de la pantalla completa ni tocar el backend.
import 'package:flutter/material.dart';

import '../ecf_pos_fiscal.dart';
import '../ecf_pos_fiscal_selector.dart';

void main() => runApp(const _VisualPreviewApp());

class _VisualPreviewApp extends StatelessWidget {
  const _VisualPreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const Scaffold(
        backgroundColor: Color(0xFFEFF5F8),
        body: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                _CartStrip(
                  caption: 'Carrito 365 px · E32 consumo',
                  width: 365,
                  child: EcfPosFiscalSelector(
                    modes: [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32],
                    selected: EcfPosFiscalMode.e32,
                    compact: true,
                    onSelected: _ignore,
                  ),
                ),
                _CartStrip(
                  caption: 'Carrito 365 px · E31 sin receptor',
                  width: 365,
                  child: EcfPosFiscalSelector(
                    modes: [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32],
                    selected: EcfPosFiscalMode.e31,
                    missingBuyer: true,
                    compact: true,
                    onSelected: _ignore,
                  ),
                ),
                _CartStrip(
                  caption: 'Carrito 365 px · venta normal (sin avisos)',
                  width: 365,
                  child: EcfPosFiscalSelector(
                    modes: [
                      EcfPosFiscalMode.e31,
                      EcfPosFiscalMode.e32,
                      EcfPosFiscalMode.normal,
                    ],
                    selected: EcfPosFiscalMode.normal,
                    compact: true,
                    onSelected: _ignore,
                  ),
                ),
                _CartStrip(
                  caption: 'Carrito 320 px (móvil mínimo)',
                  width: 320,
                  child: EcfPosFiscalSelector(
                    modes: [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32],
                    selected: EcfPosFiscalMode.e32,
                    compact: true,
                    onSelected: _ignore,
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

/// Reproduce la franja superior del carrito: fondo casi blanco y el mismo
/// padding que `_DesktopQuotePanel` (10 / 8 / 10 / 0).
class _CartStrip extends StatelessWidget {
  const _CartStrip({
    required this.caption,
    required this.width,
    required this.child,
  });

  final String caption;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF52667C),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: width,
          decoration: BoxDecoration(
            color: const Color(0xFFFCFEFF),
            border: Border.all(color: const Color(0xFFDDE7EE)),
          ),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: child,
        ),
      ],
    );
  }
}

void _ignore(EcfPosFiscalMode _) {}
