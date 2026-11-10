import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'account company menu does not render Empresa as async identity fallback',
    () {
      final source = File(
        'lib/features/account/account_menu_screens.dart',
      ).readAsStringSync();

      expect(source, isNot(contains("orElse: () => 'Empresa'")));
      expect(source, contains('const _SettingsCompanyButtonPlaceholder()'));
      expect(source, contains("if (normalized.isEmpty) return '';"));
    },
  );
}
