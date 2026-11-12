import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/widgets/app_navigation.dart';
import 'package:flutter_test/flutter_test.dart';

UserModel _user() => UserModel(
  id: 'user-a',
  email: 'admin@test.local',
  nombreCompleto: 'Admin Test',
  telefono: '',
  role: 'ADMIN',
  companyId: 'company-a',
);

List<String> _titles(List<AppNavigationSection> sections) =>
    sections.expand((section) => section.items).map((item) => item.title).toList();

void main() {
  group('buildAppNavigationSections — función pura (sin ref.watch)', () {
    test('sin usuario no expone secciones', () {
      final sections = buildAppNavigationSections(
        null,
        multiWarehouseEnabled: true,
      );

      expect(sections, isEmpty);
    });

    test('multiWarehouseEnabled=false oculta Almacenes y Kardex', () {
      final titles = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: false),
      );

      expect(titles, isNot(contains('Almacenes')));
      expect(titles, isNot(contains('Kardex')));
      // El resto de módulos base se mantiene.
      expect(titles, contains('Productos'));
      expect(titles, contains('Facturación'));
    });

    test('multiWarehouseEnabled=true expone Almacenes y Kardex', () {
      final titles = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: true),
      );

      expect(titles, contains('Almacenes'));
      expect(titles, contains('Kardex'));
      expect(titles, contains('Productos'));
    });

    test('sin e-CF y sin piloto, la entrada de facturación electrónica no aparece',
        () {
      final titles = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: true),
      );

      expect(titles, isNot(contains('Facturación electrónica')));
    });

    test('la empresa piloto ve la entrada aunque su e-CF esté desactivado', () {
      final titles = _titles(
        buildAppNavigationSections(
          _user(),
          multiWarehouseEnabled: true,
          ecfEnabled: false,
          ecfPilotEligible: true,
        ),
      );

      // Preparar la certificación no depende de tener la emisión activada.
      expect(titles, contains('Facturación electrónica'));
    });

    test('con e-CF activado la entrada sigue apareciendo como antes', () {
      final titles = _titles(
        buildAppNavigationSections(
          _user(),
          multiWarehouseEnabled: true,
          ecfEnabled: true,
        ),
      );

      expect(titles, contains('Facturación electrónica'));
    });

    test('no duplica módulos en ninguna combinación', () {
      for (final enabled in [true, false]) {
        final titles = _titles(
          buildAppNavigationSections(
            _user(),
            multiWarehouseEnabled: enabled,
          ),
        );

        expect(
          titles.toSet().length,
          titles.length,
          reason: 'duplicado con multiWarehouseEnabled=$enabled',
        );
      }
    });

    test('las secciones vacías se descartan', () {
      final sections = buildAppNavigationSections(
        _user(),
        multiWarehouseEnabled: false,
      );

      expect(sections, isNotEmpty);
      for (final section in sections) {
        expect(section.items, isNotEmpty, reason: section.title);
      }
    });

    // Guarda de regresión del cambio de producto: el grupo «Contabilidad» y sus
    // cuatro accesos (Depósitos, Factura fiscal, Pagos, Nómina) no se dibujan en
    // el menú. Las rutas siguen existiendo en el router; lo que se retiró es
    // únicamente su representación en la navegación.
    test('el grupo Contabilidad está oculto de la navegación', () {
      final sections = buildAppNavigationSections(
        _user(),
        multiWarehouseEnabled: true,
      );
      final titles = _titles(sections);

      expect(
        sections.map((section) => section.title),
        isNot(contains('Contabilidad')),
      );
      for (final hidden in [
        'Depósitos',
        'Factura fiscal',
        'Pagos',
        'Nómina',
      ]) {
        expect(titles, isNot(contains(hidden)), reason: hidden);
      }
    });

    // Paridad desktop: `DesktopSidebar` consume exactamente esta salida. El
    // orden y el contenido deben permanecer idénticos a la línea base de PC.
    test('paridad desktop: árbol de navegación con multiWarehouseEnabled=false', () {
      final sections = buildAppNavigationSections(
        _user(),
        multiWarehouseEnabled: false,
      );

      expect(
        sections.map((section) => section.title).toList(),
        ['Principal', 'Cuenta'],
      );
      expect(_titles(sections), [
        'Clientes',
        'Facturación',
        'Lista de ventas',
        'Créditos',
        'Productos',
        'Ajuste stock',
        'Categorías',
        'Recuento',
        'Compras',
        'Reportes',
        'Usuario',
      ]);
    });

    test('paridad desktop: árbol de navegación con multiWarehouseEnabled=true', () {
      final sections = buildAppNavigationSections(
        _user(),
        multiWarehouseEnabled: true,
      );

      expect(_titles(sections), [
        'Clientes',
        'Facturación',
        'Lista de ventas',
        'Créditos',
        'Productos',
        'Ajuste stock',
        'Categorías',
        'Recuento',
        'Kardex',
        'Almacenes',
        'Compras',
        'Reportes',
        'Usuario',
      ]);
    });

    // Guarda de regresión: las acciones de efectivo se unificaron en el
    // selector «Turno». Ya no son secciones de navegación lateral, así que no
    // pueden reaparecer en los grupos comodín («Otros» / «Más módulos»).
    test('las acciones de efectivo no están en la navegación lateral', () {
      for (final enabled in [true, false]) {
        final titles = _titles(
          buildAppNavigationSections(
            _user(),
            multiWarehouseEnabled: enabled,
          ),
        );
        for (final hidden in [
          'Registrar entrada',
          'Registrar salida',
          'Historial',
        ]) {
          expect(titles, isNot(contains(hidden)), reason: hidden);
        }
      }
    });
  });

  group('visibilidad e-CF por empresa (opt-in obligatorio)', () {
    test('empresa sin e-CF: el módulo NO aparece en el menú', () {
      final titles = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: false),
      );

      expect(titles, isNot(contains('Facturación electrónica')));
      // La entrada antigua, a mitad del menú, tampoco existe.
      expect(titles, isNot(contains('Comprobantes e-CF')));
    });

    test('empresa con e-CF activada: aparece una sola vez y AL FINAL', () {
      final titles = _titles(
        buildAppNavigationSections(
          _user(),
          multiWarehouseEnabled: false,
          ecfEnabled: true,
        ),
      );

      expect(
        titles.where((title) => title == 'Facturación electrónica').length,
        1,
      );
      expect(titles.last, 'Facturación electrónica');
    });

    test('activar e-CF añade exactamente una entrada y no altera el resto', () {
      final off = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: false),
      );
      final on = _titles(
        buildAppNavigationSections(
          _user(),
          multiWarehouseEnabled: false,
          ecfEnabled: true,
        ),
      );

      expect(on.length, off.length + 1);
      expect(on.take(off.length).toList(), off);
    });

    test('los módulos tradicionales son idénticos con e-CF apagada', () {
      final off = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: false),
      );

      for (final traditional in [
        'Clientes',
        'Facturación',
        'Lista de ventas',
        'Créditos',
        'Productos',
        'Compras',
        'Reportes',
        'Usuario',
      ]) {
        expect(off, contains(traditional), reason: traditional);
      }

      // El módulo Contabilidad se retiró de la navegación por decisión de
      // producto: encender o apagar e-CF no debe reintroducirlo.
      for (final hidden in ['Factura fiscal', 'Depósitos', 'Pagos', 'Nómina']) {
        expect(off, isNot(contains(hidden)), reason: hidden);
      }
    });
  });
}
