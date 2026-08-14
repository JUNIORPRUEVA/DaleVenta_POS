import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const String profilePhotoUploadName = 'profile-photo.jpg';

Uint8List processProfilePhoto(Uint8List input) {
  final decoded = img.decodeImage(input);
  if (decoded == null) {
    throw const FormatException('La imagen seleccionada no es válida');
  }

  final oriented = img.bakeOrientation(decoded);
  final cropSize = oriented.width < oriented.height
      ? oriented.width
      : oriented.height;
  final cropped = img.copyCrop(
    oriented,
    x: ((oriented.width - cropSize) / 2).round(),
    y: ((oriented.height - cropSize) / 2).round(),
    width: cropSize,
    height: cropSize,
  );
  final resized = img.copyResize(
    cropped,
    width: 512,
    height: 512,
    interpolation: img.Interpolation.average,
  );

  return Uint8List.fromList(img.encodeJpg(resized, quality: 86));
}

String profilePhotoDataUrl(Uint8List bytes) {
  return 'data:image/jpeg;base64,${base64Encode(bytes)}';
}
