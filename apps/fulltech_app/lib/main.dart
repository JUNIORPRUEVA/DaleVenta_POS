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
import 'core/company/company_settings_repository.dart';
import 'core/debug/app_error_reporter.dart';
import 'core/debug/app_error_overlay.dart';
import 'core/license/license_repository.dart';
import 'core/lifecycle/app_lifecycle_coordinator.dart';
import 'core/offline/sync_queue_service.dart';
import 'core/offline/offline_sync_handlers_bootstrap.dart';
import 'core/realtime/catalog_realtime_service.dart';
import 'core/realtime/operations_data_refresh_service.dart';
import 'core/realtime/operations_realtime_service.dart';
import 'core/startup/app_startup_controller.dart';
import 'core/startup/app_storage_scope_guard.dart';
import 'core/startup/initial_release_check.dart';
import 'core/app_update/update_guard_overlay.dart';
import 'core/utils/safe_url_launcher.dart';
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
      _configureImageCacheForPlatform();
      _initializeSqlite();
      await AppStorageScopeGuard.ensureCurrentScope();

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

void _configureImageCacheForPlatform() {
  if (!kIsWeb) return;
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 80;
  cache.maximumSizeBytes = 32 * 1024 * 1024;
  debugPrint(
    'APP_BOOT imageCache platform=web maxEntries=${cache.maximumSize} maxBytes=${cache.maximumSizeBytes}',
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
  Timer? _licensePollTimer;
  Timer? _cashPollTimer;
  final _lifecycleCoordinator = AppLifecycleCoordinator();

  /// Intervalo del polling ligero de revalidación del turno de caja. Solo
  /// corre en primer plano con sesión activa y es un GET silencioso de
  /// `/cash/state` (sin flicker). Justificación: es la red de seguridad para
  /// que, aunque el socket realtime no esté disponible (firewall, websocket
  /// caído) o un evento `cash.session.closed/opened` se pierda, el estado del
  /// turno (usuario+empresa, fuente de verdad = backend) converja entre
  /// dispositivos en <= 30s. No es agresivo: 1 petición ligera cada 30s.
  static const _cashPollInterval = Duration(seconds: 30);

  void _startCashRevalidationPolling() {
    _cashPollTimer?.cancel();
    _cashPollTimer = Timer.periodic(_cashPollInterval, (_) {
      if (!mounted) return;
      final auth = ref.read(authStateProvider);
      if (!auth.isAuthenticated) return;
      ref.read(operationsDataRefreshProvider).refreshCash(silent: true);
    });
  }

  void _stopCashRevalidationPolling() {
    _cashPollTimer?.cancel();
    _cashPollTimer = null;
  }

  void _refreshCashOnResume() {
    // Al volver al primer plano (Android/iOS/Windows) otro dispositivo pudo
    // abrir/cerrar el turno mientras esta app estuvo en background y el evento
    // realtime pudo perderse. Revalidamos en silencio contra el backend.
    ref.read(operationsDataRefreshProvider).refreshCash(silent: true);
  }

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
          _startLicensePolling();
        } else if (previous?.isAuthenticated == true && !next.isAuthenticated) {
          ref.read(catalogRealtimeServiceProvider).disconnect();
          ref.read(operationsRealtimeServiceProvider).disconnect();
          _stopLicensePolling();
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
        unawaited(
          ref.read(operationsRealtimeServiceProvider).connect(authState),
        );
        _startLicensePolling();
      } else {
        ref.read(catalogRealtimeServiceProvider).disconnect();
        ref.read(operationsRealtimeServiceProvider).disconnect();
        _stopLicensePolling();
      }
      _licenseRealtimeSubscription ??= ref
          .read(operationsRealtimeServiceProvider)
          .licenseStream
          .listen(_handleLicenseRealtimeMessage);
    });
  }

  @override
  void dispose() {
    _stopLicensePolling();
    _stopCashRevalidationPolling();
    _licenseRealtimeSubscription?.cancel();
    _authStateSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startLicensePolling() {
    if (_licensePollTimer?.isActive == true) return;
    unawaited(_checkLicenseNow());
    _licensePollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_checkLicenseNow());
    });
  }

  void _stopLicensePolling() {
    _licensePollTimer?.cancel();
    _licensePollTimer = null;
  }

  Future<bool> _checkLicenseNow() async {
    if (!mounted) return false;
    final authState = ref.read(authStateProvider);
    if (!authState.isAuthenticated) return false;
    final licenseRepository = ref.read(licenseRepositoryProvider);
    final authSessionEvents = ref.read(authSessionEventsProvider);
    try {
      final license = await licenseRepository.getLicense();
      if (!mounted) return false;
      ref.invalidate(licenseStatusProvider);
      if (!license.isUsable) {
        authSessionEvents.requestUnauthorizedLogout(reason: 'license_expired');
      }
      return true;
    } catch (_) {
      // 401/403 responses are handled by AuthInterceptor. Temporary network
      // failures should not log out an otherwise valid user.
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.enableBackgroundStartup) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopCashRevalidationPolling();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    _startCashRevalidationPolling();
    unawaited(
      _lifecycleCoordinator.runPendingSync(
        () => ref.read(syncQueueServiceProvider.notifier).processPending(),
      ),
    );
    unawaited(
      _lifecycleCoordinator.runUpdateCheck(
        () => ref.read(appUpdateProvider.notifier).checkNow(),
      ),
    );
    final authState = ref.read(authStateProvider);
    if (authState.isAuthenticated) {
      unawaited(ref.read(operationsRealtimeServiceProvider).connect(authState));
      _refreshCashOnResume();
      unawaited(
        _lifecycleCoordinator.runSessionValidation(
          () async => ref
              .read(authStateProvider.notifier)
              .refreshCurrentUser(silent: true),
        ),
      );
      unawaited(
        _lifecycleCoordinator.runLicenseValidation(_checkLicenseNow),
      );
    }
  }

  void _handleLicenseRealtimeMessage(LicenseRealtimeMessage message) {
    ref.invalidate(licenseStatusProvider);
    if (message.type == 'license.company_name_updated' ||
        message.license.containsKey('companyName')) {
      ref.invalidate(companySettingsProvider);
    }
    final status = (message.license['status'] ?? '').toString().toUpperCase();
    final blockedEvent =
        message.type == 'license.blocked' ||
        message.type == 'license.deleted' ||
        status == 'BLOCKED' ||
        status == 'EXPIRED';
    if (blockedEvent) {
      ref
          .read(authSessionEventsProvider)
          .requestUnauthorizedLogout(reason: 'license_expired');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.enableBackgroundStartup && _backgroundStartupStarted) {
      ref.watch(offlineSyncHandlersBootstrapProvider);
      ref.watch(syncQueueBootstrapProvider);
      ref.watch(operationsDataRefreshProvider);
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
            const LicensePurchaseOverlay(),
          ],
        );
      },
    );
  }
}

class LicensePurchaseOverlay extends ConsumerWidget {
  const LicensePurchaseOverlay({super.key});

  static const _phone = '18295344286';

  Uri get _whatsAppUri => Uri.https('wa.me', '/$_phone', {
    'text':
        'Hola, mi plan demo de FullPOS Cloud vencio y quiero comprar o renovar el programa.',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(authSessionEventsProvider);
    if (!events.isLicenseLogout) return const SizedBox.shrink();

    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 680;

    return Material(
      color: const Color(0xEAF3F7FB),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(compact ? 18 : 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Container(
                padding: EdgeInsets.all(compact ? 22 : 30),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD9E4F2)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x260B2744),
                      blurRadius: 34,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.workspace_premium_rounded,
                            color: Color(0xFF1957E6),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Plan demo finalizado',
                                style: TextStyle(
                                  color: Color(0xFF0D1B2A),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'Tu prueba de 7 dias ya vencio.',
                                style: TextStyle(
                                  color: Color(0xFF5E7187),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Para continuar usando FullPOS Cloud necesitas comprar o renovar tu licencia. El plan demo incluye 2 usuarios y 100 productos durante una semana.',
                      style: TextStyle(
                        color: Color(0xFF31465C),
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6FAFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD9E7FB)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.call_rounded,
                            color: Color(0xFF1957E6),
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Compra directa por WhatsApp: 829-534-4286',
                              style: TextStyle(
                                color: Color(0xFF183548),
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => safeOpenWhatsApp(
                              context,
                              _whatsAppUri,
                              copiedMessage:
                                  'No se pudo abrir WhatsApp. Numero copiado.',
                            ),
                            icon: const Icon(Icons.chat_rounded),
                            label: const Text('Comprar por WhatsApp'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1957E6),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.outlined(
                          tooltip: 'Cerrar aviso',
                          onPressed: () => ref
                              .read(authSessionEventsProvider)
                              .dismissReason(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
