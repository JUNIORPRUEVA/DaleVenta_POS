import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login screen lets router handle post-login navigation', () {
    final source = File(
      'lib/features/auth/presentation/login_screen.dart',
    ).readAsStringSync();

    expect(
      source,
      isNot(contains("import 'package:go_router/go_router.dart'")),
    );
    expect(source, isNot(contains('context.go(')));
    expect(source, contains('.login(_emailCtrl.text, _passwordCtrl.text)'));
  });
}
