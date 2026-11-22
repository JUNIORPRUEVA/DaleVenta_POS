import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/pagination/paged_result.dart';
import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/clientes/data/clientes_repository.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_historial_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/data/cotizaciones_repository.dart';
import 'package:flutter/services.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

final _quote = CotizacionModel(
  id: 'quotation-demo', createdAt: DateTime(2026, 11, 22),
  customerId: 'client-demo', customerName: 'Cliente de demostración',
  customerPhone: '', note: 'Nota de demostración', includeItbis: false,
  itbisRate: 0.18, items: const [],
);

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(initialized: true, isAuthenticated: true, user: UserModel(
      id: 'demo-owner', companyId: 'demo-company', email: 'owner@example.test',
      nombreCompleto: 'Administrador', telefono: '', role: 'ADMIN',
    ));
  }
}

class _Quotes implements CotizacionesRepository {
  @override
  Future<List<CotizacionModel>> getCachedList({String? customerPhone, String? userId,
    DateTime? from, DateTime? to, int take = 80}) async => [];
  @override
  Future<PagedResult<CotizacionModel>> listPage({String? customerPhone,
    String? customerId, String? userId, String? search, DateTime? from,
    DateTime? to, int page = 1, int limit = 50}) async =>
      PagedResult(items: [_quote], page: 1, limit: 50, hasMore: false, total: 1);
  @override
  Future<void> upsertLocal(CotizacionModel item, {required String companyId}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('Local fixture only');
}

class _Clients implements ClientesRepository {
  @override
  Future<List<ClienteModel>> listClients({required String ownerId, String search = '',
    ClientesOrder order = ClientesOrder.az, CorreoFilter correoFilter = CorreoFilter.todos,
    EstadoFilter estadoFilter = EstadoFilter.activos, OwnerFilter ownerFilter = OwnerFilter.todos,
    int page = 1, int pageSize = 100, bool skipLoader = false}) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('Local fixture only');
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
    final loader = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await loader.load();
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS, TargetPlatform.windows]) {
    testWidgets('quotation options and card navigation: $platform', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(overrides: [
        authStateProvider.overrideWith((ref) => _Auth(ref)),
        cotizacionesRepositoryProvider.overrideWithValue(_Quotes()),
        clientesRepositoryProvider.overrideWithValue(_Clients()),
      ], child: MaterialApp(theme: AppTheme.light, home: const CotizacionesHistorialScreen(pickForEditor: false))));
      await tester.pumpAndSettle();
      expect(find.text('Cliente de demostración'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Quotation list must fit');
      final menu = find.byType(PopupMenuButton<String>);
      expect(menu, findsOneWidget);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      final phone = platform != TargetPlatform.windows;
      expect(find.text('Ver detalle'), phone ? findsNothing : findsOneWidget);
      expect(find.text('Ver PDF'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Quotation menu must fit');
      if (phone) {
        expect(tester.widget<PopupMenuButton<String>>(menu).shape, const RoundedRectangleBorder());
        expect(find.byIcon(Icons.description_outlined), findsNothing);
        expect(find.byType(MobileActionIcon), findsWidgets);
      }
      await tester.tapAt(const Offset(5, 200));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cliente de demostración'));
      await tester.pumpAndSettle();
      expect(find.text('Nota de demostración'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}
