import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/widgets/app_drawer.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los grupos del drawer siguen siendo alcanzables en pantallas pequeñas.
/// Las opciones de «Más módulos» no deben reaparecer, ni siquiera con e-CF activo.
class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

UserModel _adminUser() => UserModel(
  id: 'user-admin',
  email: 'admin@test.local',
  nombreCompleto: 'Admin Test',
  telefono: '',
  role: 'ADMIN',
  companyId: 'company-a',
  companyName: 'FULLTECH, SRL',
);

/// Repositorio de caja mínimo: el menú solo necesita saber si hay turno.
class _SilentCashRepository implements CashRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();

  @override
  Future<CashGateState> state() async =>
      const CashGateState(businessDate: '2026-08-22', canOperate: false);
}

ProviderContainer _buildContainer() {
  return ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: _adminUser(),
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          ),
        ),
      ),
      cashRepositoryProvider.overrideWithValue(_SilentCashRepository()),
      // Activar e-CF no debe añadir módulos extra al drawer.
      companySettingsProvider.overrideWith(
        (ref) async => CompanySettings.empty().copyWith(ecfEnabled: true),
      ),
    ],
  );
}

Widget _buildHost(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (buttonContext) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(buttonContext).openDrawer(),
              ),
            ),
          ),
          drawer: AppDrawer(currentUser: _adminUser()),
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

Finder _drawerScrollable() => find
    .descendant(of: find.byType(AppDrawer), matching: find.byType(Scrollable))
    .first;

/// Desplaza el menú hasta que la entrada esté **visible dentro del área del
/// menú** (la lista es perezosa: los hijos se construyen al acercarse, y estar
/// construido no significa estar en pantalla).
Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  final scroll = _drawerScrollable();
  for (var i = 0; i < 30; i++) {
    if (finder.evaluate().isNotEmpty) {
      final viewport = tester.getRect(scroll);
      final rect = tester.getRect(finder.last);
      if (rect.top >= viewport.top - 0.5 &&
          rect.bottom <= viewport.bottom + 0.5) {
        return;
      }
    }
    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();
  }
  fail('no se pudo dejar visible la entrada del menú: $finder');
}

/// La opción debe estar dentro de la pantalla **y** poder pulsarse.
void _expectReachable(WidgetTester tester, String etiqueta) {
  final altura = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final rect = tester.getRect(find.text(etiqueta).last);
  expect(
    rect.top,
    greaterThanOrEqualTo(0),
    reason: '«$etiqueta» quedó por encima de la pantalla',
  );
  expect(
    rect.bottom,
    lessThanOrEqualTo(altura),
    reason:
        '«$etiqueta» debe quedar dentro de la pantalla '
        '(pantalla=$altura, borde inferior=${rect.bottom})',
  );
  expect(
    find.text(etiqueta).hitTestable(),
    findsWidgets,
    reason: '«$etiqueta» debe poder pulsarse, no solo existir',
  );
}

Future<void> _expectAllOptionsReachable(WidgetTester tester) async {
  expect(
    find.byType(AppDrawer),
    findsOneWidget,
    reason: 'el drawer no se abrió',
  );
  expect(
    _drawerScrollable(),
    findsOneWidget,
    reason: 'el menú no tiene un área desplazable',
  );

  final groups = <String, List<String>>{
    'Ventas': ['Facturación', 'Lista de ventas'],
    'Cliente': ['Cliente', 'Cotizaciones', 'Créditos'],
    'Inventario': ['Productos', 'Ajuste stock', 'Categorías', 'Recuento'],
    'Compras': [
      'Nueva compra',
      'Lista de compra',
      'Suplidores',
      'Facturas',
      'Productos por comprar',
    ],
  };
  Future<void> scrollToTop() async {
    for (var i = 0; i < 8; i++) {
      await tester.drag(_drawerScrollable(), const Offset(0, 400));
      await tester.pumpAndSettle();
    }
  }

  for (final entry in groups.entries) {
    await scrollToTop();
    await _scrollUntilFound(tester, find.text(entry.key));
    await tester.tap(find.text(entry.key).first);
    await tester.pumpAndSettle();
    for (final label in entry.value) {
      await _scrollUntilFound(tester, find.text(label));
      _expectReachable(tester, label);
    }
    await scrollToTop();
    await _scrollUntilFound(tester, find.text(entry.key));
    await tester.tap(find.text(entry.key).first);
    await tester.pumpAndSettle();
  }

  await _scrollUntilFound(tester, find.text('Reportes'));
  _expectReachable(tester, 'Reportes');
  await _scrollUntilFound(tester, find.text('Facturación electrónica'));
  _expectReachable(tester, 'Facturación electrónica');
  expect(find.text('FullPOS').hitTestable(), findsWidgets);
  for (final label in [
    'Más módulos',
    'Depósitos',
    'Pagos',
    'Nómina',
  ]) {
    expect(
      find.text(label),
      findsNothing,
      reason: 'Los módulos adicionales se retiraron del drawer',
    );
  }
}

void main() {
  group('Drawer — todas las opciones alcanzables', () {
    testWidgets('teléfono pequeño 390x500', (tester) async {
      tester.view.physicalSize = const Size(390, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildHost(container));
      await _openDrawer(tester);
      await _expectAllOptionsReachable(tester);
    });

    testWidgets('portátil con escala alta 1280x420', (tester) async {
      tester.view.physicalSize = const Size(1280, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = _buildContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildHost(container));
      await _openDrawer(tester);
      await _expectAllOptionsReachable(tester);
    });
  });
}
