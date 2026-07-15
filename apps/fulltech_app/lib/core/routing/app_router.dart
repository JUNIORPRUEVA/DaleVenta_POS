import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/user/profile_screen.dart';
import '../../features/user/users_screen.dart';
import '../../features/ponche/ponche_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/contabilidad/contabilidad_screen.dart';
import '../../features/contabilidad/cierres_diarios_screen.dart';
import '../../features/contabilidad/depositos_bancarios_screen.dart';
import '../../features/contabilidad/factura_fiscal_screen.dart';
import '../../features/contabilidad/pagos_pendientes_screen.dart';
import '../../features/administracion/admin_punch_registry_screen.dart';
import '../../features/administracion/admin_service_commissions_screen.dart';
import '../../features/administracion/admin_sales_registry_screen.dart';
import '../../features/administracion/admin_quotes_registry_screen.dart';
import '../../features/administracion/administracion_screen.dart';
import '../../features/products/ui/inventory_module_pages.dart';
import '../../features/reports/ui/reports_page.dart';
import '../../features/media_gallery/presentation/media_gallery_screen.dart';
import '../../modules/clientes/cliente_detail_screen.dart';
import '../../modules/clientes/clientes_screen.dart';
import '../../modules/clientes/clientes_map_screen.dart';
import '../../modules/clientes/cliente_form_screen.dart';
import '../../modules/nomina/nomina_screen.dart';
import '../../modules/publicidad/publicidad_hub_screen.dart';
import '../../modules/publicidad/publicidad_campanas_screen_v2.dart';
import '../../modules/publicidad/publicidad_placeholder_screens.dart';
import '../../modules/publicidad/publicidad_screen.dart';
import '../../features/media_gallery/presentation/galeria_publicidad_screen.dart';
import '../../modules/nomina/mis_pagos_screen.dart';
import '../../modules/configuracion/configuracion_screen.dart';
import '../../modules/whatsapp/whatsapp_screen.dart';
import '../../modules/crm_comercial/crm_comercial_screen.dart';
import '../../modules/whatsapp_crm/whatsapp_crm_screen.dart';
import '../../features/amonestaciones/presentation/amonestaciones_screen.dart';
import '../../features/amonestaciones/presentation/warning_detail_screen.dart';
import '../../features/amonestaciones/presentation/mis_amonestaciones_pendientes_screen.dart';
import '../../modules/manual_interno/manual_interno_screen.dart';
import '../../modules/cotizaciones/cotizaciones_historial_screen.dart';
import '../../modules/cotizaciones/cotizaciones_screen.dart';
import '../../modules/document_flows/document_flow_detail_screen.dart';
import '../../modules/document_flows/document_flows_screen.dart';
import '../../modules/service_orders/create_service_order_screen.dart';
import '../../modules/service_orders/service_order_commissions_screen.dart';
import '../../modules/service_orders/service_order_detail_screen.dart';
import '../../modules/service_orders/service_order_models.dart';
import '../../modules/service_orders/service_orders_list_screen.dart';
import '../../modules/ventas/mis_ventas_screen.dart';
import '../../modules/ventas/registrar_venta_screen.dart';
import '../ai_assistant/presentation/ai_screen.dart';
import '../auth/auth_provider.dart';
import '../auth/app_permissions.dart';
import '../auth/app_role.dart';
import 'app_route_observer.dart';
import 'route_access.dart';
import 'routes.dart';

final GlobalKey<NavigatorState> appRootNavigatorKey =
    GlobalKey<NavigatorState>();

CustomTransitionPage<void> _buildPublicidadTransitionPage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final offsetTween = Tween<Offset>(
        begin: const Offset(0.016, 0),
        end: Offset.zero,
      );

      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: offsetTween.animate(curved),
          child: pageChild,
        ),
      );
    },
  );
}

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier();
  ref.listen<AuthState>(
    authStateProvider,
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
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    observers: [routeObserver],
    routes: [
      GoRoute(
        path: Routes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: Routes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: Routes.register,
        redirect: (context, state) => Routes.login,
      ),
      GoRoute(
        path: Routes.home,
        redirect: (context, state) {
          final auth = ref.read(authStateProvider);
          if (!auth.isAuthenticated) return Routes.login;
          return RouteAccess.defaultHomeForRole(
            auth.user?.appRole ?? AppRole.unknown,
          );
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
            path: Routes.users,
            builder: (context, state) => const UsersScreen(),
          ),
          GoRoute(
            path: Routes.ponche,
            builder: (context, state) => const PoncheScreen(),
          ),
          GoRoute(
            path: Routes.poncheHistorial,
            builder: (context, state) => const PunchHistoryScreen(),
          ),
          GoRoute(
            path: Routes.catalogo,
            builder: (context, state) => const InventoryModulePages(),
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
            path: Routes.administracion,
            builder: (context, state) => const AdministracionScreen(),
          ),
          GoRoute(
            path: Routes.administracionPonches,
            builder: (context, state) => const AdminPunchRegistryScreen(),
          ),
          GoRoute(
            path: Routes.administracionVentas,
            builder: (context, state) => const AdminSalesRegistryScreen(),
          ),
          GoRoute(
            path: Routes.administracionComisiones,
            builder: (context, state) => const AdminServiceCommissionsScreen(),
          ),
          GoRoute(
            path: Routes.administracionCotizaciones,
            builder: (context, state) => const AdminQuotesRegistryScreen(),
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
            builder: (context, state) => const MisVentasScreen(),
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
            path: Routes.serviceOrders,
            builder: (context, state) => const ServiceOrdersListScreen(),
          ),
          GoRoute(
            path: Routes.serviceOrderCommissions,
            builder: (context, state) => const ServiceOrderCommissionsScreen(),
          ),
          GoRoute(
            path: Routes.mediaGallery,
            builder: (context, state) => const MediaGalleryScreen(),
          ),
          GoRoute(
            path: Routes.documentFlows,
            builder: (context, state) => const DocumentFlowsScreen(),
          ),
          GoRoute(
            path: Routes.serviceOrderCreate,
            builder: (context, state) {
              final args = state.extra is ServiceOrderCreateArgs
                  ? state.extra as ServiceOrderCreateArgs
                  : null;
              return CreateServiceOrderScreen(args: args);
            },
          ),
          GoRoute(
            path: Routes.serviceOrderDetail,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return ServiceOrderDetailScreen(orderId: id);
            },
          ),
          GoRoute(
            path: Routes.documentFlowDetail,
            builder: (context, state) {
              final orderId = state.pathParameters['orderId'] ?? '';
              return DocumentFlowDetailScreen(orderId: orderId);
            },
          ),
          GoRoute(
            path: Routes.cotizacionesHistorial,
            builder: (context, state) {
              final phone = (state.uri.queryParameters['customerPhone'] ?? '')
                  .trim();
              final pick = (state.uri.queryParameters['pick'] ?? '').trim();
              final quoteId = (state.uri.queryParameters['quoteId'] ?? '')
                  .trim();
              final pickForEditor = pick != '0';
              return CotizacionesHistorialScreen(
                customerPhone: phone.isEmpty ? null : phone,
                pickForEditor: pickForEditor,
                quoteId: quoteId.isEmpty ? null : quoteId,
              );
            },
          ),
          GoRoute(
            path: Routes.manualInterno,
            builder: (context, state) => const ManualInternoScreen(),
          ),
          GoRoute(
            path: Routes.ai,
            builder: (context, state) => const AiScreen(),
          ),
          GoRoute(
            path: Routes.configuracion,
            builder: (context, state) => const ConfiguracionScreen(),
          ),
          GoRoute(
            path: Routes.whatsapp,
            builder: (context, state) => const WhatsappScreen(),
          ),
          GoRoute(
            path: Routes.publicidad,
            builder: (context, state) => const PublicidadHubScreen(),
          ),
          GoRoute(
            path: Routes.publicidadInvestigacion,
            pageBuilder: (context, state) => _buildPublicidadTransitionPage(
              state: state,
              child: const PublicidadScreen.investigacion(),
            ),
          ),
          GoRoute(
            path: Routes.publicidadEstados,
            pageBuilder: (context, state) => _buildPublicidadTransitionPage(
              state: state,
              child: const PublicidadScreen.estados(),
            ),
          ),
          GoRoute(
            path: Routes.publicidadCampanas,
            pageBuilder: (context, state) => _buildPublicidadTransitionPage(
              state: state,
              child: const PublicidadCampanasScreenV2(),
            ),
          ),
          GoRoute(
            path: Routes.publicidadMarketplace,
            pageBuilder: (context, state) => _buildPublicidadTransitionPage(
              state: state,
              child: const PublicidadMarketplaceScreen(),
            ),
          ),
          GoRoute(
            path: Routes.galeriaPublicidad,
            builder: (context, state) => const GaleriaPublicidadScreen(),
          ),
          GoRoute(
            path: Routes.publicidadGaleria,
            pageBuilder: (context, state) => _buildPublicidadTransitionPage(
              state: state,
              child: const GaleriaPublicidadScreen(),
            ),
          ),
          GoRoute(
            path: Routes.whatsappCrm,
            builder: (context, state) => const WhatsappCrmScreen(),
          ),
          GoRoute(
            path: Routes.crmComercial,
            builder: (context, state) => const CrmComercialScreen(),
          ),
          GoRoute(
            path: Routes.amonestaciones,
            builder: (context, state) => const AmonestacionesScreen(),
          ),
          GoRoute(
            path: Routes.amonestacionDetail,
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return WarningDetailScreen(warningId: id);
            },
          ),
          GoRoute(
            path: Routes.misAmonestacionesPendientes,
            builder: (context, state) =>
                const MisAmonestacionesPendientesScreen(),
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
      final role = auth.user?.appRole ?? AppRole.unknown;
      final loc = state.uri.toString();
      final path = state.uri.path;
      final isAuthRoute = path == Routes.login;
      final isSplashRoute = path == Routes.splash;

      String defaultAuthedRoute() {
        return RouteAccess.defaultHomeForRole(role);
      }

      if (!auth.initialized || auth.restoringSession) {
        return isSplashRoute ? null : Routes.splash;
      }

      if (isSplashRoute) {
        return isAuth ? defaultAuthedRoute() : Routes.login;
      }

      if (!isAuth) {
        return isAuthRoute ? null : Routes.login;
      }

      if (isAuth && isAuthRoute) {
        return defaultAuthedRoute();
      }

      final required = RouteAccess.permissionForLocation(loc);
      if (required != null && !hasPermission(role, required)) {
        final fallback = RouteAccess.defaultHomeForRole(role);
        if (path != fallback) {
          return fallback;
        }

        if (path != Routes.profile &&
            hasPermission(role, AppPermission.viewProfile)) {
          return Routes.profile;
        }

        return Routes.login;
      }

      return null;
    },
  );
});

class _RouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
