import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) throw StateError('Missing native acceptance evidence');
    final raw = Platform.environment['RECOVERY_HOST_EVIDENCE_DIR'];
    if (raw == null || !raw.replaceAll('\\', '/').contains('/.uat/')) {
      throw StateError('An isolated host evidence directory is required');
    }
    final directory = Directory(raw);
    await directory.create(recursive: true);
    final result = Map<String, dynamic>.from(data);
    final png = result.remove('centerScreenshotPngBase64');
    final name = '${result['platform']}-${result['run']}';
    await File('${directory.path}/$name.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(result));
    if (png is String) await File('${directory.path}/$name.png').writeAsBytes(base64Decode(png));
  },
);
