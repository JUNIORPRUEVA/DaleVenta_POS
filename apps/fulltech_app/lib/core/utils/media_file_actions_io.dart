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

  var targetPath = path.trim();
  final extension = allowedExtensions.isEmpty
      ? ''
      : allowedExtensions.first.trim().replaceFirst(RegExp(r'^\.'), '');
  if (extension.isNotEmpty &&
      !targetPath.toLowerCase().endsWith('.${extension.toLowerCase()}')) {
    targetPath = '$targetPath.$extension';
  }

  await File(targetPath).writeAsBytes(bytes, flush: true);
  return true;
}
