import 'dart:typed_data';

import 'pdf_file_actions_stub.dart'
    if (dart.library.io) 'pdf_file_actions_io.dart'
    if (dart.library.html) 'pdf_file_actions_web.dart'
    as impl;

Future<bool> savePdfBytes({
  required Uint8List bytes,
  required String fileName,
}) {
  return impl.savePdfBytes(bytes: bytes, fileName: fileName);
}
