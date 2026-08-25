import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio de ajustes de impresión fake (sin red/almacenamiento real).
class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  @override
  Future<PrinterSettingsModel> getOrCreate() async {
    return const PrinterSettingsModel(
      selectedPrinterName: '',
      copies: 1,
      autoCut: true,
      warrantyPolicy: 'Garantía según política.',
    );
  }
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      printerSettingsRepositoryProvider.overrideWith(
        (_) => _FakePrinterSettingsRepository(),
      ),
    ],
  );
}

const _technicalPatterns = [
  'Invalid argument',
  'DynamicLibrary',
  'Failed to load',
  'Exception',
];

void main() {
  group('UnifiedTicketPrinter — no carga DLLs de Windows en móvil', () {
    test('construir UnifiedTicketPrinter en Android NO lanza '
        '"Failed to load dynamic library" (regresión)', () async {
      // Simula la plataforma Android.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final container = _container();
      addTearDown(container.dispose);

      // Antes del fix, leer el provider construía FfiWindowsRawSpooler →
      // DynamicLibrary.open('winspool.drv') → ArgumentError en Android.
      expect(
        container.read(unifiedTicketPrinterProvider),
        isA<UnifiedTicketPrinter>(),
      );
    });

    test(
      'RAW en Android devuelve mensaje amigable, sin texto técnico',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final container = _container();
        addTearDown(container.dispose);

        final printer = container.read(unifiedTicketPrinterProvider);
        final result = await printer.printWindowsRawEscPosBytes(
          bytes: Uint8List.fromList(const [0x1b, 0x40]),
          ticketNumber: 'CIERRE-1',
          documentName: 'Cierre de turno CIERRE-1',
          printerName: '',
        );

        expect(result.success, isFalse);
        for (final pattern in _technicalPatterns) {
          expect(
            result.message,
            isNot(contains(pattern)),
            reason: 'no debe exponer "$pattern" al usuario',
          );
        }
      },
    );

    test('en Android el transporte RAW por defecto no es el FFI de Windows '
        '(no intenta abrir winspool.drv)', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      // La construcción no debe lanzar y el camino RAW debe fallar con
      // mensaje claro de plataforma (no con error de librería dinámica).
      final container = _container();
      addTearDown(container.dispose);
      final printer = container.read(unifiedTicketPrinterProvider);
      final result = await printer.printWindowsRawEscPosBytes(
        bytes: Uint8List.fromList(const [0x1b]),
        ticketNumber: 'T-2',
        documentName: 'Test',
      );
      expect(result.message, contains('Windows'));
    });
  });
}
