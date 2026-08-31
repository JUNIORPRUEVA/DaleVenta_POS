import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_menu_screens.dart';
import '../../features/auth/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/user/profile_screen.dart';
import '../../features/user/users_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/contabilidad/contabilidad_screen.dart';
import '../../features/contabilidad/cierres_diarios_screen.dart';
import '../../features/contabilidad/depositos_bancarios_screen.dart';
import '../../features/contabilidad/factura_fiscal_screen.dart';
import '../../features/contabilidad/pagos_pendientes_screen.dart';
import '../../features/products/ui/inventory_module_pages.dart';
import '../../features/reports/ui/reports_page.dart';
import '../../features/warehouses/ui/warehouse_settings_screen.dart';
import '../../modules/clientes/cliente_detail_screen.dart';
import '../../modules/clientes/clientes_screen.dart';
import '../../modules/cash/cash_box_screen.dart';
import '../../modules/cash/cash_management_screens.dart';
import '../../modules/clientes/clientes_map_screen.dart';
import '../../modules/clientes/cliente_form_screen.dart';
import '../../modules/nomina/nomina_screen.dart';
import '../../modules/nomina/mis_pagos_screen.dart';
import '../../modules/cotizaciones/cotizaciones_historial_screen.dart';
import '../../modules/cotizaciones/cotizaciones_screen.dart';
import '../../modules/ventas/tpv_sales_history_screen.dart';
import '../../modules/ventas/registrar_venta_screen.dart';
import '../../modules/ventas/sales_credit_screen.dart';
import '../../modules/compras/compras_screen.dart';
import '../ai_assistant/presentation/ai_screen.dart';
import '../auth/admin_authorization_session.dart';
import '../auth/app_bootstrap_status.dart';
import '../auth/auth_provider.dart';
import '../auth/app_permissions.dart';
import '../auth/business_registration_policy.dart';
import 'app_route_observer.dart';
import 'route_access.dart';
import 'routes.dart';

final GlobalKey<NavigatorState> appRootNavigatorKey =
    GlobalKey<NavigatorState>();

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen<AuthState>(
    authStateProvider,
    (previous, next) => notifier.refresh(),
  );
  ref.listen<AppBootstrapStatus>(
    appBootstrapStatusProvider,
    (previous, next) => notifier.refresh(),
  );
  ref.listen<AdminAuthorizationState>(
    adminAuthorizationProvider,
    (previous, next) => notifier.refresh(),
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);
  final routeObserver = ref.watch(appRouteObserverProvider);

  return GoRouter(
    navigatorKey: appRootNavigatorKey,
    refreshListenable: refresh,
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: Routes.landing,
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: Routes.resetPassword,
        builder: (context, state) {
          final token = (state.uri.queryParameters['token'] ?? '').trim();
          return ResetPasswordScreen(token: token);
        },
      ),
      GoRoute(
        path: Routes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: Routes.home,
        redirect: (context, state) {
          final auth = ref.read(authStateProvider);
          if (!auth.isAuthenticated) return Routes.login;
          return RouteAccess.defaultHomeForUser(auth.user);
        },
      ),
      GoRoute(
        path: Routes.registrarVenta,
        builder: (context, state) => const RegistrarVentaScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: Routes.user,
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: Routes.nomina,
            builder: (context, state) => const NominaScreen(),
          ),
          GoRoute(
            path: Routes.misPagos,
            builder: (context, state) => const MisPagosScreen(),
          ),
          GoRoute(
            path: Routes.profile,
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: Routes.apps,
            builder: (context, state) => const AccountAppsScreen(),
          ),
          GoRoute(
            path: Routes.licencias,
            builder: (context, state) => const AccountLicensesScreen(),
          ),
          GoRoute(
            path: Routes.actualizaciones,
            builder: (context, state) => const AccountUpdatesScreen(),
          ),
          GoRoute(
            path: Routes.configuracion,
            redirect: (context, state) =>
                _isDesktopSettingsLayout(context) ? Routes.cotizaciones : null,
            builder: (context, state) => const AccountSettingsScreen(),
          ),
          GoRoute(
            path: Routes.configuracionEmpresa,
            builder: (context, state) => const AccountCompanySettingsScreen(),
          ),
          GoRoute(
            path: Routes.configuracionImpresora,
            redirect: (context, state) => kIsWeb ? Routes.cotizaciones : null,
            builder: (context, state) => const AccountPrinterSettingsScreen(),
          ),
          GoRoute(
            path: Routes.configuracionBackup,
            builder: (context, state) => const AccountBackupSettingsScreen(),
          ),
          GoRoute(
            path: Routes.configuracionParametros,
            builder: (context, state) => const AccountParametersScreen(),
          ),
          GoRoute(
            path: Routes.configuracionDocumentos,
            builder: (context, state) => const AccountDocumentsSettingsScreen(),
          ),
          GoRoute(
            path: Routes.configuracionAlmacenes,
            builder: (context, state) => const WarehouseSettingsScreen(),
          ),
          GoRoute(
            path: Routes.users,
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: Routes.userPermissions,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return UserPermissionsScreen(userId: id);
            },
          ),
          GoRoute(
            path: Routes.catalogo,
            builder: (context, state) => const InventoryModulePages(),
          ),
          GoRoute(
            path: Routes.catalogoStock,
            builder: (context, state) =>
                const InventoryModulePages(initialMobileTab: 'stock'),
          ),
          GoRoute(
            path: Routes.catalogoCategorias,
            builder: (context, state) =>
                const InventoryModulePages(initialMobileTab: 'categories'),
          ),
          GoRoute(
            path: Routes.catalogoConteo,
            builder: (context, state) =>
                const InventoryModulePages(initialMobileTab: 'inventory'),
          ),
          GoRoute(
            path: Routes.contabilidad,
            builder: (context, state) => const ContabilidadScreen(),
          ),
          GoRoute(
            path: Routes.contabilidadCierresDiarios,
            builder: (context, state) => const CierresDiariosScreen(),
          ),
          GoRoute(
            path: Routes.contabilidadDepositos,
            builder: (context, state) => const DepositosBancariosScreen(),
          ),
          GoRoute(
            path: Routes.contabilidadFacturaFiscal,
            builder: (context, state) => const FacturaFiscalScreen(),
          ),
          GoRoute(
            path: Routes.contabilidadPagosPendientes,
            builder: (context, state) => const PagosPendientesScreen(),
          ),
          GoRoute(
            path: Routes.clientes,
            builder: (context, state) => const ClientesScreen(),
          ),
          GoRoute(
            path: Routes.clientesMapa,
            builder: (context, state) => const ClientesMapScreen(),
          ),
          GoRoute(
            path: Routes.ventasLista,
            builder: (context, state) => const TpvSalesHistoryScreen(),
          ),
          GoRoute(
            path: Routes.ventasCreditos,
            builder: (context, state) => const SalesCreditScreen(),
          ),
          GoRoute(
            path: Routes.compras,
            builder: (context, state) => const ComprasScreen(),
          ),
          GoRoute(
            path: Routes.comprasLista,
            builder: (context, state) =>
                const ComprasScreen(initialMobileTab: 'orders'),
          ),
          GoRoute(
            path: Routes.comprasSuplidores,
            builder: (context, state) =>
                const ComprasScreen(initialMobileTab: 'suppliers'),
          ),
          GoRoute(
            path: Routes.comprasFacturas,
            builder: (context, state) =>
                const ComprasScreen(initialMobileTab: 'invoices'),
          ),
          GoRoute(
            path: Routes.comprasPorComprar,
            builder: (context, state) =>
                const ComprasScreen(initialMobileTab: 'recommendations'),
          ),
          GoRoute(
            path: Routes.caja,
            builder: (context, state) => const CashBoxScreen(),
          ),
          GoRoute(
            path: Routes.cajaMovimientos,
            builder: (context, state) => const CashMovementsHistoryScreen(),
          ),
          GoRoute(
            path: Routes.cajaRegistrarGasto,
            builder: (context, state) => const CashExpenseScreen(),
          ),
          GoRoute(
            path: Routes.cajaGastosHistorial,
            builder: (context, state) => const CashExpensesHistoryScreen(),
          ),
          GoRoute(
            path: Routes.cajaTurnosHistorial,
            builder: (context, state) => const CashTurnHistoryScreen(),
          ),
          GoRoute(
            path: Routes.ventasBase,
            redirect: (context, state) => Routes.ventas,
          ),
          GoRoute(
            path: Routes.ventas,
            builder: (context, state) => const ReportsPage(),
          ),
          GoRoute(
            path: Routes.cotizaciones,
            builder: (context, state) => const CotizacionesScreen(),
          ),
          GoRoute(
            path: Routes.cotizacionesHistorial,
            builder: (context, state) {
              final phone = (state.uri.queryParameters['customerPhone'] ?? '')
                  .trim();
              final pick = (state.uri.queryParameters['pick'] ?? '').trim();
              final quoteId = (state.uri.queryParameters['quoteId'] ?? '')
                  .trim();
              final pickForEditor = pick == '1';
              return CotizacionesHistorialScreen(
                customerPhone: phone.isEmpty ? null : phone,
                pickForEditor: pickForEditor,
                quoteId: quoteId.isEmpty ? null : quoteId,
              );
            },
          ),
          GoRoute(
            path: Routes.ai,
            builder: (context, state) => const AiScreen(),
          ),
          GoRoute(
            path: Routes.clienteNuevo,
            builder: (context, state) => const ClienteFormScreen(),
          ),
          GoRoute(
            path: Routes.clienteDetalle,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return ClienteDetailScreen(clienteId: id);
            },
          ),
          GoRoute(
            path: Routes.clienteEditar,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return ClienteFormScreen(clienteId: id);
            },
          ),
        ],
      ),
    ],
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final isAuth = auth.isAuthenticated;
      final loc = state.uri.toString();
      final path = state.uri.path;
      ref.read(adminAuthorizationProvider.notifier).clearIfExpired();
      final registrationDisabled = ref.read(
        businessRegistrationDisabledProvider,
      );
      final recoveryLocation = _passwordRecoveryLocationFrom(state.uri);
      if (recoveryLocation != null && recoveryLocation != loc) {
        return recoveryLocation;
      }
      final isPasswordRecoveryRoute =
          path == Routes.forgotPassword || path == Routes.resetPassword;

      if (registrationDisabled && path == Routes.register) {
        return Routes.login;
      }

      if (isPasswordRecoveryRoute) {
        return null;
      }

      final bootstrap = ref.read(appBootstrapStatusProvider);
      final publicLandingEnabled = _isPublicLandingEnabled(
        registrationDisabled,
      );

      final isAuthRoute =
          path == Routes.login ||
          (!registrationDisabled && path == Routes.register) ||
          (publicLandingEnabled && path == Routes.landing);
      final isSplashRoute = path == Routes.splash;

      String defaultAuthedRoute() {
        return RouteAccess.defaultHomeForUser(auth.user);
      }

      String unauthenticatedEntryRoute() {
        return publicLandingEnabled ? Routes.landing : Routes.login;
      }

      final bootstrappingAuthenticatedSession =
          bootstrap == AppBootstrapStatus.initializing ||
          bootstrap == AppBootstrapStatus.authenticatedLoadingCompany ||
          bootstrap == AppBootstrapStatus.error;

      if (bootstrappingAuthenticatedSession) {
        return isSplashRoute ? null : Routes.splash;
      }

      if (isSplashRoute) {
        if (bootstrap == AppBootstrapStatus.ready) {
          return defaultAuthedRoute();
        }
        return unauthenticatedEntryRoute();
      }

      if (!publicLandingEnabled && path == Routes.landing) {
        return isAuth ? defaultAuthedRoute() : Routes.login;
      }

      if (!isAuth) {
        if (isAuthRoute) return null;
        return unauthenticatedEntryRoute();
      }

      if (isAuth && isAuthRoute) {
        return defaultAuthedRoute();
      }

      final required = RouteAccess.permissionForLocation(loc);
      if (required != null && !hasUserPermission(auth.user, required)) {
        final adminOverride = ref
            .read(adminAuthorizationProvider.notifier)
            .isAuthorizedForRoute(loc);
        if (adminOverride) return null;
        final fallback = RouteAccess.defaultHomeForUser(auth.user);
        if (path != fallback) {
          return fallback;
        }

        if (path != Routes.profile &&
            hasUserPermission(auth.user, AppPermission.viewProfile)) {
          return Routes.profile;
        }

        return Routes.login;
      }

      return null;
    },
  );
});

bool _isPublicLandingEnabled(bool registrationDisabled) {
  return kIsWeb && !registrationDisabled;
}

String? _passwordRecoveryLocationFrom(Uri uri) {
  final path = uri.path.isEmpty ? Routes.landing : uri.path;
  final directToken = (uri.queryParameters['token'] ?? '').trim();
  if (path == Routes.resetPassword && directToken.isNotEmpty) {
    return '${Routes.resetPassword}?token=${Uri.encodeQueryComponent(directToken)}';
  }

  if ((path == Routes.landing || path == Routes.splash) &&
      directToken.isNotEmpty) {
    return '${Routes.resetPassword}?token=${Uri.encodeQueryComponent(directToken)}';
  }

  final fragmentLocation = _passwordRecoveryLocationFromFragment(uri.fragment);
  if (fragmentLocation != null) return fragmentLocation;

  return null;
}

String? _passwordRecoveryLocationFromFragment(String fragment) {
  final text = fragment.trim();
  if (text.isEmpty) return null;

  final normalized = text.startsWith('/') ? text : '/$text';
  Uri? parsed;
  try {
    parsed = Uri.parse(normalized);
  } catch (_) {
    return null;
  }

  final path = parsed.path.isEmpty ? Routes.landing : parsed.path;
  final token = (parsed.queryParameters['token'] ?? '').trim();
  if (path == Routes.resetPassword && token.isNotEmpty) {
    return '${Routes.resetPassword}?token=${Uri.encodeQueryComponent(token)}';
  }
  if ((path == Routes.landing || path == Routes.splash) && token.isNotEmpty) {
    return '${Routes.resetPassword}?token=${Uri.encodeQueryComponent(token)}';
  }

  return null;
}

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

bool _isDesktopSettingsLayout(BuildContext context) {
  final size = MediaQuery.maybeSizeOf(context);
  return size != null && size.width >= 900;
}
