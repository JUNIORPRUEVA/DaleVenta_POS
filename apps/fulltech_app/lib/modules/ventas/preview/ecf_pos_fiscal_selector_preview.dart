import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../ecf_pos_fiscal.dart';
import '../ecf_pos_fiscal_selector.dart';

/// Reproduce la franja superior del carrito de `/cotizaciones`: el panel mide
/// ~365 px de ancho y el selector se dibuja con padding 10/8/10/0 sobre fondo
/// casi blanco. Así se ve el widget REAL en su sitio, sin levantar los 22
/// providers de la pantalla completa.
class _CartStrip extends StatelessWidget {
  const _CartStrip({required this.child, this.width = 365});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        backgroundColor: const Color(0xFFEFF5F8),
        body: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: width,
            color: const Color(0xFFFCFEFF),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// E32 preseleccionado: es lo que ve el cajero con un consumidor final.
@Preview(name: 'Carrito 365 · E32 consumo', size: Size(365, 76))
Widget cartStripE32() => _CartStrip(
  child: EcfPosFiscalSelector(
    modes: const [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32],
    selected: EcfPosFiscalMode.e32,
    compact: true,
    onSelected: _ignore,
  ),
);

/// E31 exige receptor identificado: el aviso va debajo del campo.
@Preview(name: 'Carrito 365 · E31 sin receptor', size: Size(365, 96))
Widget cartStripE31MissingBuyer() => _CartStrip(
  child: EcfPosFiscalSelector(
    modes: const [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32],
    selected: EcfPosFiscalMode.e31,
    missingBuyer: true,
    compact: true,
    onSelected: _ignore,
  ),
);

/// Venta normal: una venta interna, sin comprobante y sin ningún aviso.
@Preview(name: 'Carrito 365 · venta normal', size: Size(365, 76))
Widget cartStripNormal() => _CartStrip(
  child: EcfPosFiscalSelector(
    modes: const [
      EcfPosFiscalMode.e31,
      EcfPosFiscalMode.e32,
      EcfPosFiscalMode.normal,
    ],
    selected: EcfPosFiscalMode.normal,
    compact: true,
    onSelected: _ignore,
  ),
);

/// El ancho mínimo que soporta el carrito en móvil (320 px).
@Preview(name: 'Carrito 320 · E32 consumo', size: Size(320, 76))
Widget cartStripNarrow() => _CartStrip(
  width: 320,
  child: EcfPosFiscalSelector(
    modes: const [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32],
    selected: EcfPosFiscalMode.e32,
    compact: true,
    onSelected: _ignore,
  ),
);

void _ignore(EcfPosFiscalMode _) {}
