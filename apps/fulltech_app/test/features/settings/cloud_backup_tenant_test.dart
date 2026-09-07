import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daleventa_pos/core/api/api_routes.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/features/settings/data/cloud_backup_service.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('createCloudBackup writes a non-empty tenant-aware ZIP', () async {
    final backupRoot = await Directory.systemTemp.createTemp(
      'fullpos_backup_root_',
    );
    addTearDown(() => backupRoot.delete(recursive: true));

    final dio = Dio(BaseOptions(baseUrl: 'https://backup.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        expect(options.queryParameters, isEmpty);
        return ResponseBody.fromString(
          jsonEncode({'items': <Object?>[], 'data': <Object?>[]}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_TestAuthController.new),
        dioProvider.overrideWithValue(dio),
        companySettingsRepositoryProvider.overrideWithValue(
          _FakeCompanySettingsRepository(),
        ),
        printerSettingsRepositoryProvider.overrideWithValue(
          _FakePrinterSettingsRepository(),
        ),
        cloudBackupServiceProvider.overrideWith(
          (ref) => CloudBackupService(ref, dio, backupRootOverride: backupRoot),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container
        .read(cloudBackupServiceProvider)
        .createCloudBackup();

    final zipFile = File(result.zipPath);
    expect(await zipFile.exists(), isTrue);
    expect(await zipFile.length(), greaterThan(22));

    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    final names = archive.files.map((file) => file.name).toList();
    expect(names, contains(contains('manifest.json')));
    expect(names, contains(contains('empresa.json')));
    expect(names, contains(contains('impresora_local.json')));

    final inspection = await CloudBackupService.inspectBackupZipForCompany(
      result.zipPath,
      expectedCompanyId: '165e3fca-6225-479b-8805-d2205f10536c',
    );
    expect(result.status, CloudBackupStatus.complete);
    expect(inspection.validationStatus, CloudBackupValidationStatus.valid);
    expect(inspection.backupStatus, CloudBackupStatus.complete);
    expect(inspection.backupType, CloudBackupType.manual);
    expect(
      inspection.backupFormatVersion,
      CloudBackupService.backupFormatVersion,
    );
    expect(inspection.companyId, '165e3fca-6225-479b-8805-d2205f10536c');
    expect(inspection.companyName, 'FULLTECH, SRL');
    expect(await Directory(result.folderPath).exists(), isFalse);
  });

  test(
    'accepts matching backup manifests and rejects another company',
    () async {
      final zipPath = await _zipWithManifest(_manifestForCompany('company-a'));

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

  test('recognizes canonical backend dvbackup as restorable', () async {
    final zipPath = await _canonicalZipForCompany(
      '165e3fca-6225-479b-8805-d2205f10536c',
    );

    final inspection = await CloudBackupService.inspectBackupZipForCompany(
      zipPath,
      expectedCompanyId: '165e3fca-6225-479b-8805-d2205f10536c',
    );

    expect(inspection.isCanonical, isTrue);
    expect(inspection.format, CloudBackupFormat.canonical);
    expect(inspection.canRestoreByDefault, isTrue);
    expect(inspection.companyName, 'FULLTECH, SRL');
    expect(inspection.modules, contains('products'));
  });

  test('server upload validation maps canonical preview', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://backup.test'))
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        expect(options.path, ApiRoutes.backupsValidateUpload);
        return ResponseBody.fromString(
          jsonEncode({
            'status': 'VALID',
            'format': 'CANONICAL',
            'errors': <String>[],
            'warnings': <String>[],
            'manifest': {
              'backupId': '33333333-3333-4333-8333-333333333333',
              'companyId': '165e3fca-6225-479b-8805-d2205f10536c',
              'companyNameSnapshot': 'FULLTECH, SRL',
              'backupType': 'MANUAL',
              'backupStatus': 'COMPLETE',
              'createdAt': '2026-09-06T00:00:00.000Z',
              'modules': ['products'],
              'recordCounts': {'products': 2},
              'formatVersion': 2,
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_TestAuthController.new),
        cloudBackupServiceProvider.overrideWith(
          (ref) => CloudBackupService(ref, dio),
        ),
      ],
    );
    addTearDown(container.dispose);

    final preview = await container
        .read(cloudBackupServiceProvider)
        .validateCanonicalUpload(
          bytes: Uint8List.fromList([1, 2, 3]),
          fileName: 'Backup.dvbackup',
        );

    expect(preview.canRestore, isTrue);
    expect(preview.companyId, '165e3fca-6225-479b-8805-d2205f10536c');
    expect(preview.recordCounts['products'], 2);
  });

  test('rejects legacy manifests without companyId', () async {
    final zipPath = await _zipWithManifest({
      'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      'modules': ['empresa'],
    });

    expect(
      () => CloudBackupService.inspectBackupZipForCompany(
        zipPath,
        expectedCompanyId: 'company-a',
      ),
      throwsFormatException,
    );
  });

  test('partial backups are blocked by restore guard', () async {
    final backupRoot = await Directory.systemTemp.createTemp(
      'fullpos_backup_root_',
    );
    addTearDown(() => backupRoot.delete(recursive: true));
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(_TestAuthController.new),
        cloudBackupServiceProvider.overrideWith(
          (ref) =>
              CloudBackupService(ref, Dio(), backupRootOverride: backupRoot),
        ),
      ],
    );
    addTearDown(container.dispose);
    final zipPath = await _zipWithManifest(
      _manifestForCompany(
        '165e3fca-6225-479b-8805-d2205f10536c',
        status: 'PARTIAL',
        moduleOverride: {
          'productos': {'status': 'FAILED', 'records': 0, 'error': 'HTTP 400'},
        },
      ),
    );

    await expectLater(
      container
          .read(cloudBackupServiceProvider)
          .assertBackupRestorable(zipPath),
      throwsStateError,
    );
  });

  test(
    'retention deletes only old automatic backups for the active company',
    () async {
      final backupRoot = await Directory.systemTemp.createTemp(
        'fullpos_backup_retention_',
      );
      addTearDown(() => backupRoot.delete(recursive: true));
      final companyA = Directory(
        '${backupRoot.path}/165e3fca-6225-479b-8805-d2205f10536c',
      );
      final companyB = Directory('${backupRoot.path}/company-b');
      await companyA.create(recursive: true);
      await companyB.create(recursive: true);

      for (var i = 0; i < 20; i++) {
        await _zipWithManifest(
          _manifestForCompany(
            '165e3fca-6225-479b-8805-d2205f10536c',
            backupId: 'auto-a-$i',
            backupType: 'AUTOMATIC',
            createdAt: DateTime(2026, 1, 1).add(Duration(days: i)),
          ),
          directory: companyA,
          fileName: 'auto_a_$i.zip',
        );
      }
      for (var i = 0; i < 3; i++) {
        await _zipWithManifest(
          _manifestForCompany(
            '165e3fca-6225-479b-8805-d2205f10536c',
            backupId: 'manual-a-$i',
            backupType: 'MANUAL',
            createdAt: DateTime(2026, 2, 1).add(Duration(days: i)),
          ),
          directory: companyA,
          fileName: 'manual_a_$i.zip',
        );
      }
      for (var i = 0; i < 8; i++) {
        await _zipWithManifest(
          _manifestForCompany(
            'company-b',
            backupId: 'auto-b-$i',
            backupType: 'AUTOMATIC',
            createdAt: DateTime(2026, 1, 1).add(Duration(days: i)),
          ),
          directory: companyB,
          fileName: 'auto_b_$i.zip',
        );
      }
      await File('${companyA.path}/unknown.zip').writeAsString('not a zip');

      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(_TestAuthController.new),
          cloudBackupServiceProvider.overrideWith(
            (ref) =>
                CloudBackupService(ref, Dio(), backupRootOverride: backupRoot),
          ),
        ],
      );
      addTearDown(container.dispose);

      final deleted = await container
          .read(cloudBackupServiceProvider)
          .cleanupAutomaticBackups(
            companyId: '165e3fca-6225-479b-8805-d2205f10536c',
          );

      expect(deleted, 5);
      final companyAFiles = companyA.listSync().whereType<File>().toList();
      final companyBFiles = companyB.listSync().whereType<File>().toList();
      expect(
        companyAFiles.where((file) => file.path.contains('auto_a_')).length,
        15,
      );
      expect(
        companyAFiles.where((file) => file.path.contains('manual_a_')).length,
        3,
      );
      expect(
        companyAFiles.any((file) => file.path.endsWith('unknown.zip')),
        isTrue,
      );
      expect(companyBFiles.length, 8);
    },
  );
}

Future<String> _zipWithManifest(
  Map<String, Object?> manifest, {
  Directory? directory,
  String fileName = 'backup.zip',
}) async {
  final dir =
      directory ??
      await Directory.systemTemp.createTemp('fullpos_backup_test_');
  final bytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
  final archive = Archive();
  for (final module in _requiredModuleNamesForTest) {
    final moduleBytes = utf8.encode('[]');
    archive.addFile(
      ArchiveFile('$module.json', moduleBytes.length, moduleBytes),
    );
  }
  archive.addFile(ArchiveFile('manifest.json', bytes.length, bytes));
  final zipBytes = ZipEncoder().encode(archive);
  final zipFile = File('${dir.path}/$fileName');
  await zipFile.writeAsBytes(zipBytes, flush: true);
  return zipFile.path;
}

Future<String> _canonicalZipForCompany(String companyId) async {
  final dir = await Directory.systemTemp.createTemp('fullpos_canonical_test_');
  final records = [
    {'id': 'product-a', 'companyId': companyId, 'nombre': 'Monitor'},
  ];
  final payload = utf8.encode(jsonEncode(records));
  final manifest = {
    'backupFormatVersion': CloudBackupService.backupFormatVersion,
    'backupId': '33333333-3333-4333-8333-333333333333',
    'product': 'DaleVentas POS / FullPOS Cloud',
    'environment': 'test',
    'createdAt': '2026-09-06T00:00:00.000Z',
    'appVersion': null,
    'backendVersion': 'test',
    'minimumCompatibleVersion': '1.0.5',
    'companyId': companyId,
    'companyNameSnapshot': 'FULLTECH, SRL',
    'backupType': 'MANUAL',
    'backupStatus': 'COMPLETE',
    'modules': ['products'],
    'recordCounts': {'products': records.length},
    'checksums': {'products': 'not-checked-client-side'},
  };
  final manifestBytes = utf8.encode(jsonEncode(manifest));
  final archive = Archive()
    ..addFile(ArchiveFile('data/products.json', payload.length, payload))
    ..addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));
  final zipBytes = ZipEncoder().encode(archive);
  final zipFile = File('${dir.path}/backup.dvbackup');
  await zipFile.writeAsBytes(zipBytes, flush: true);
  return zipFile.path;
}

Map<String, Object?> _manifestForCompany(
  String companyId, {
  String? backupId,
  String backupType = 'MANUAL',
  String status = 'COMPLETE',
  DateTime? createdAt,
  Map<String, Map<String, Object?>> moduleOverride = const {},
}) {
  final moduleStatus = {
    for (final module in _requiredModuleNamesForTest)
      module: {
        'status': 'COMPLETE',
        'records': 0,
        'file': '$module.json',
        'checksum': 'test-checksum',
        ...?moduleOverride[module],
      },
  };
  return {
    'backupFormatVersion': CloudBackupService.backupFormatVersion,
    'appVersion': CloudBackupService.appVersion,
    'backupId': backupId ?? '$companyId-backup',
    'backupType': backupType,
    'backupStatus': status,
    'sourceEnvironment': 'test',
    'companyId': companyId,
    'companyName': companyId == 'company-b' ? 'Empresa B' : 'Empresa A',
    'createdAt': (createdAt ?? DateTime(2026, 1, 1)).toIso8601String(),
    'modules': _requiredModuleNamesForTest,
    'moduleStatus': moduleStatus,
  };
}

const _requiredModuleNamesForTest = [
  'empresa',
  'impresora_local',
  'usuarios',
  'clientes',
  'productos',
  'ventas',
  'facturas_ventas',
  'creditos_ventas',
  'suplidores',
  'compras',
  'facturas_compras',
  'movimientos_caja',
  'nomina_empleados',
  'nomina_periodos',
  'nomina_configuracion',
  'depositos_contabilidad',
  'pagos_pendientes',
  'pagos_realizados',
];

class _TestAuthController extends AuthController {
  _TestAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'f6a41e76-67b8-485f-ab5f-4d29fba1c192',
        email: 'fulltech@example.test',
        nombreCompleto: 'FULLTECH User',
        telefono: '',
        role: 'ADMIN',
        companyId: '165e3fca-6225-479b-8805-d2205f10536c',
        companyName: 'FULLTECH, SRL',
        companySlug: 'fulltech-srl',
      ),
    );
  }
}

class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  _FakePrinterSettingsRepository() : super(companyId: 'company-test');

  @override
  Future<PrinterSettingsModel> getOrCreate() async {
    return const PrinterSettingsModel(
      id: 1,
      headerBusinessName: 'FULLTECH, SRL',
      headerRnc: 'TEST-RNC',
      footerMessage: 'FULLTECH footer',
    );
  }
}

class _FakeCompanySettingsRepository extends CompanySettingsRepository {
  _FakeCompanySettingsRepository()
    : super(Dio(), SyncQueueService(OfflineStore.instance));

  @override
  Future<CompanySettings> getSettingsRemoteAndCache() async {
    return CompanySettings.empty().copyWith(
      companyName: 'FULLTECH, SRL',
      rnc: 'TEST-RNC',
    );
  }
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
