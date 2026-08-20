import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:daleventa_pos/core/auth/token_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TokenStorage().clearTokens();
  exit(0);
}
