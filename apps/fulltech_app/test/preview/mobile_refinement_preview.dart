// Local visual fixture. No production credentials or network calls.
import 'dart:typed_data';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/mobile_drawer_account_footer.dart';
import 'package:daleventa_pos/core/widgets/app_drawer.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_repository.dart';
import 'package:daleventa_pos/features/settings/ui/printer_settings_page.dart';
import 'package:daleventa_pos/features/user/data/users_repository.dart';
import 'package:daleventa_pos/features/user/users_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final previewOwner = UserModel(
  id: 'demo-owner',
  companyId: 'demo-company',
  email: 'administrador@example.test',
  nombreCompleto: 'Administrador',
  telefono: '',
  role: 'ADMIN',
);
final previewCashier = UserModel(
  id: 'demo-cashier',
  companyId: 'demo-company',
  email: 'cajero@example.test',
  nombreCompleto: 'María de los Ángeles Rodríguez',
  telefono: '',
  role: 'CAJERO',
);

class PreviewAuth extends AuthController {
  PreviewAuth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: previewOwner,
    );
  }
}

class _Storage extends TokenStorage {
  @override
  Future<UserModel?> getUserSnapshot() async => previewOwner;
}

class _AuthRepository implements AuthRepository {
  @override
  Future<HydratedSession> hydrateSession() async =>
      HydratedSession(hasToken: true, user: previewOwner);
  @override
  Future<SessionVerificationResult> verifySession({
    bool silent = false,
  }) async => SessionVerificationResult.authenticated(previewOwner);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Preview only');
}

class PreviewUsers extends UsersRepository {
  PreviewUsers() : super(dio: Dio());
  @override
  Future<UsersPage> fetchUsersPage({
    int page = 1,
    int? limit,
    bool skipLoader = false,
  }) async => UsersPage(
    items: [previewOwner, previewCashier],
    page: 1,
    limit: 50,
    hasMore: false,
  );
}

class PreviewPrinter extends MobilePrinterSettingsRepository {
  PreviewPrinter() : super(companyScope: 'demo-company');
  MobilePrinterSettingsModel value = const MobilePrinterSettingsModel(
    companyScope: 'demo-company',
    connectionType: MobilePrinterConnectionType.systemPrinter,
  );
  @override
  Future<MobilePrinterSettingsModel> getOrCreate() async => value;
  @override
  Future<void> update(MobilePrinterSettingsModel settings) async {
    value = settings;
  }
}

class _Platform extends PrintingPlatformResolver {
  @override
  PrintingPlatform get platform => PrintingPlatform.android;
}

class _NoNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{}',
    503,
    headers: {
      'content-type': ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

List<Override> mobilePreviewOverrides() => [
  dioProvider.overrideWithValue(Dio()..httpClientAdapter = _NoNetwork()),
  tokenStorageProvider.overrideWithValue(_Storage()),
  authRepositoryProvider.overrideWithValue(_AuthRepository()),
  authStateProvider.overrideWith(PreviewAuth.new),
  usersRepositoryProvider.overrideWithValue(PreviewUsers()),
  companySettingsProvider.overrideWith((_) async => CompanySettings.empty()),
  mobilePrinterSettingsRepositoryProvider.overrideWithValue(PreviewPrinter()),
  printingPlatformResolverProvider.overrideWithValue(_Platform()),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  dotenv.testLoad(fileInput: 'APP_ENV=uat\nAPI_BASE_URL=http://127.0.0.1:9');
  runApp(
    ProviderScope(
      overrides: mobilePreviewOverrides(),
      child: const MobileRefinementPreview(),
    ),
  );
}

class MobileRefinementPreview extends StatefulWidget {
  const MobileRefinementPreview({super.key});
  @override
  State<MobileRefinementPreview> createState() => _PreviewState();
}

class _PreviewState extends State<MobileRefinementPreview> {
  late final router = GoRouter(
    initialLocation: Routes.users,
    routes: [
      GoRoute(
        path: '/preview-menu',
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Vista local del menú')),
          drawer: buildAdaptiveDrawer(context, currentUser: previewOwner),
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                child: const Text('Abrir menú'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(path: Routes.users, builder: (_, __) => const UsersScreen()),
      GoRoute(
        path: Routes.configuracion,
        builder: (_, __) => const AccountSettingsScreen(),
      ),
      GoRoute(
        path: Routes.configuracionImpresora,
        builder: (_, __) => const PrinterSettingsPage(),
      ),
      GoRoute(
        path: Routes.cotizaciones,
        builder: (_, __) => const Scaffold(body: Text('Vista previa local')),
      ),
    ],
  );
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: router,
    builder: (context, child) => Column(
      children: [
        SafeArea(
          bottom: false,
          child: Material(
            child: Row(
              children: [
                for (final item in [
                  ('Usuario', Routes.users),
                  ('Configuración', Routes.configuracion),
                  ('Impresora', Routes.configuracionImpresora),
                  ('Menú', '/preview-menu'),
                ])
                  Expanded(
                    child: TextButton(
                      onPressed: () => router.go(item.$2),
                      child: Text(
                        item.$1,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: child!),
      ],
    ),
  );
}

// Reuses the actual footer for isolated visual and callback checks.
Widget previewFooter() => MobileDrawerAccountFooter(
  canManageUsers: true,
  onProfile: () {},
  onUsers: () {},
  onSettings: () {},
  onLogout: () {},
);
