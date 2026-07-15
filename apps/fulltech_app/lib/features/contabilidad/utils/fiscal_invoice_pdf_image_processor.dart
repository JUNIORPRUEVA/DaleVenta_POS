import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List? enhanceFiscalInvoiceImageForPdf(Uint8List sourceBytes) {
  try {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return null;

    var working = img.bakeOrientation(decoded);
    working = _trimUniformBorders(working);

    final enhanced = img.adjustColor(
      img.grayscale(working),
      contrast: 1.18,
      brightness: 0.02,
      gamma: 0.98,
    );

    final sharpened = img.convolution(
      enhanced,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
    );

    final output = Uint8List.fromList(img.encodeJpg(sharpened, quality: 92));
    if (_looksOverexposed(sharpened)) {
      return sourceBytes;
    }
    return output;
  } catch (_) {
    return sourceBytes;
  }
}

bool _looksOverexposed(img.Image image) {
  final stepX = (image.width / 24).ceil().clamp(1, image.width);
  final stepY = (image.height / 24).ceil().clamp(1, image.height);
  var bright = 0;
  var total = 0;

  for (var y = 0; y < image.height; y += stepY) {
    for (var x = 0; x < image.width; x += stepX) {
      final pixel = image.getPixel(x, y);
      final luminance = (pixel.r + pixel.g + pixel.b) / 3;
      if (luminance >= 245) bright += 1;
      total += 1;
    }
  }

  return total > 0 && bright / total >= 0.96;
}

img.Image _trimUniformBorders(img.Image source) {
  final width = source.width;
  final height = source.height;
  if (width < 40 || height < 40) return source;

  final marginX = (width * 0.06).round().clamp(1, width ~/ 4);
  final marginY = (height * 0.06).round().clamp(1, height ~/ 4);

  int left = 0;
  int right = width - 1;
  int top = 0;
  int bottom = height - 1;

  while (left < marginX && _columnLooksLikeBackground(source, left)) {
    left += 1;
  }
  while (right > width - marginX - 1 &&
      _columnLooksLikeBackground(source, right)) {
    right -= 1;
  }
  while (top < marginY && _rowLooksLikeBackground(source, top)) {
    top += 1;
  }
  while (bottom > height - marginY - 1 &&
      _rowLooksLikeBackground(source, bottom)) {
    bottom -= 1;
  }

  final cropWidth = (right - left + 1).clamp(width ~/ 2, width);
  final cropHeight = (bottom - top + 1).clamp(height ~/ 2, height);

  if (cropWidth == width && cropHeight == height) return source;

  return img.copyCrop(
    source,
    x: left.clamp(0, width - 1),
    y: top.clamp(0, height - 1),
    width: cropWidth,
    height: cropHeight,
  );
}

bool _rowLooksLikeBackground(img.Image image, int y) {
  final step = (image.width / 24).ceil().clamp(1, image.width);
  var brightPixels = 0;
  var samples = 0;

  for (var x = 0; x < image.width; x += step) {
    final pixel = image.getPixel(x, y);
    final luminance = (pixel.r + pixel.g + pixel.b) / 3;
    if (luminance >= 238) brightPixels += 1;
    samples += 1;
  }

  return samples > 0 && brightPixels / samples >= 0.92;
}

bool _columnLooksLikeBackground(img.Image image, int x) {
  final step = (image.height / 24).ceil().clamp(1, image.height);
  var brightPixels = 0;
  var samples = 0;

  for (var y = 0; y < image.height; y += step) {
    final pixel = image.getPixel(x, y);
    final luminance = (pixel.r + pixel.g + pixel.b) / 3;
    if (luminance >= 238) brightPixels += 1;
    samples += 1;
  }

  return samples > 0 && brightPixels / samples >= 0.92;
}
