import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveMediaBytes({
  required Uint8List bytes,
  required String fileName,
  required List<String> allowedExtensions,
  String? mimeType,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Guardar archivo',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: allowedExtensions,
  );

  if (path == null || path.trim().isEmpty) return false;

  await File(path).writeAsBytes(bytes, flush: true);
  return true;
}
