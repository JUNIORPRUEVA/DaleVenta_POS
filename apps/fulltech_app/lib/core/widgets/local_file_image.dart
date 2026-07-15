import 'package:flutter/widgets.dart';

import 'local_file_image_stub.dart'
    if (dart.library.io) 'local_file_image_io.dart';

Widget localFileImage({required String path, BoxFit fit = BoxFit.cover}) {
  return localFileImageImpl(path: path, fit: fit);
}
