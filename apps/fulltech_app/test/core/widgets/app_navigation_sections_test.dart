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

    // Paridad desktop: `DesktopSidebar` consume exactamente esta salida. El
    // orden y el contenido deben permanecer idénticos a la línea base de PC.
    test('paridad desktop: árbol de navegación con multiWarehouseEnabled=false', () {
      final sections = buildAppNavigationSections(
        _user(),
        multiWarehouseEnabled: false,
      );

      expect(
        sections.map((section) => section.title).toList(),
        ['Principal', 'Contabilidad', 'Cuenta'],
      );
      expect(_titles(sections), [
        'Clientes',
        'Facturación',
        'Lista de ventas',
        'Registrar entrada',
        'Registrar salida',
        'Historial',
        'Créditos',
        'Productos',
        'Ajuste stock',
        'Categorías',
        'Recuento',
        'Compras',
        'Reportes',
        'Factura fiscal',
        'Depósitos',
        'Pagos',
        'Nómina',
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
        'Registrar entrada',
        'Registrar salida',
        'Historial',
        'Créditos',
        'Productos',
        'Ajuste stock',
        'Categorías',
        'Recuento',
        'Kardex',
        'Almacenes',
        'Compras',
        'Reportes',
        'Factura fiscal',
        'Depósitos',
        'Pagos',
        'Nómina',
        'Usuario',
      ]);
    });
  });

  group('interruptor e-CF de la empresa', () {
    test('con el módulo apagado la opción no existe en el menú', () {
      final titles = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: false),
      );

      expect(titles, isNot(contains('Facturación electrónica')));
      // La entrada antigua, a mitad del menú, ya no existe.
      expect(titles, isNot(contains('Comprobantes e-CF')));
    });

    test('con el módulo encendido la opción aparece y va AL FINAL', () {
      final titles = _titles(
        buildAppNavigationSections(
          _user(),
          multiWarehouseEnabled: false,
          ecfEnabled: true,
        ),
      );

      expect(titles, contains('Facturación electrónica'));
      expect(titles.last, 'Facturación electrónica');
      expect(titles, isNot(contains('Comprobantes e-CF')));
    });

    test('encender el módulo solo AÑADE la opción: nada más cambia', () {
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

      expect(on, [...off, 'Facturación electrónica']);
    });

    test('el resto del menú es idéntico con el módulo apagado', () {
      final titles = _titles(
        buildAppNavigationSections(_user(), multiWarehouseEnabled: false),
      );

      // Sin e-CF, los módulos tradicionales siguen exactamente igual.
      expect(titles, contains('Facturación'));
      expect(titles, contains('Productos'));
      expect(titles, contains('Usuario'));
    });
  });
}
