import 'package:daleventa_pos/core/printing/cash_drawer/cash_drawer_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashDrawerCommand', () {
    test('default pulse bytes use Pin 2 with safe on/off timing', () {
      expect(CashDrawerCommand.pulseBytes(), [0x1B, 0x70, 0x00, 0x19, 0xFA]);
      expect(CashDrawerCommand.defaultPulseBytes, [0x1B, 0x70, 0x00, 0x19, 0xFA]);
    });

    test('pin 5 uses m = 0x01', () {
      expect(
        CashDrawerCommand.pulseBytes(pin: CashDrawerPin.pin5),
        [0x1B, 0x70, 0x01, 0x19, 0xFA],
      );
    });

    test('custom on/off durations are honored (clamped to a byte)', () {
      expect(
        CashDrawerCommand.pulseBytes(pulseOnUnits: 100, pulseOffUnits: 200),
        [0x1B, 0x70, 0x00, 100, 200],
      );
    });

    test('never contains vendor/brand specific data', () {
      // El comando es ESC/POS estándar; no depende de Epson/XPrinter/Sewoo.
      final bytes = CashDrawerCommand.pulseBytes();
      expect(bytes.length, 5);
      expect(bytes[0], 0x1B);
      expect(bytes[1], 0x70);
    });
  });

  group('CashDrawerCommand · canal configurable', () {
    test('automatic resolves to Pin 2 and keeps the legacy pulse', () {
      expect(CashDrawerChannel.automatic.resolvedPin, CashDrawerPin.pin2);
      expect(
        CashDrawerCommand.pulseBytesForChannel(CashDrawerChannel.automatic),
        CashDrawerCommand.defaultPulseBytes,
      );
    });

    test('pin2 channel equals the historical pulse', () {
      expect(
        CashDrawerCommand.pulseBytesForChannel(CashDrawerChannel.pin2),
        [0x1B, 0x70, 0x00, 0x19, 0xFA],
      );
    });

    test('pin5 channel sends m = 0x01 (Drawer 2)', () {
      expect(CashDrawerChannel.pin5.resolvedPin, CashDrawerPin.pin5);
      expect(
        CashDrawerCommand.pulseBytesForChannel(CashDrawerChannel.pin5),
        [0x1B, 0x70, 0x01, 0x19, 0xFA],
      );
    });

    test('fromValue maps empty/unknown values to automatic', () {
      expect(CashDrawerChannel.fromValue(null), CashDrawerChannel.automatic);
      expect(CashDrawerChannel.fromValue(''), CashDrawerChannel.automatic);
      expect(CashDrawerChannel.fromValue('automatic'), CashDrawerChannel.automatic);
      expect(CashDrawerChannel.fromValue('pin2'), CashDrawerChannel.pin2);
      expect(CashDrawerChannel.fromValue('pin5'), CashDrawerChannel.pin5);
      // Nunca se ramifica por marca de impresora.
      expect(CashDrawerChannel.fromValue('SEWOO'), CashDrawerChannel.automatic);
    });

    test('labels describe the physical connector, not the brand', () {
      expect(CashDrawerPin.pin2.label, contains('Pin 2'));
      expect(CashDrawerPin.pin5.label, contains('Pin 5'));
      expect(CashDrawerChannel.pin2.label, contains('Pin 2'));
      expect(CashDrawerChannel.pin5.label, contains('Pin 5'));
    });

    test('profile identity is generic EPSON_ESC_POS (never brand specific)',
        () {
      expect(CashDrawerCommand.profileId, 'EPSON_ESC_POS');
      expect(CashDrawerCommand.profileId, startsWith('EPSON'));
      expect(
        CashDrawerCommand.profileId.toUpperCase(),
        isNot(contains('SEWOO')),
      );
    });

    test('pulse defaults stay at the safe 50 ms ON / 500 ms OFF', () {
      expect(CashDrawerCommand.defaultPulseOnUnits, 25);
      expect(CashDrawerCommand.defaultPulseOffUnits, 250);
      expect(CashDrawerCommand.defaultPulseOnUnits * 2, 50);
      expect(CashDrawerCommand.defaultPulseOffUnits * 2, 500);
    });

    test(
      'audit: never emits the real-time DLE DC4 pulse (0x10 0x14)',
      () {
        // Auditoria FASE 9: DLE DC4 no se implementa (sin evidencia SEWOO).
        for (final channel in CashDrawerChannel.values) {
          final bytes = CashDrawerCommand.pulseBytesForChannel(channel);
          expect(bytes.length, 5, reason: 'ESC p m t1 t2 = 5 bytes');
          expect(bytes[0], 0x1B);
          expect(bytes[1], 0x70);
          expect(bytes.contains(0x10), isFalse);
          expect(bytes.contains(0x14), isFalse);
        }
      },
    );

    test('byte-for-byte matrix: automatic / pin2 / pin5', () {
      // Matriz obligatoria (FASE 14).
      expect(
        CashDrawerCommand.pulseBytesForChannel(CashDrawerChannel.automatic),
        [0x1B, 0x70, 0x00, 0x19, 0xFA],
      );
      expect(
        CashDrawerCommand.pulseBytesForChannel(CashDrawerChannel.pin2),
        [0x1B, 0x70, 0x00, 0x19, 0xFA],
      );
      expect(
        CashDrawerCommand.pulseBytesForChannel(CashDrawerChannel.pin5),
        [0x1B, 0x70, 0x01, 0x19, 0xFA],
      );
      // Nunca ambos pulsos en una misma apertura.
      expect(CashDrawerCommand.defaultPulseBytes.length, 5);
    });

    test('describe() reports the Epson ESC/POS parameters for support', () {
      expect(
        CashDrawerCommand.describe(CashDrawerPin.pin2),
        contains('m=0'),
      );
      expect(
        CashDrawerCommand.describe(CashDrawerPin.pin5),
        contains('m=1'),
      );
      expect(CashDrawerCommand.describe(CashDrawerPin.pin2), contains('50 ms'));
      expect(CashDrawerCommand.describe(CashDrawerPin.pin2), contains('500 ms'));
    });
  });
}
