import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/settings/data/cloud_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'accepts matching backup manifests and rejects another company',
    () async {
      final zipPath = await _zipWithManifest({
        'companyId': 'company-a',
        'companyName': 'Empresa A',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
        'modules': ['empresa'],
      });

      final inspection = await CloudBackupService.inspectBackupZipForCompany(
        zipPath,
        expectedCompanyId: 'company-a',
      );
      expect(inspection.companyId, 'company-a');
      expect(inspection.companyName, 'Empresa A');

      expect(
        () => CloudBackupService.inspectBackupZipForCompany(
          zipPath,
          expectedCompanyId: 'company-b',
        ),
        throwsFormatException,
      );
    },
  );

  test('keeps legacy manifests without companyId inspectable', () async {
    final zipPath = await _zipWithManifest({
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'modules': ['empresa'],
    });

    final inspection = await CloudBackupService.inspectBackupZipForCompany(
      zipPath,
      expectedCompanyId: 'company-a',
    );

    expect(inspection.companyId, isNull);
    expect(inspection.modules, ['empresa']);
  });
}

Future<String> _zipWithManifest(Map<String, Object?> manifest) async {
  final dir = await Directory.systemTemp.createTemp('fullpos_backup_test_');
  final bytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  final archive = Archive()
    ..addFile(ArchiveFile('manifest.json', bytes.length, bytes));
  final zipBytes = ZipEncoder().encode(archive);
  final zipFile = File('${dir.path}/backup.zip');
  await zipFile.writeAsBytes(zipBytes, flush: true);
  return zipFile.path;
}
