import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/modules/ventas/ecf_pos_fiscal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regla de selección fiscal del POS sobre e-CF.
///
/// Se prueba lo que puede salir caro: que «Normal» no aparezca nunca sin la
/// habilitación de la empresa, que E34 jamás se ofrezca como comprobante de
/// venta, y que la preselección siga el dato del receptor en lugar de una
/// preferencia fija.
class _Builder {
  _Builder({this.enabled = true, this.allowNormal = false});

  final bool enabled;
  final bool allowNormal;
  List<String> types = const ['E31', 'E32'];
  bool allowedForCompany = true;
  bool allocatable = true;

  EcfCapabilities build() {
    return EcfCapabilities(
      enabled: enabled,
      environment: 'SANDBOX',
      certificationStatus: 'NOT_STARTED',
      productionEnabled: false,
      allowedTypes: types,
      emissionPathAvailable: false,
      allowSalesWithoutEcf: allowNormal,
      salesWithoutEcfWarning: 'Advertencia fiscal',
      documentTypes: [
        for (final type in const ['E31', 'E32', 'E34'])
          EcfDocumentTypeCapability(
            documentType: type,
            contractStatus: 'CONFIRMED_PARTIAL',
            contractAllowsEmission: true,
            allowedForCompany: allowedForCompany && types.contains(type),
            allocatable: allocatable,
          ),
      ],
    );
  }
}

void main() {
  group('modos ofrecidos', () {
    test('sin e-CF activa no se ofrece nada', () {
      expect(ecfPosFiscalModesFromCapabilities(null), isEmpty);
      expect(
        ecfPosFiscalModesFromCapabilities(_Builder(enabled: false).build()),
        isEmpty,
      );
    });

    test('con e-CF activa ofrece E31 y E32, nunca E34', () {
      final modes = ecfPosFiscalModesFromCapabilities(_Builder().build());
      expect(modes, [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32]);
      expect(modes.map((m) => m.code), isNot(contains('E34')));
    });

    test('con la excepción habilitada sigue ofreciendo E31 y E32', () {
      // El interruptor de Empresa añade «Normal» a la lista; no retira los
      // comprobantes electrónicos: el vendedor tiene que poder elegirlos.
      final modes = ecfPosFiscalModesFromCapabilities(
        _Builder(allowNormal: true).build(),
      );
      expect(modes, [
        EcfPosFiscalMode.e31,
        EcfPosFiscalMode.e32,
        EcfPosFiscalMode.normal,
      ]);
    });

    test('Normal solo aparece si la empresa habilitó la excepción', () {
      expect(
        ecfPosFiscalModesFromCapabilities(_Builder().build()),
        isNot(contains(EcfPosFiscalMode.normal)),
      );
      expect(
        ecfPosFiscalModesFromCapabilities(
          _Builder(allowNormal: true).build(),
        ),
        contains(EcfPosFiscalMode.normal),
      );
    });

    test('un tipo no habilitado para la empresa no se ofrece', () {
      final builder = _Builder()..types = const ['E32'];
      expect(ecfPosFiscalModesFromCapabilities(builder.build()), [
        EcfPosFiscalMode.e32,
      ]);
    });

    test('un tipo sin numeración asignable no se ofrece', () {
      final builder = _Builder()..allocatable = false;
      expect(ecfPosFiscalModesFromCapabilities(builder.build()), isEmpty);
    });

    test('sin capacidades del tipo no se asume permitido', () {
      final capabilities = EcfCapabilities(
        enabled: true,
        environment: 'SANDBOX',
        certificationStatus: 'NOT_STARTED',
        productionEnabled: false,
        allowedTypes: const ['E31'],
        emissionPathAvailable: false,
        documentTypes: const [],
        allowSalesWithoutEcf: true,
      );
      expect(ecfPosFiscalModesFromCapabilities(capabilities), [
        EcfPosFiscalMode.normal,
      ]);
    });
  });

  group('preselección automática', () {
    const both = [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32];

    test('con RNC y nombre elige E31', () {
      expect(
        defaultEcfPosFiscalMode(
          available: both,
          clientTaxId: '1-33-02025-3',
          clientLegalName: 'Cliente SA',
        ),
        EcfPosFiscalMode.e31,
      );
    });

    test('sin receptor elige E32', () {
      expect(
        defaultEcfPosFiscalMode(
          available: both,
          clientTaxId: null,
          clientLegalName: null,
        ),
        EcfPosFiscalMode.e32,
      );
    });

    test('con RNC pero sin nombre elige E32 (E31 exige ambos)', () {
      expect(
        defaultEcfPosFiscalMode(
          available: both,
          clientTaxId: '133020253',
          clientLegalName: '   ',
        ),
        EcfPosFiscalMode.e32,
      );
    });

    test('sin E32 disponible usa E31', () {
      expect(
        defaultEcfPosFiscalMode(
          available: const [EcfPosFiscalMode.e31],
          clientTaxId: null,
          clientLegalName: null,
        ),
        EcfPosFiscalMode.e31,
      );
    });

    test('solo «Normal» cuando no hay numeración y la empresa lo permite', () {
      expect(
        defaultEcfPosFiscalMode(
          available: const [EcfPosFiscalMode.normal],
          clientTaxId: null,
          clientLegalName: null,
        ),
        EcfPosFiscalMode.normal,
      );
    });

    test('con la excepción habilitada, Normal gana sobre E31 y E32', () {
      const withNormal = [
        EcfPosFiscalMode.e31,
        EcfPosFiscalMode.e32,
        EcfPosFiscalMode.normal,
      ];
      // Con receptor calificado: seguiría siendo válido E31, pero la decisión
      // del propietario es que Normal venga preseleccionado.
      expect(
        defaultEcfPosFiscalMode(
          available: withNormal,
          clientTaxId: '133020253',
          clientLegalName: 'Cliente SA',
        ),
        EcfPosFiscalMode.normal,
      );
      expect(
        defaultEcfPosFiscalMode(
          available: withNormal,
          clientTaxId: null,
          clientLegalName: null,
        ),
        EcfPosFiscalMode.normal,
      );
    });

    test('con la excepción apagada, el comprobante se elige solo', () {
      expect(
        defaultEcfPosFiscalMode(
          available: both,
          clientTaxId: '133020253',
          clientLegalName: 'Cliente SA',
        ),
        EcfPosFiscalMode.e31,
      );
      expect(
        defaultEcfPosFiscalMode(
          available: both,
          clientTaxId: null,
          clientLegalName: null,
        ),
        EcfPosFiscalMode.e32,
      );
    });

    test('sin opciones no inventa un modo', () {
      expect(
        defaultEcfPosFiscalMode(
          available: const [],
          clientTaxId: '133020253',
          clientLegalName: 'Cliente SA',
        ),
        isNull,
      );
    });
  });

  group('contrato del modo', () {
    test('normaliza el RNC para comparar el mismo documento', () {
      // La regla E31 compara documentos: con y sin guiones es el mismo RNC.
      expect(ecfBuyerIdentityComplete('1-33-02025-3', 'Cliente SA'), isTrue);
      expect(ecfBuyerIdentityComplete('1 33 02025 3', 'Cliente SA'), isTrue);
      expect(ecfBuyerIdentityComplete('133020253', 'Cliente SA'), isTrue);
      expect(ecfBuyerIdentityComplete('13302025', 'Cliente SA'), isFalse);
      expect(ecfBuyerIdentityComplete(null, 'Cliente SA'), isFalse);
      expect(ecfBuyerIdentityComplete('133020253', '  '), isFalse);
    });

    test('solo E31 exige receptor', () {
      expect(EcfPosFiscalMode.e31.requiresBuyer, isTrue);
      expect(EcfPosFiscalMode.e32.requiresBuyer, isFalse);
      expect(EcfPosFiscalMode.normal.requiresBuyer, isFalse);
    });

    test('el código viaja estable al backend', () {
      expect(ecfPosFiscalModeFromCode(' e31 ')?.code, 'E31');
      expect(ecfPosFiscalModeFromCode('E32')?.code, 'E32');
      expect(ecfPosFiscalModeFromCode('NORMAL')?.code, 'NORMAL');
      expect(ecfPosFiscalModeFromCode('B01'), isNull);
      expect(ecfPosFiscalModeFromCode(null), isNull);
    });
  });

  group('preselección al cambiar de cliente', () {
    const all = [
      EcfPosFiscalMode.e31,
      EcfPosFiscalMode.e32,
      EcfPosFiscalMode.normal,
    ];
    const electronic = [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32];

    test('la elección manual del vendedor no se pisa', () {
      // El vendedor eligió E31 y luego cambia el cliente: se respeta.
      expect(
        ecfResolvePreselection(
          current: EcfPosFiscalMode.e31,
          chosenByUser: true,
          available: all,
          clientTaxId: null,
          clientLegalName: null,
        ),
        EcfPosFiscalMode.e31,
      );
    });

    test(
      'con la excepción activa, el vendedor puede quedarse en Normal aunque '
      'el cliente tenga RNC',
      () {
        expect(
          ecfResolvePreselection(
            current: EcfPosFiscalMode.normal,
            chosenByUser: true,
            available: all,
            clientTaxId: '133020253',
            clientLegalName: 'Cliente SA',
          ),
          EcfPosFiscalMode.normal,
        );
      },
    );

    test('sin elección previa se propone según el receptor', () {
      expect(
        ecfResolvePreselection(
          current: null,
          chosenByUser: false,
          available: electronic,
          clientTaxId: '133020253',
          clientLegalName: 'Cliente SA',
        ),
        EcfPosFiscalMode.e31,
      );
      expect(
        ecfResolvePreselection(
          current: null,
          chosenByUser: false,
          available: electronic,
          clientTaxId: '133020253',
          clientLegalName: null,
        ),
        EcfPosFiscalMode.e32,
      );
    });

    test('si lo elegido dejó de estar disponible, se vuelve a proponer', () {
      // «Normal» ya no se ofrece (se desactivó la excepción): no se conserva.
      expect(
        ecfResolvePreselection(
          current: EcfPosFiscalMode.normal,
          chosenByUser: true,
          available: electronic,
          clientTaxId: null,
          clientLegalName: null,
        ),
        EcfPosFiscalMode.e32,
      );
    });
  });
}
