import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app_update/app_update_controller.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/loading/app_loading_overlay.dart';
import 'core/auth/app_role.dart';
import 'core/auth/auth_provider.dart';
import 'core/auth/auth_session_events.dart';
import 'core/debug/app_error_reporter.dart';
import 'core/debug/app_error_overlay.dart';
import 'core/license/license_repository.dart';
import 'core/offline/sync_queue_service.dart';
import 'core/offline/offline_sync_handlers_bootstrap.dart';
import 'core/realtime/catalog_realtime_service.dart';
import 'core/realtime/operations_realtime_service.dart';
import 'core/startup/app_startup_controller.dart';
import 'core/startup/initial_release_check.dart';
import 'core/app_update/update_guard_overlay.dart';
import 'core/widgets/fulltech_global_background.dart';
import 'features/contabilidad/contabilidad_init.dart';

class _GlobalErrorFallback extends StatefulWidget {
  final FlutterErrorDetails details;

  const _GlobalErrorFallback({required this.details});

  @override
  State<_GlobalErrorFallback> createState() => _GlobalErrorFallbackState();
}

class _GlobalErrorFallbackState extends State<_GlobalErrorFallback> {
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceMuted,
      child: Center(
        child: Icon(
          Icons.error_outline_rounded,
          size: 36,
          color: AppColors.error,
        ),
      ),
    );
  }
}

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      GoogleFonts.config.allowRuntimeFetching = false;
      if (!kIsWeb) {
        MediaKit.ensureInitialized();
      }
      _initializeSqlite();

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppErrorReporter.instance.recordFlutterError(details);
      };

      ErrorWidget.builder = (details) {
        return _GlobalErrorFallback(details: details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppErrorReporter.instance.record(error, stack, context: 'Platform');
        return true;
      };

      unawaited(
        ensureContabilidadLocale(
          locale: PlatformDispatcher.instance.locale.toString(),
        ),
      );

      runApp(const ProviderScope(child: AppBootstrap()));
    },
    (error, stack) {
      AppErrorReporter.instance.record(error, stack, context: 'Zone');
    },
  );
}

class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({super.key});

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  @override
  Widget build(BuildContext context) {
    return const MyApp();
  }
}

void _initializeSqlite() {
  if (kIsWeb) return;

  final platform = defaultTargetPlatform;
  if (platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key, this.enableBackgroundStartup = true});

  final bool enableBackgroundStartup;

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _backgroundStartupStarted = false;
  ProviderSubscription<AuthState>? _authStateSubscription;
  StreamSubscription<LicenseRealtimeMessage>? _licenseRealtimeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authStateSubscription = ref.listenManual<AuthState>(authStateProvider, (
      previous,
      next,
    ) {
      if (!widget.enableBackgroundStartup || !_backgroundStartupStarted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next.isAuthenticated) {
          unawaited(ref.read(catalogRealtimeServiceProvider).connect(next));
          unawaited(ref.read(operationsRealtimeServiceProvider).connect(next));
        } else if (previous?.isAuthenticated == true && !next.isAuthenticated) {
          ref.read(catalogRealtimeServiceProvider).disconnect();
          ref.read(operationsRealtimeServiceProvider).disconnect();
        }
      });
    });
    if (!widget.enableBackgroundStartup) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _backgroundStartupStarted = true);
      unawaited(prepareAppFirstFrame());
      unawaited(
        runInitialReleaseCheck(
          ensureStartupReady: prepareAppFirstFrame,
          checkForUpdates: () async {
            if (!mounted) return;
            await ref.read(appUpdateProvider.notifier).checkNow(force: true);
          },
        ),
      );

      final authState = ref.read(authStateProvider);
      if (authState.isAuthenticated) {
        unawaited(ref.read(catalogRealtimeServiceProvider).connect(authState));
        unawaited(ref.read(operationsRealtimeServiceProvider).connect(authState));
      } else {
        ref.read(catalogRealtimeServiceProvider).disconnect();
        ref.read(operationsRealtimeServiceProvider).disconnect();
      }
      _licenseRealtimeSubscription ??= ref
          .read(operationsRealtimeServiceProvider)
          .licenseStream
          .listen(_handleLicenseRealtimeMessage);
    });
  }

  @override
  void dispose() {
    _licenseRealtimeSubscription?.cancel();
    _authStateSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !widget.enableBackgroundStartup) {
      return;
    }

    unawaited(ref.read(syncQueueServiceProvider.notifier).processPending());
    unawaited(ref.read(appUpdateProvider.notifier).checkNow());
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      unawaited(ref.read(operationsRealtimeServiceProvider).connect(authState));
      unawaited(ref.read(licenseRepositoryProvider).getLicense().then((license) {
        if (!license.isUsable) {
          ref.read(authSessionEventsProvider).requestUnauthorizedLogout();
        }
      }).catchError((_) {}));
    }
  }

  void _handleLicenseRealtimeMessage(LicenseRealtimeMessage message) {
    ref.invalidate(licenseStatusProvider);
    final status = (message.license['status'] ?? '').toString().toUpperCase();
    final blockedEvent = message.type == 'license.blocked' ||
        message.type == 'license.deleted' ||
        status == 'BLOCKED' ||
        status == 'EXPIRED';
    if (blockedEvent) {
      ref.read(authSessionEventsProvider).requestUnauthorizedLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableBackgroundStartup && _backgroundStartupStarted) {
      ref.watch(offlineSyncHandlersBootstrapProvider);
      ref.watch(syncQueueBootstrapProvider);
    }
    ref.watch(appUpdateProvider);
    final router = ref.watch(routerProvider);
    final authState = ref.watch(authStateProvider);
    final role = authState.user?.appRole ?? AppRole.unknown;

    return MaterialApp.router(
      title: 'FullPOS Cloud - Sistema de facturacion',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'DO'),
      supportedLocales: const [Locale('es', 'DO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.lightForRole(role),
      routerConfig: router,
      builder: (context, child) {
        final effectiveChild = child == null
            ? null
            : MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(alwaysUse24HourFormat: false),
                child: child,
              );

        return Stack(
          children: [
            FulltechGlobalBackground(
              role: role,
              enableBlurEffects:
                  widget.enableBackgroundStartup && _backgroundStartupStarted,
            ),
            if (effectiveChild != null) effectiveChild,
            const AppLoadingOverlay(),
            const AppErrorOverlay(),
            const UpdateGuardOverlay(),
          ],
        );
      },
    );
  }
}
