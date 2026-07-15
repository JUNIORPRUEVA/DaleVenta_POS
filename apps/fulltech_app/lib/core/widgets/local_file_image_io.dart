import 'dart:io';

import 'package:flutter/widgets.dart';

Widget localFileImageImpl({required String path, BoxFit fit = BoxFit.cover}) {
  return Image.file(File(path), fit: fit);
}
