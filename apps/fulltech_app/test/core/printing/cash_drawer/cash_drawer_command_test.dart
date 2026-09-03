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
}
