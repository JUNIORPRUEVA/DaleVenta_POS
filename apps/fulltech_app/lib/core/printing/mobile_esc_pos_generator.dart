import 'dart:convert';
import 'dart:typed_data';

import '../../features/settings/data/mobile_printer_settings_model.dart';

class MobileEscPosGenerator {
  const MobileEscPosGenerator();

  Uint8List buildTicketBytes({
    required List<String> lines,
    required MobilePrinterSettingsModel settings,
  }) {
    final bytes = <int>[
      0x1B,
      0x40,
      0x1B,
      0x74,
      settings.encoding.toLowerCase() == 'cp437' ? 0 : 16,
    ];

    for (final line in lines) {
      bytes.addAll(_encodeLine(line, settings.encoding));
      bytes.add(0x0A);
    }

    bytes.addAll([0x0A, 0x0A]);
    if (settings.openCashDrawer) {
      bytes.addAll([0x1B, 0x70, 0x00, 0x19, 0xFA]);
    }
    if (settings.cutPaper) {
      bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    }
    return Uint8List.fromList(bytes);
  }

  List<int> _encodeLine(String value, String encodingName) {
    final safe = _sanitize(value);
    if (encodingName.toLowerCase() == 'utf8') return utf8.encode(safe);
    return safe.codeUnits.map((code) => code <= 255 ? code : 63).toList();
  }

  String _sanitize(String value) {
    return value
        .replaceAll('\x1B', '')
        .replaceAll('\x1D', '')
        .replaceAll('\x00', '')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('—', '-')
        .replaceAll('–', '-');
  }
}
