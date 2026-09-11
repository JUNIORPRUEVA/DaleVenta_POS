import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source guards that fail if technical information returns to the customer UI.
///
/// These guards are intentionally simple text scans: they protect the
/// presentation layer, not the diagnostics layer.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// Removes comments so doc explanations do not produce false positives.
  String code(String path) {
    return read(path)
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '')
        .replaceAll(RegExp(r'///[^\n]*'), '')
        .toLowerCase();
  }

  group('customer error surface guards', () {
    test('notification overlay exposes no technical UI', () {
      final source = code('lib/core/debug/app_error_overlay.dart');

      const forbidden = <String>[
        'ver error',
        'copiar reporte',
        'error real',
        'stack trace',
        'endpoint',
        'httpexception',
        'dioexception',
        'apiexception',
        'stacktrace',
        'statuscode',
        'https://',
        'http://',
      ];

      for (final marker in forbidden) {
        expect(
          source.contains(marker),
          isFalse,
          reason:
              'lib/core/debug/app_error_overlay.dart must not contain "$marker". '
              'Move technical UI to the diagnostics sheet.',
        );
      }
    });

    test('technical diagnostics are gated by a compile-time flag', () {
      final overlay = read('lib/core/debug/app_error_overlay.dart');
      expect(overlay.contains('kAppDiagnosticsUiEnabled'), isTrue);

      final flag = read('lib/core/debug/app_diagnostics.dart');
      expect(flag.contains('kDebugMode'), isTrue);
      expect(flag.contains('bool.fromEnvironment'), isTrue);
    });

    test('human error copy never contains infrastructure markers', () {
      final source = code('lib/core/errors/user_facing_error.dart');

      const forbidden = <String>[
        'http://',
        'https://',
        'statuscode',
        'prisma',
        'nestjs',
        'stack trace',
        'localhost',
        'easypanel',
        'gcdndd',
        'dioexception',
        'httpexception',
      ];

      for (final marker in forbidden) {
        expect(
          source.contains(marker),
          isFalse,
          reason: 'Human copy must not contain "$marker".',
        );
      }
    });

    test('reporter no longer uses "Algo salio mal" as user copy', () {
      final source = code('lib/core/debug/app_error_reporter.dart');

      expect(source.contains('algo salio mal'), isFalse);
    });

    test('no widget renders a bare exception as text', () {
      final bareException = RegExp(r"Text\(\s*'\$e'\s*\)");
      final bareNamed = RegExp(r"Text\(\s*'\$\{?(error|exception|err)\}?'\s*\)");
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = entity.readAsStringSync();
        if (bareException.hasMatch(content) || bareNamed.hasMatch(content)) {
          offenders.add(entity.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Use userSafeErrorMessage(...) instead of rendering a raw '
            'exception (found in: ${offenders.join(', ')}).',
      );
    });
  });
}
