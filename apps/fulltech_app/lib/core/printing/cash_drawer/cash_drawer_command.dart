import 'dart:typed_data';

/// Pin físico de la caja registradora en el conector RJ11/RJ12 de la
/// impresora térmica compatible.
///
/// - [CashDrawerPin.pin2] = conector "Drawer 1 / Pin 2" (el más común).
/// - [CashDrawerPin.pin5] = conector "Drawer 2 / Pin 5".
enum CashDrawerPin {
  pin2,
  pin5;

  /// Nombre legible para diagnóstico (logs internos / soporte técnico).
  String get label {
    switch (this) {
      case CashDrawerPin.pin2:
        return 'Drawer 1 (Pin 2)';
      case CashDrawerPin.pin5:
        return 'Drawer 2 (Pin 5)';
    }
  }
}

/// Canal de apertura configurable por el usuario/técnico.
///
/// Existe porque el pinout eléctrico del cable RJ11/RJ12 **no es idéntico**
/// entre impresoras y gavetas: una gaveta que abre por `Pin 2` en una
/// impresora puede requerir `Pin 5` en otro modelo (p. ej. SEWOO SLK-TS100
/// con cable/estuche de gaveta distinto). En lugar de ramas por marca
/// (`if (name.contains('SEWOO'))`) se expone la capacidad física real.
///
/// - [CashDrawerChannel.automatic]: usa [CashDrawerPin.pin2]. Es el valor por
///   defecto y **preserva exactamente** el pulso histórico de FullPOS.
/// - [CashDrawerChannel.pin2]: fuerza "Drawer 1 / Pin 2".
/// - [CashDrawerChannel.pin5]: fuerza "Drawer 2 / Pin 5".
enum CashDrawerChannel {
  automatic,
  pin2,
  pin5;

  static CashDrawerChannel fromValue(String? value) {
    switch ((value ?? '').trim()) {
      case 'pin2':
        return CashDrawerChannel.pin2;
      case 'pin5':
        return CashDrawerChannel.pin5;
      case 'automatic':
      default:
        return CashDrawerChannel.automatic;
    }
  }

  /// Pin efectivo del pulso. `automatic` resuelve a Pin 2 (comportamiento
  /// histórico de FullPOS, sin cambios para las instalaciones existentes).
  CashDrawerPin get resolvedPin {
    switch (this) {
      case CashDrawerChannel.automatic:
      case CashDrawerChannel.pin2:
        return CashDrawerPin.pin2;
      case CashDrawerChannel.pin5:
        return CashDrawerPin.pin5;
    }
  }

  String get label {
    switch (this) {
      case CashDrawerChannel.automatic:
        return 'Automático (recomendado)';
      case CashDrawerChannel.pin2:
        return 'Drawer 1 / Pin 2';
      case CashDrawerChannel.pin5:
        return 'Drawer 2 / Pin 5';
    }
  }
}

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
/// Lo que sí varía entre instalaciones es el **canal físico** de la gaveta,
/// por eso se modela con [CashDrawerChannel] (configurable en Ajustes de
/// impresora) en lugar de ramas por nombre de impresora.
class CashDrawerCommand {
  const CashDrawerCommand._();

  /// Identificador del perfil de comando usado por FullPOS.
  ///
  /// Genérico y estándar, NO por marca: la familia de comandos es la de
  /// Epson `ESC p m t1 t2`, y la CR-330K declara explícitamente
  /// compatibilidad "Epson standard". Así el mismo perfil sirve para
  /// cualquier impresora ESC/POS compatible.
  static const String profileId = 'EPSON_ESC_POS';

  /// Duración del pulso ON por defecto: 25 × 2 ms = 50 ms.
  static const int defaultPulseOnUnits = 25;

  /// Duración del pulso OFF por defecto: 250 × 2 ms = 500 ms.
  static const int defaultPulseOffUnits = 250;

  /// Comando por defecto: Pin 2, 50 ms ON / 500 ms OFF.
  ///
  /// Este es el comando histórico de FullPOS y debe seguir siendo el
  /// predeterminado para no romper instalaciones existentes.
  ///
  /// Nota (FASE 9 de auditoría): Epson también define el comando real-time
  /// `DLE DC4` (0x10 0x14) para el pulso de gaveta. FullPOS **no** lo emite:
  /// no existe evidencia suficiente de soporte explícito en la SEWOO
  /// SLK-TS100 y el comando principal sigue siendo `ESC p`, que es el
  /// estándar de apertura ya utilizado y validado.
  static const List<int> defaultPulseBytes = <int>[0x1B, 0x70, 0x00, 0x19, 0xFA];

  /// Descripción legible del pulso (para logs/reportes de soporte).
  static String describe(CashDrawerPin pin) {
    final onMs = defaultPulseOnUnits * 2;
    final offMs = defaultPulseOffUnits * 2;
    return 'ESC p m=${pin == CashDrawerPin.pin2 ? 0x00 : 0x01} '
        't1=$defaultPulseOnUnits t2=$defaultPulseOffUnits '
        '($onMs ms ON / $offMs ms OFF, ${pin.label})';
  }

  /// Devuelve los bytes del pulso de apertura con los parámetros indicados.
  static Uint8List pulseBytes({
    CashDrawerPin pin = CashDrawerPin.pin2,
    int pulseOnUnits = defaultPulseOnUnits,
    int pulseOffUnits = defaultPulseOffUnits,
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

  /// Devuelve los bytes del pulso para el canal configurado.
  ///
  /// [CashDrawerChannel.automatic] mantiene el pulso histórico de FullPOS
  /// (Pin 2), por lo que las instalaciones que hoy funcionan no cambian.
  static Uint8List pulseBytesForChannel(
    CashDrawerChannel channel, {
    int pulseOnUnits = defaultPulseOnUnits,
    int pulseOffUnits = defaultPulseOffUnits,
  }) {
    return pulseBytes(
      pin: channel.resolvedPin,
      pulseOnUnits: pulseOnUnits,
      pulseOffUnits: pulseOffUnits,
    );
  }
}
