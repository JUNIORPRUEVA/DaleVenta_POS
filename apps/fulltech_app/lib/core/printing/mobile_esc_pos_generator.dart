import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../features/settings/data/mobile_printer_settings_model.dart';

class MobileEscPosGenerator {
  const MobileEscPosGenerator();

  Uint8List buildTicketBytes({
    required List<String> lines,
    required MobilePrinterSettingsModel settings,
    Uint8List? logoBytes,
    bool printLogo = false,
  }) {
    final charsPerLine = _charsPerLine(settings);
    final bytes = <int>[
      0x1B,
      0x40,
      0x1C,
      0x2E,
      0x1B,
      0x52,
      0x0C,
      0x1B,
      0x74,
      0x02,
    ];

    if (printLogo && logoBytes != null && logoBytes.isNotEmpty) {
      final logo = _buildRasterLogo(
        logoBytes,
        paperWidthMm: settings.paperWidthMm,
      );
      if (logo.isNotEmpty) {
        bytes.addAll([0x1B, 0x61, 0x01]);
        bytes.addAll(logo);
        bytes.addAll([0x1B, 0x61, 0x00]);
      }
    }

    for (final line in lines) {
      for (final wrapped in _wrapLine(line, charsPerLine)) {
        bytes.addAll(_encodeLine(wrapped, settings.encoding));
        bytes.add(0x0A);
      }
    }

    bytes.add(0x0A);
    if (settings.openCashDrawer) {
      bytes.addAll([0x1B, 0x70, 0x00, 0x19, 0xFA]);
    }
    if (settings.cutPaper) {
      bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    }
    return Uint8List.fromList(bytes);
  }

  List<int> _encodeLine(String value, String _) {
    final safe = _sanitize(value);
    return safe.codeUnits;
  }

  List<String> _wrapLine(String value, int width) {
    if (value.isEmpty) return const [''];
    if (value.length <= width) return [value];
    final lines = <String>[];
    var remaining = value;
    while (remaining.length > width) {
      var split = remaining.lastIndexOf(' ', width);
      if (split <= 0) split = width;
      lines.add(remaining.substring(0, split).trimRight());
      remaining = remaining.substring(split).trimLeft();
    }
    lines.add(remaining);
    return lines;
  }

  int _charsPerLine(MobilePrinterSettingsModel settings) {
    if (settings.paperWidthMm == 58) return 30;
    return settings.charsPerLine.clamp(42, 48);
  }

  List<int> _buildRasterLogo(Uint8List bytes, {required int paperWidthMm}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return const [];
    }

    final cropped = _cropLogo(decoded);
    final maxWidth = paperWidthMm == 58 ? 224 : 384;
    final maxHeight = paperWidthMm == 58 ? 96 : 128;
    final ratio = [
      maxWidth / cropped.width,
      maxHeight / cropped.height,
      1.0,
    ].reduce((a, b) => a < b ? a : b);
    final targetWidth = ((cropped.width * ratio).round()).clamp(1, maxWidth);
    final targetHeight = ((cropped.height * ratio).round()).clamp(1, maxHeight);
    final resized = img.copyResize(
      cropped,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );
    final widthBytes = (resized.width + 7) ~/ 8;
    final imageData = <int>[];

    for (var y = 0; y < resized.height; y++) {
      for (var xByte = 0; xByte < widthBytes; xByte++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = xByte * 8 + bit;
          if (x >= resized.width) continue;
          final pixel = resized.getPixel(x, y);
          final alpha = pixel.a.toInt();
          final luminance =
              (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114).round();
          if (alpha > 24 && luminance < 178) {
            byte |= 0x80 >> bit;
          }
        }
        imageData.add(byte);
      }
    }

    return [
      0x1D,
      0x76,
      0x30,
      0x00,
      widthBytes & 0xFF,
      (widthBytes >> 8) & 0xFF,
      resized.height & 0xFF,
      (resized.height >> 8) & 0xFF,
      ...imageData,
    ];
  }

  img.Image _cropLogo(img.Image source) {
    var minX = source.width;
    var minY = source.height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final pixel = source.getPixel(x, y);
        final alpha = pixel.a.toInt();
        final luminance = (pixel.r * 0.299 + pixel.g * 0.587 + pixel.b * 0.114)
            .round();
        if (alpha > 24 && luminance < 230) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < minX || maxY < minY) return source;
    const padding = 2;
    final x = (minX - padding).clamp(0, source.width - 1);
    final y = (minY - padding).clamp(0, source.height - 1);
    final right = (maxX + padding).clamp(0, source.width - 1);
    final bottom = (maxY + padding).clamp(0, source.height - 1);
    return img.copyCrop(
      source,
      x: x,
      y: y,
      width: right - x + 1,
      height: bottom - y + 1,
    );
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
        .replaceAll('–', '-')
        .replaceAll('º', 'o')
        .replaceAll('ª', 'a')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ü', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[\u{1F300}-\u{1FAFF}]', unicode: true), '')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }
}
