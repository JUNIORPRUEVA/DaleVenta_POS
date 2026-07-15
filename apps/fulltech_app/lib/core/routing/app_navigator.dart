import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

class AppNavigator {
  static String currentLocation(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.toString();
    } catch (_) {
      try {
        return GoRouter.of(
          context,
        ).routerDelegate.currentConfiguration.uri.toString();
      } catch (_) {
        return ModalRoute.of(context)?.settings.name ?? '';
      }
    }
  }

  static bool canGoBack(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() ?? false) return true;
    return Navigator.maybeOf(context)?.canPop() ?? false;
  }

  static Widget? maybeBackButton(
    BuildContext context, {
    String? fallbackRoute,
    String tooltip = 'Regresar',
  }) {
    final fallback =
        fallbackRoute ?? fallbackRouteFor(currentLocation(context));
    if (!canGoBack(context) && fallback == null) return null;

    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => goBack(context, fallbackRoute: fallback),
    );
  }

  static void goBack(BuildContext context, {String? fallbackRoute}) {
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() ?? false) {
      router!.pop();
      return;
    }

    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
      return;
    }

    final fallback =
        fallbackRoute ?? fallbackRouteFor(currentLocation(context));
    if (fallback != null && router != null) {
      router.go(fallback);
    }
  }

  static Future<bool> handleSystemBack(BuildContext context) async {
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() ?? false) {
      router!.pop();
      return false;
    }

    final navigator = Navigator.maybeOf(context);
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
      return false;
    }

    final fallback = fallbackRouteFor(currentLocation(context));
    if (fallback != null && router != null) {
      router.go(fallback);
      return false;
    }

    return _confirmExitApp(context);
  }

  static String? fallbackRouteFor(String location) {
    final normalized = location.trim();
    final path = (Uri.tryParse(normalized)?.path ?? normalized).trim();

    if (path.isEmpty) return Routes.profile;

    if (path == Routes.poncheHistorial) return Routes.ponche;
    if (path == Routes.registrarVenta) return Routes.ventas;
    if (path == Routes.serviceOrderCreate) return Routes.serviceOrders;
    if (path == Routes.cotizacionesHistorial) return Routes.cotizaciones;
    if (path == Routes.clienteNuevo) return Routes.clientes;
    if (path == Routes.ai) return Routes.serviceOrders;
    if (path.startsWith('/clientes/') && path.endsWith('/editar')) {
      return Routes.clientes;
    }
    if (path.startsWith('/clientes/')) return Routes.clientes;
    if (path.startsWith('${Routes.serviceOrders}/')) {
      return Routes.serviceOrders;
    }
    if (path == Routes.contabilidadCierresDiarios ||
        path == Routes.contabilidadDepositos ||
        path == Routes.contabilidadFacturaFiscal ||
        path == Routes.contabilidadPagosPendientes) {
      return Routes.contabilidad;
    }
    if (path.startsWith('/publicidad/') && path != Routes.publicidad) {
      return Routes.publicidad;
    }

    return null;
  }

  static Future<bool> _confirmExitApp(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Salir de la app'),
          content: const Text('¿Deseas cerrar FULLTECH?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salir'),
            ),
          ],
        );
      },
    );

    return result == true;
  }
}
