import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> saveMediaBytes({
  required Uint8List bytes,
  required String fileName,
  required List<String> allowedExtensions,
  String? mimeType,
}) async {
  var downloadName = fileName.trim().isEmpty ? 'archivo' : fileName.trim();
  final extension = allowedExtensions.isEmpty
      ? ''
      : allowedExtensions.first.trim().replaceFirst(RegExp(r'^\.'), '');
  if (extension.isNotEmpty &&
      !downloadName.toLowerCase().endsWith('.${extension.toLowerCase()}')) {
    downloadName = '$downloadName.$extension';
  }

  final dataUrl = Uri.dataFromBytes(
    bytes,
    mimeType: mimeType ?? 'application/octet-stream',
  ).toString();

  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = downloadName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  return true;
}
