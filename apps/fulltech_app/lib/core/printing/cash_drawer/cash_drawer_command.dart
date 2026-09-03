import 'dart:typed_data';

/// Pin físico de la caja registradora en el conector RJ11/RJ12 de la
/// impresora térmica compatible.
///
/// - [CashDrawerPin.pin2] = conector "Drawer 1 / Pin 2" (el más común).
/// - [CashDrawerPin.pin5] = conector "Drawer 2 / Pin 5".
enum CashDrawerPin { pin2, pin5 }

/// Comando ESC/POS estándar para abrir la caja registradora (pulso de cajón).
///
/// Forma binaria del comando `ESC p` que usan las impresoras térmicas
/// compatibles:
///
/// ```text
/// ESC p <m> <t1> <t2>
/// 0x1B 0x70 <m> <t1> <t2>
/// ```
///
/// - `m`  : 0x00 = Pin 2, 0x01 = Pin 5.
/// - `t1` : tiempo de pulso ON  en unidades de 2 ms.
/// - `t2` : tiempo de pulso OFF en unidades de 2 ms.
///
/// Los valores por defecto son idénticos a los que ya emite el generador
/// ESC/POS móvil de FullPOS (`[0x1B, 0x70, 0x00, 0x19, 0xFA]` = Pin 2,
/// 50 ms ON / 500 ms OFF), la combinación compatible con la mayoría de
/// impresoras térmicas estándar y cajas registradoras de POS.
///
/// FullPOS NO usa variantes por marca (Epson, XPrinter, Sewoo...): envía el
/// mismo comando estándar `ESC p` a cualquier impresora térmica compatible.
/// Los ajustes avanzados (pin y duración del pulso) se modelan aquí para uso
/// interno / futuro y no se exponen a clientes normales.
class CashDrawerCommand {
  const CashDrawerCommand._();

  /// Comando por defecto: Pin 2, 50 ms ON / 500 ms OFF.
  static const List<int> defaultPulseBytes = <int>[0x1B, 0x70, 0x00, 0x19, 0xFA];

  /// Devuelve los bytes del pulso de apertura con los parámetros indicados.
  static Uint8List pulseBytes({
    CashDrawerPin pin = CashDrawerPin.pin2,
    int pulseOnUnits = 25,
    int pulseOffUnits = 250,
  }) {
    final m = pin == CashDrawerPin.pin2 ? 0x00 : 0x01;
    return Uint8List.fromList(<int>[
      0x1B,
      0x70,
      m,
      pulseOnUnits & 0xFF,
      pulseOffUnits & 0xFF,
    ]);
  }
}
