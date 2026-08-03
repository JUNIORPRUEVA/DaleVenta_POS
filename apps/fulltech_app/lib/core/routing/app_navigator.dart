import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'routes.dart';

class AppNavigator {
  static String? _previousShellLocation;
  static String? _currentShellLocation;

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

    final location = currentLocation(context);
    if (effectiveFallbackRouteFor(location) != null) return true;

    return _canUseNavigatorPop(context, location);
  }

  static Widget? maybeBackButton(
    BuildContext context, {
    String? fallbackRoute,
    String tooltip = 'Regresar',
  }) {
    final fallback =
        fallbackRoute ?? effectiveFallbackRouteFor(currentLocation(context));
    if (!canGoBack(context) && fallback == null) return null;

    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => goBack(context, fallbackRoute: fallback),
    );
  }

  static void go(BuildContext context, String location) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    _recordShellTransition(
      _routerLocation(router) ?? currentLocation(context),
      location,
    );
    router.go(location);
  }

  static void recordShellLocation(String location) {
    if (!_isShellLocation(location)) return;
    final normalized = _normalizeLocation(location);
    if (normalized == _currentShellLocation) return;
    if (_currentShellLocation != null) {
      _previousShellLocation = _currentShellLocation;
    }
    _currentShellLocation = normalized;
  }

  static void goBack(BuildContext context, {String? fallbackRoute}) {
    final router = GoRouter.maybeOf(context);
    final location = router == null
        ? currentLocation(context)
        : (_routerLocation(router) ?? currentLocation(context));
    final fallback = fallbackRoute ?? effectiveFallbackRouteFor(location);
    if (router != null &&
        _shouldUseShellFallbackBeforePop(location, fallback)) {
      _consumeBackFallback(location, fallback!);
      router.go(fallback);
      return;
    }

    if (router?.canPop() ?? false) {
      router!.pop();
      return;
    }

    final navigator = Navigator.maybeOf(context);
    if (_canUseNavigatorPop(context, location)) {
      navigator!.pop();
      return;
    }

    if (fallback != null && router != null) {
      _consumeBackFallback(location, fallback);
      router.go(fallback);
    }
  }

  static Future<bool> handleSystemBack(BuildContext context) async {
    final router = GoRouter.maybeOf(context);
    final location = router == null
        ? currentLocation(context)
        : (_routerLocation(router) ?? currentLocation(context));
    final shellFallback = effectiveFallbackRouteFor(location);
    if (router != null &&
        _shouldUseShellFallbackBeforePop(location, shellFallback)) {
      _consumeBackFallback(location, shellFallback!);
      router.go(shellFallback);
      return false;
    }

    if (router?.canPop() ?? false) {
      router!.pop();
      return false;
    }

    final navigator = Navigator.maybeOf(context);
    if (_canUseNavigatorPop(context, location)) {
      navigator!.pop();
      return false;
    }

    final fallback = shellFallback ?? _shellHomeFallbackFor(location);
    if (fallback != null && router != null) {
      _consumeBackFallback(location, fallback);
      router.go(fallback);
      return false;
    }

    return _confirmExitApp(context);
  }

  static String? effectiveFallbackRouteFor(String location) {
    final normalized = _normalizeLocation(location);
    final previous = _previousShellLocation;
    if (previous != null &&
        previous != normalized &&
        _isShellLocation(previous) &&
        _isShellLocation(normalized)) {
      return previous;
    }
    return fallbackRouteFor(normalized);
  }

  static String? fallbackRouteFor(String location) {
    final normalized = location.trim();
    final path = (Uri.tryParse(normalized)?.path ?? normalized).trim();

    if (path.isEmpty) return Routes.profile;

    if (path == Routes.poncheHistorial) return Routes.ponche;
    if (path == Routes.registrarVenta) return Routes.ventas;
    if (path == Routes.compras) return Routes.cotizaciones;
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
    if (path.startsWith('${Routes.configuracion}/') &&
        path != Routes.configuracion) {
      return Routes.configuracion;
    }
    if (path.startsWith('/publicidad/') && path != Routes.publicidad) {
      return Routes.publicidad;
    }

    return null;
  }

  static void resetBackHistoryForTesting() {
    _previousShellLocation = null;
    _currentShellLocation = null;
  }

  static String? get debugPreviousShellLocation => _previousShellLocation;

  static String? get debugCurrentShellLocation => _currentShellLocation;

  static void _recordShellTransition(String from, String to) {
    if (!_isShellLocation(from) || !_isShellLocation(to)) return;
    final normalizedFrom = _normalizeLocation(from);
    final normalizedTo = _normalizeLocation(to);
    if (normalizedFrom == normalizedTo) return;
    _previousShellLocation = normalizedFrom;
    _currentShellLocation = normalizedTo;
  }

  static void _consumeBackFallback(String from, String fallback) {
    final normalizedFrom = _normalizeLocation(from);
    final normalizedFallback = _normalizeLocation(fallback);
    if (_previousShellLocation == normalizedFallback) {
      _previousShellLocation = normalizedFrom;
      _currentShellLocation = normalizedFallback;
      return;
    }
    if (_isShellLocation(normalizedFallback)) {
      _recordShellTransition(normalizedFrom, normalizedFallback);
    }
  }

  static bool _canUseNavigatorPop(BuildContext context, String location) {
    if (_isShellLocation(location)) return false;
    return Navigator.maybeOf(context)?.canPop() ?? false;
  }

  static bool _shouldUseShellFallbackBeforePop(
    String location,
    String? fallback,
  ) {
    if (fallback == null) return false;
    final normalized = _normalizeLocation(location);
    final normalizedFallback = _normalizeLocation(fallback);
    return _isShellLocation(normalized) &&
        _previousShellLocation == normalizedFallback;
  }

  static String? _shellHomeFallbackFor(String location) {
    final normalized = _normalizeLocation(location);
    if (!_isShellLocation(normalized)) return null;
    final path = Uri.tryParse(normalized)?.path ?? normalized;
    if (path == Routes.cotizaciones || path == Routes.profile) return null;
    return Routes.home;
  }

  static bool _isShellLocation(String location) {
    final path = (Uri.tryParse(location)?.path ?? location).trim();
    if (path.isEmpty) return false;
    if (path == Routes.splash ||
        path == Routes.login ||
        path == Routes.register ||
        path == Routes.registrarVenta) {
      return false;
    }
    return path.startsWith('/');
  }

  static String _normalizeLocation(String location) {
    final trimmed = location.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return trimmed;
    final query = uri.query.trim();
    return query.isEmpty ? uri.path : '${uri.path}?$query';
  }

  static String? _routerLocation(GoRouter router) {
    try {
      return router.routerDelegate.currentConfiguration.uri.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _confirmExitApp(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Salir de la app'),
          content: const Text('¿Deseas cerrar FullPOS Cloud?'),
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
