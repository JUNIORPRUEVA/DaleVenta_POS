import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/mobile_esc_pos_generator.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('prints logo raster command and thermal-safe spanish text', () {
    final logo = img.Image(width: 16, height: 16);
    img.fill(logo, color: img.ColorRgb8(255, 255, 255));
    img.fillCircle(logo, x: 8, y: 8, radius: 6, color: img.ColorRgb8(0, 0, 0));

    final bytes = const MobileEscPosGenerator().buildTicketBytes(
      lines: const ['Cajón: información áéíóú ñ'],
      settings: const MobilePrinterSettingsModel(
        paperWidthMm: 58,
        charsPerLine: 32,
        encoding: 'latin1',
        cutPaper: false,
      ),
      logoBytes: Uint8List.fromList(img.encodePng(logo)),
      printLogo: true,
    );

    expect(_containsSequence(bytes, const [0x1D, 0x76, 0x30, 0x00]), isTrue);
    expect(_containsSequence(bytes, 'Cajon'.codeUnits), isTrue);
    expect(_containsSequence(bytes, 'informacion'.codeUnits), isTrue);
    expect(bytes, isNot(contains(0xA2)));
    expect(bytes, isNot(contains(0xA4)));
  });
}

bool _containsSequence(Uint8List bytes, List<int> sequence) {
  for (var i = 0; i <= bytes.length - sequence.length; i++) {
    var matches = true;
    for (var j = 0; j < sequence.length; j++) {
      if (bytes[i + j] != sequence[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
