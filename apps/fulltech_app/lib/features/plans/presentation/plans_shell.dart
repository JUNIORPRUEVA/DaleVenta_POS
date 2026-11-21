import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/license/license_repository.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../data/plans_repository.dart';
import 'plans_open_provider.dart';

/// Pantallas de la seccion Planes.
///
/// Cada una es una **pagina independiente** con su propio boton de regresar:
/// no hay indice lateral ni barra de secciones, para que la pagina se vea
/// limpia y el regreso devuelva exactamente a donde se estaba.
enum PlansSection {
  resumen(
    label: 'Plan actual',
    icon: Icons.shield_outlined,
    path: Routes.planes,
  ),
  catalogo(
    label: 'Planes',
    icon: Icons.layers_outlined,
    path: Routes.planesCatalogo,
  ),
  pago(
    label: 'Transferencia',
    icon: Icons.account_balance_outlined,
    path: Routes.planesPago,
  ),
  historial(
    label: 'Historial',
    icon: Icons.receipt_long_outlined,
    path: Routes.planesHistorial,
  );

  const PlansSection({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;
}

/// Marco de una pagina de Planes: barra superior con **regresar** y refrescar.
class PlansShell extends ConsumerStatefulWidget {
  const PlansShell({
    super.key,
    required this.section,
    required this.child,
    this.actions = const [],
    this.maxContentWidth = 1080,
  });

  final PlansSection section;
  final Widget child;
  final double maxContentWidth;

  /// Acciones propias de la pagina (p. ej. el historial en Transferencia).
  final List<Widget> actions;

  @override
  ConsumerState<PlansShell> createState() => _PlansShellState();
}

class _PlansShellState extends ConsumerState<PlansShell> {
  bool _busy = false;

  /// Contador capturado en `initState`: en `dispose` ya no se puede usar `ref`
  /// con garantias (la pantalla puede estar desmontandose junto con el armazon)
  /// y el descuento se perdia, dejando la capa de licencia apagada para siempre.
  StateController<int>? _plansCount;
  bool _counted = false;

  @override
  void initState() {
    super.initState();
    _plansCount = ref.read(plansOpenCountProvider.notifier);
    // Avisa de que hay una pantalla de Planes abierta: la capa de licencia
    // vencida se aparta mientras el contador este por encima de cero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _counted) return;
      _counted = true;
      _bump(1);
    });
  }

  @override
  void dispose() {
    // **No** se puede modificar un provider dentro de `dispose` (Riverpod lo
    // prohibe y la excepcion se perdia: el contador nunca bajaba y el cuadro de
    // licencia se quedaba apagado para siempre). Se descuenta en el siguiente
    // fotograma, con el notifier ya capturado.
    if (_counted) {
      final notifier = _plansCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bumpWith(notifier, -1);
      });
    }
    super.dispose();
  }

  void _bump(int delta) => _bumpWith(_plansCount, delta);

  static void _bumpWith(StateController<int>? notifier, int delta) {
    if (notifier == null) return;
    try {
      final next = notifier.state + delta;
      notifier.state = next < 0 ? 0 : next;
    } catch (_) {
      // Contenedor cerrado (cierre de sesion): no hay nada que ajustar.
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    ref.invalidate(plansCatalogProvider);
    ref.invalidate(paymentInstructionsProvider);
    ref.invalidate(licenseOrdersProvider);
    ref.invalidate(licenseStatusProvider);
    try {
      await Future.wait([
        ref.read(plansCatalogProvider.future),
        ref.read(licenseOrdersProvider.future),
      ]);
    } catch (_) {
      // El error se pinta dentro de cada pantalla.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        // El titulo lo pone la propia pagina; la barra solo orienta y vuelve.
        title: '',
        showLogo: false,
        showDepartmentLabel: false,
        fallbackRoute: Routes.cotizaciones,
        trailing: const SizedBox.shrink(),
        actions: [
          ...widget.actions,
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          // Pegado arriba: la pagina no debe quedar centrada en vertical.
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
