import 'dart:typed_data';

import 'media_file_actions_stub.dart'
    if (dart.library.io) 'media_file_actions_io.dart'
    if (dart.library.html) 'media_file_actions_web.dart'
    as impl;

Future<bool> saveMediaBytes({
  required Uint8List bytes,
  required String fileName,
  required List<String> allowedExtensions,
  String? mimeType,
}) {
  return impl.saveMediaBytes(
    bytes: bytes,
    fileName: fileName,
    allowedExtensions: allowedExtensions,
    mimeType: mimeType,
  );
}
