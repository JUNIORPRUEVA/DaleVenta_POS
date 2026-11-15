// Local design review only. No production entry point imports this file.
// Real FullPOS widgets, synthetic in-memory repositories and blocked HTTP.
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/loading/web_startup_cover.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/core/theme/app_colors.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_assistant_section.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_intent_api.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_portal_launcher.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_preparation_step.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_welcome_step.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'ecf_design_gallery.dart';

const _preparationRoute = '/revision/preparacion';

final _user = UserModel(
  id: 'synthetic-design-user',
  companyId: 'synthetic-design-company',
  companyName: 'Empresa de demostración',
  email: 'admin@example.test',
  nombreCompleto: 'Administrador de demostración',
  telefono: '',
  role: 'ADMIN',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No local or deployment environment values are loaded into this preview.
  dotenv.testLoad(fileInput: 'APP_ENV=uat\nAPI_BASE_URL=http://127.0.0.1:9');
  runApp(const EcfDesignPreview());
}

class PreviewBackend {
  CompanySettings settings = CompanySettings.empty().copyWith(
    companyName: 'Empresa de demostración',
    rnc: '101000001',
    ecfContactEmail: 'facturacion@example.test',
    address: 'Dirección ficticia para revisar el diseño',
    ecfEnabled: true,
    taxEnabled: true,
    ecfPilotEligible: true,
    defaultTaxRate: 0.18,
  );
  bool allowWithoutVoucher = false;
  int blockedRequests = 0;
}

class _NoNetwork implements HttpClientAdapter {
  _NoNetwork(this.backend);
  final PreviewBackend backend;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    backend.blockedRequests++;
    throw DioException(
      requestOptions: options,
      error: 'Esta vista previa solo utiliza datos ficticios locales.',
      type: DioExceptionType.connectionError,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AuthRepository implements AuthRepository {
  @override
  Future<HydratedSession> hydrateSession() async =>
      HydratedSession(hasToken: true, user: _user);

  @override
  Future<SessionVerificationResult> verifySession({
    bool silent = false,
  }) async => SessionVerificationResult.authenticated(_user);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Acción ajena a la revisión visual.');
}

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(initialized: true, isAuthenticated: true, user: _user);
  }
}

class _SettingsRepository implements CompanySettingsRepository {
  _SettingsRepository(this.backend);
  final PreviewBackend backend;

  @override
  Future<CompanySettings> getSettings() async => backend.settings;

  @override
  Future<bool> saveSettingsOrQueue(CompanySettings settings) async {
    backend.settings = settings;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Esta revisión no modifica datos reales.');
}

class _FiscalRepository extends EcfRepository {
  _FiscalRepository(this.backend, Dio dio) : super(dio);
  final PreviewBackend backend;

  @override
  Future<EcfCapabilities> capabilities() async => EcfCapabilities.fromJson({
    'enabled': backend.settings.ecfEnabled,
    'environment': 'SANDBOX',
    'certificationStatus': 'NOT_STARTED',
    'productionEnabled': false,
    'posReady': false,
    'allowSalesWithoutEcf': backend.allowWithoutVoucher,
    'salesWithoutEcfWarning':
        'Las ventas normales no emiten un comprobante '
        'electrónico ni se envían a la DGII. La empresa es responsable de su uso.',
    'documentTypes': <Object>[],
  });

  @override
  Future<void> updateEnabled({required bool enabled}) async {
    backend.settings = backend.settings.copyWith(
      ecfEnabled: enabled,
      taxEnabled: enabled || backend.settings.taxEnabled,
      ecfPilotEligible: enabled,
    );
  }

  @override
  Future<void> updateAllowSalesWithoutEcf({required bool allow}) async {
    backend.allowWithoutVoucher = allow;
  }
}

class _CashRepository implements CashRepository {
  @override
  bool lastStateFromCache = false;

  @override
  void registerSyncHandlers() {}

  @override
  Future<CashGateState> state() async => CashGateState(
    businessDate: DateTime.now().toIso8601String().split('T').first,
    canOperate: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Las operaciones de caja no forman parte de esta vista previa.',
  );
}

enum _Viewport {
  adaptable('Adaptable', null, TargetPlatform.windows),
  desktop('Escritorio · 1280', 1280, TargetPlatform.windows),
  android('Android · 390', 390, TargetPlatform.android),
  iphone('iPhone · 390', 390, TargetPlatform.iOS),
  tablet('Tableta · 834', 834, TargetPlatform.android);

  const _Viewport(this.label, this.width, this.platform);
  final String label;
  final double? width;
  final TargetPlatform platform;
}

class EcfDesignPreview extends StatefulWidget {
  const EcfDesignPreview({
    super.key,
    this.onStartupComplete = completeWebStartup,
  });

  final VoidCallback onStartupComplete;

  @override
  State<EcfDesignPreview> createState() => _EcfDesignPreviewState();
}

class _EcfDesignPreviewState extends State<EcfDesignPreview> {
  _Viewport _viewport = _Viewport.adaptable;
  int _revision = 0;
  late PreviewBackend _backend;
  late ProviderContainer _container;
  late GoRouter _router;

  @override
  void initState() {
    super.initState();
    _initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStartupComplete();
    });
  }

  void _initialize() {
    _backend = PreviewBackend();
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:9'))
      ..httpClientAdapter = _NoNetwork(_backend);
    _container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        authRepositoryProvider.overrideWithValue(_AuthRepository()),
        authStateProvider.overrideWith(_Auth.new),
        companySettingsRepositoryProvider.overrideWithValue(
          _SettingsRepository(_backend),
        ),
        ecfRepositoryProvider.overrideWithValue(
          _FiscalRepository(_backend, dio),
        ),
        cashRepositoryProvider.overrideWithValue(_CashRepository()),
        dosaPortalEligibilityProvider.overrideWith((ref) async => true),
        dosaIntentStateProvider.overrideWith(
          (ref) async => DosaIntentState.fromJson({
            'canonicalRnc': _backend.settings.rnc,
            'ecfEnabled': true,
            'provider': 'DOSA',
            'canRegister': true,
            'blockingReasons': <String>[],
          }),
        ),
        dosaIntentRegistrationProvider.overrideWith((ref, rnc) async {
          throw StateError('Vista previa: no se abre una postulación real.');
        }),
      ],
    );
    _router = GoRouter(
      initialLocation: Routes.configuracionEmpresa,
      routes: [
        GoRoute(
          path: '/revision/galeria',
          builder: (context, _) => EcfDesignGallery(blockedDio: dio),
        ),
        GoRoute(
          path: Routes.configuracionEmpresa,
          builder: (_, _) => const AccountCompanySettingsScreen(),
        ),
        GoRoute(
          path: Routes.ecf,
          builder: (context, _) => Scaffold(
            appBar: AppBar(title: const Text('Facturación electrónica')),
            body: EcfWelcomeStep(
              videoUrl: '',
              onStart: () => context.go(_preparationRoute),
            ),
          ),
        ),
        GoRoute(
          path: _preparationRoute,
          builder: (context, _) => Scaffold(
            appBar: AppBar(
              title: const Text('Preparación'),
              leading: BackButton(onPressed: () => context.go(Routes.ecf)),
            ),
            body: Consumer(
              builder: (context, ref, _) => EcfPreparationStep(
                settings: ref.watch(companySettingsProvider).valueOrNull,
                companyReady: true,
                contactEmailReady: true,
                certificateReady: false,
                dosaOwnsCertificate: true,
                canManage: true,
                busy: false,
                dosaEntry: const DosaAssistantSection(portalOnly: true),
                onEditFiscalData: () => context.go(Routes.configuracionEmpresa),
                onGoCompany: () => context.go(Routes.configuracionEmpresa),
                onGoCertificate: () {},
                onContinue: () {},
                onStart: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Vista previa: no se abre una postulación real.',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
      errorBuilder: (context, _) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => context.go(Routes.configuracionEmpresa),
            child: const Text('Volver a Empresa'),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    _container.dispose();
    super.dispose();
  }

  void _reset() {
    final previousRouter = _router;
    final previousContainer = _container;
    setState(() {
      _revision++;
      _initialize();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousRouter.dispose();
      previousContainer.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      backgroundColor: AppColors.border,
      body: Column(
        children: [
          Material(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'Vista previa · datos ficticios',
                      style: TextStyle(fontSize: 15),
                    ),
                    TextButton(
                      onPressed: () => _router.go(Routes.configuracionEmpresa),
                      child: const Text('1. Empresa'),
                    ),
                    TextButton(
                      onPressed: () => _router.go(Routes.ecf),
                      child: const Text('2. Entrada al módulo'),
                    ),
                    TextButton(
                      onPressed: () => _router.go(_preparationRoute),
                      child: const Text('3. Preparación'),
                    ),
                    TextButton(
                      onPressed: () => _router.go('/revision/galeria'),
                      child: const Text('4–19. Otras pantallas'),
                    ),
                    DropdownButton<_Viewport>(
                      value: _viewport,
                      items: [
                        for (final viewport in _Viewport.values)
                          DropdownMenuItem(
                            value: viewport,
                            child: Text(viewport.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _viewport = value);
                      },
                    ),
                    TextButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reiniciar vista'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = (_viewport.width ?? constraints.maxWidth).clamp(
                  0.0,
                  constraints.maxWidth,
                );
                return Center(
                  child: SizedBox(
                    width: width,
                    child: UncontrolledProviderScope(
                      key: ValueKey(_revision),
                      container: _container,
                      child: MaterialApp.router(
                        debugShowCheckedModeBanner: false,
                        theme: AppTheme.light.copyWith(
                          platform: _viewport.platform,
                        ),
                        routerConfig: _router,
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(size: Size(width, constraints.maxHeight)),
                          child: child!,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
