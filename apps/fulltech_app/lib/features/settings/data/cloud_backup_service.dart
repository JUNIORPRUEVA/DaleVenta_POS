import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/storage/windows_product_paths.dart';
import 'printer_settings_repository.dart';

final cloudBackupServiceProvider = Provider<CloudBackupService>((ref) {
  return CloudBackupService(ref, ref.watch(dioProvider));
});

enum CloudBackupStatus { complete, partial, failed }

enum CloudBackupType { manual, automatic, preRestoreSafety }

enum CloudBackupValidationStatus { valid, validWithWarnings, invalid }

enum CloudBackupFormat { canonical, legacy, invalid }

class CloudBackupModuleResult {
  const CloudBackupModuleResult({
    required this.name,
    required this.status,
    required this.records,
    this.file,
    this.checksum,
    this.error,
  });

  final String name;
  final CloudBackupStatus status;
  final int records;
  final String? file;
  final String? checksum;
  final String? error;

  Map<String, Object?> toMap() => {
    'status': _statusName(status),
    'records': records,
    if (file != null) 'file': file,
    if (checksum != null) 'checksum': checksum,
    if (error != null) 'error': error,
  };
}

class CloudBackupResult {
  const CloudBackupResult({
    required this.backupId,
    required this.folderPath,
    required this.zipPath,
    required this.modules,
    required this.failedModules,
    required this.moduleStatus,
    required this.status,
    required this.type,
    required this.createdAt,
  });

  final String backupId;
  final String folderPath;
  final String zipPath;
  final List<String> modules;
  final Map<String, String> failedModules;
  final Map<String, CloudBackupModuleResult> moduleStatus;
  final CloudBackupStatus status;
  final CloudBackupType type;
  final DateTime createdAt;

  bool get hasFailures => status != CloudBackupStatus.complete;
}

class CloudBackupInspection {
  const CloudBackupInspection({
    required this.path,
    required this.modules,
    required this.createdAt,
    required this.validationStatus,
    required this.backupStatus,
    required this.backupFormatVersion,
    required this.backupId,
    required this.backupType,
    required this.fileSize,
    required this.warnings,
    this.format = CloudBackupFormat.legacy,
    this.isCanonical = false,
    this.companyId,
    this.companyName,
  });

  final String path;
  final List<String> modules;
  final DateTime? createdAt;
  final CloudBackupValidationStatus validationStatus;
  final CloudBackupStatus? backupStatus;
  final int? backupFormatVersion;
  final String? backupId;
  final CloudBackupType? backupType;
  final int fileSize;
  final List<String> warnings;
  final CloudBackupFormat format;
  final bool isCanonical;
  final String? companyId;
  final String? companyName;

  bool get canRestoreByDefault =>
      isCanonical &&
      validationStatus == CloudBackupValidationStatus.valid &&
      backupStatus == CloudBackupStatus.complete;
}

class CloudBackupServerPreview {
  const CloudBackupServerPreview({
    required this.status,
    required this.format,
    required this.errors,
    required this.warnings,
    this.backupId,
    this.companyId,
    this.companyName,
    this.createdAt,
    this.backupType,
    this.modules = const [],
    this.recordCounts = const {},
    this.formatVersion,
  });

  final CloudBackupValidationStatus status;
  final CloudBackupFormat format;
  final List<String> errors;
  final List<String> warnings;
  final String? backupId;
  final String? companyId;
  final String? companyName;
  final DateTime? createdAt;
  final CloudBackupType? backupType;
  final List<String> modules;
  final Map<String, int> recordCounts;
  final int? formatVersion;

  bool get canRestore => status != CloudBackupValidationStatus.invalid;

  factory CloudBackupServerPreview.fromMap(Map<String, dynamic> map) {
    final manifest = map['manifest'] is Map
        ? Map<String, dynamic>.from(map['manifest'] as Map)
        : null;
    return CloudBackupServerPreview(
      status: _validationStatusFromName(map['status']),
      format: _formatFromName(map['format']),
      errors: _stringList(map['errors']),
      warnings: _stringList(map['warnings']),
      backupId: manifest?['backupId']?.toString(),
      companyId: manifest?['companyId']?.toString(),
      companyName: manifest?['companyNameSnapshot']?.toString(),
      createdAt: manifest?['createdAt'] is String
          ? DateTime.tryParse(manifest!['createdAt'] as String)
          : null,
      backupType: _typeFromName(manifest?['backupType']),
      modules: _stringList(manifest?['modules']),
      recordCounts: _intMap(manifest?['recordCounts']),
      formatVersion: _readInt(manifest?['formatVersion']),
    );
  }
}

class CloudBackupServerMetadata {
  const CloudBackupServerMetadata({
    required this.backupId,
    required this.companyId,
    required this.status,
    required this.type,
    required this.size,
    required this.createdAt,
    this.companyName,
    this.checksum,
  });

  final String backupId;
  final String companyId;
  final CloudBackupStatus status;
  final CloudBackupType? type;
  final int size;
  final DateTime? createdAt;
  final String? companyName;
  final String? checksum;

  factory CloudBackupServerMetadata.fromMap(Map<String, dynamic> map) {
    return CloudBackupServerMetadata(
      backupId: (map['backupId'] ?? '').toString(),
      companyId: (map['companyId'] ?? '').toString(),
      status: _statusFromName(map['status']) ?? CloudBackupStatus.failed,
      type: _typeFromName(map['type']),
      size: _readInt(map['size']) ?? 0,
      createdAt: map['createdAt'] is String
          ? DateTime.tryParse(map['createdAt'] as String)
          : null,
      companyName: map['companyNameSnapshot']?.toString(),
      checksum: map['checksum']?.toString(),
    );
  }
}

class CloudBackupRestoreResult {
  const CloudBackupRestoreResult({
    required this.ok,
    required this.backupId,
    required this.companyId,
    this.preRestoreBackupId,
  });

  final bool ok;
  final String backupId;
  final String companyId;
  final String? preRestoreBackupId;

  factory CloudBackupRestoreResult.fromMap(Map<String, dynamic> map) {
    return CloudBackupRestoreResult(
      ok: map['ok'] == true,
      backupId: (map['backupId'] ?? '').toString(),
      companyId: (map['companyId'] ?? '').toString(),
      preRestoreBackupId: map['preRestoreBackupId']?.toString(),
    );
  }
}

class CloudBackupService {
  CloudBackupService(this._ref, this._dio, {Directory? backupRootOverride})
    : _backupRootOverride = backupRootOverride;

  final Ref _ref;
  final Dio _dio;
  final Directory? _backupRootOverride;

  static const backupFormatVersion = 2;
  static const appVersion = '1.0.5+122';
  static const automaticBackupInterval = Duration(days: 2);
  static const maxAutomaticBackupsPerCompany = 15;
  static const _timeout = Duration(seconds: 25);
  static const _lastBackupAtKey = 'fullpos_cloud_last_backup_at';
  static const _lastBackupZipKey = 'fullpos_cloud_last_backup_zip';

  Future<CloudBackupResult?> createAutomaticBackupIfDue({
    Duration interval = automaticBackupInterval,
  }) async {
    if (kIsWeb) return null;
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return null;
    }
    if (!_ref.read(authStateProvider).isAuthenticated) return null;
    final prefs = await SharedPreferences.getInstance();
    final companyId = _activeCompanyId();
    if (companyId.isEmpty) return null;
    final lastRaw = prefs.getString(_lastBackupAtKeyForCompany(companyId));
    final last = lastRaw == null ? null : DateTime.tryParse(lastRaw);
    if (last != null && DateTime.now().difference(last) < interval) {
      final zipPath = prefs.getString(_lastBackupZipKeyForCompany(companyId));
      if (zipPath != null && await File(zipPath).exists()) return null;
    }
    return createCloudBackup(type: CloudBackupType.automatic);
  }

  Future<String?> lastBackupZipPath() async {
    if (kIsWeb) return null;
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(
      _lastBackupZipKeyForCompany(_activeCompanyId()),
    );
    if (path == null || path.trim().isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  Future<CloudBackupInspection> inspectBackupZip(String zipPath) async {
    return inspectBackupZipForCompany(
      zipPath,
      expectedCompanyId: _activeCompanyId(),
    );
  }

  static Future<CloudBackupInspection> inspectBackupZipForCompany(
    String zipPath, {
    String? expectedCompanyId,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Backup local no disponible en la version web.');
    }
    final file = File(zipPath);
    if (!await file.exists()) {
      throw const FormatException('El archivo seleccionado no existe.');
    }
    final fileSize = await file.length();
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    ArchiveFile? manifest;
    for (final entry in archive.files) {
      final normalizedName = entry.name.replaceAll('\\', '/');
      if (normalizedName.endsWith('/manifest.json') ||
          normalizedName == 'manifest.json') {
        manifest = entry;
        break;
      }
    }
    if (manifest == null) {
      throw const FormatException('El backup no contiene manifiesto.');
    }
    final data =
        jsonDecode(utf8.decode(manifest.content)) as Map<String, dynamic>;
    if ((data['product'] ?? '').toString() ==
        'DaleVentas POS / FullPOS Cloud') {
      return _inspectCanonicalArchive(
        data,
        archive,
        zipPath: zipPath,
        fileSize: fileSize,
        expectedCompanyId: expectedCompanyId,
      );
    }
    final version = _readInt(data['backupFormatVersion']);
    if (version != backupFormatVersion) {
      throw const FormatException('Version de backup no soportada.');
    }
    final backupId = (data['backupId'] ?? '').toString().trim();
    if (backupId.isEmpty) {
      throw const FormatException('El backup no contiene backupId.');
    }
    final modulesRaw = data['modules'];
    final modules = modulesRaw is List
        ? modulesRaw.map((item) => '$item').toList()
        : <String>[];
    final moduleStatusRaw = data['moduleStatus'];
    if (moduleStatusRaw is! Map) {
      throw const FormatException('El backup no contiene estado de modulos.');
    }
    final backupStatus = _statusFromName(data['backupStatus']);
    if (backupStatus == null) {
      throw const FormatException('Estado de backup invalido.');
    }
    final backupType = _typeFromName(data['backupType']);
    if (backupType == null) {
      throw const FormatException('Tipo de backup invalido.');
    }
    final createdAtRaw = data['createdAt'];
    final manifestCompanyId = (data['companyId'] ?? '').toString().trim();
    if (manifestCompanyId.isEmpty) {
      throw const FormatException('El backup no identifica la empresa.');
    }
    final activeCompanyId = expectedCompanyId?.trim() ?? '';
    if (manifestCompanyId.isNotEmpty &&
        activeCompanyId.isNotEmpty &&
        manifestCompanyId != activeCompanyId) {
      throw const FormatException(
        'Este backup pertenece a otra empresa y no puede restaurarse aquí.',
      );
    }
    final warnings = <String>[];
    for (final module in _requiredModuleNames) {
      if (!modules.contains(module)) {
        throw FormatException(
          'El backup no contiene el modulo requerido $module.',
        );
      }
      final status = moduleStatusRaw[module];
      if (status is! Map) {
        throw FormatException('El backup no contiene estado para $module.');
      }
      final statusName = (status['status'] ?? '').toString();
      if (_statusFromName(statusName) == null) {
        throw FormatException('Estado invalido para $module.');
      }
      final fileName = (status['file'] ?? '').toString().trim();
      if (fileName.isNotEmpty &&
          !archive.files.any((entry) {
            final normalizedName = entry.name.replaceAll('\\', '/');
            return normalizedName == fileName ||
                normalizedName.endsWith('/$fileName');
          })) {
        throw FormatException('Archivo faltante para $module.');
      }
      if (statusName != _statusName(CloudBackupStatus.complete)) {
        warnings.add('$module: $statusName');
      }
    }
    return CloudBackupInspection(
      path: zipPath,
      modules: modules,
      createdAt: createdAtRaw is String
          ? DateTime.tryParse(createdAtRaw)
          : null,
      validationStatus: warnings.isEmpty
          ? CloudBackupValidationStatus.valid
          : CloudBackupValidationStatus.validWithWarnings,
      backupStatus: backupStatus,
      backupFormatVersion: version,
      backupId: backupId,
      backupType: backupType,
      fileSize: fileSize,
      warnings: warnings,
      format: CloudBackupFormat.legacy,
      isCanonical: false,
      companyId: manifestCompanyId.isEmpty ? null : manifestCompanyId,
      companyName: (data['companyName'] ?? '').toString().trim().isEmpty
          ? null
          : (data['companyName'] ?? '').toString().trim(),
    );
  }

  Future<CloudBackupResult> createCloudBackup({
    CloudBackupType type = CloudBackupType.manual,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Backup local no disponible en la version web.');
    }
    final now = DateTime.now();
    final stamp = _stamp(now);
    final companyId = _activeCompanyId();
    if (companyId.isEmpty) {
      throw StateError('No se puede crear backup sin empresa activa.');
    }
    final companyName = _activeCompanyName();
    final backupId = '${_safePathSegment(companyId)}_$stamp';
    final root = await _backupRoot(companyId: companyId);
    final safeCompany = _safePathSegment(
      companyId.isEmpty ? 'unknown_company' : companyId,
    );
    final folder = Directory(
      p.join(root.path, 'cloud_backup_${safeCompany}_$stamp'),
    );
    await folder.create(recursive: true);

    final modules = <String>[];
    final failures = <String, String>{};
    final moduleStatus = <String, CloudBackupModuleResult>{};

    Future<CloudBackupModuleResult> writeJson(String name, Object? data) async {
      final file = File(p.join(folder.path, '$name.json'));
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(data), encoding: utf8);
      final checksum = await _sha256File(file);
      final result = CloudBackupModuleResult(
        name: name,
        status: CloudBackupStatus.complete,
        records: _recordCount(data),
        file: '$name.json',
        checksum: checksum,
      );
      moduleStatus[name] = result;
      modules.add(name);
      return result;
    }

    Future<void> captureRemote(String name, String path) async {
      try {
        final data = await _captureModuleData(path);
        await writeJson(name, data);
      } catch (error) {
        final friendly = _friendlyError(error);
        failures[name] = friendly;
        moduleStatus[name] = CloudBackupModuleResult(
          name: name,
          status: CloudBackupStatus.failed,
          records: 0,
          error: friendly,
        );
      }
    }

    try {
      final settings = await _ref
          .read(companySettingsRepositoryProvider)
          .getSettingsRemoteAndCache();
      await writeJson('empresa', settings.toMap());
    } catch (error) {
      final friendly = _friendlyError(error);
      failures['empresa'] = friendly;
      moduleStatus['empresa'] = CloudBackupModuleResult(
        name: 'empresa',
        status: CloudBackupStatus.failed,
        records: 0,
        error: friendly,
      );
    }

    try {
      final printer = await _ref
          .read(printerSettingsRepositoryProvider)
          .getOrCreate();
      await writeJson('impresora_local', printer.toMap());
    } catch (error) {
      final friendly = _friendlyError(error);
      failures['impresora_local'] = friendly;
      moduleStatus['impresora_local'] = CloudBackupModuleResult(
        name: 'impresora_local',
        status: CloudBackupStatus.failed,
        records: 0,
        error: friendly,
      );
    }

    for (final entry in _remoteModules.entries) {
      await captureRemote(entry.key, entry.value);
    }

    final status = failures.isEmpty
        ? CloudBackupStatus.complete
        : modules.isEmpty
        ? CloudBackupStatus.failed
        : CloudBackupStatus.partial;
    final manifest = {
      'app': 'FullPOS Cloud',
      'backupFormatVersion': backupFormatVersion,
      'appVersion': appVersion,
      'kind': 'cloud-local-backup',
      'backupId': backupId,
      'backupType': _typeName(type),
      'sourceEnvironment': 'daleventas-pos-windows',
      'companyId': companyId,
      'companyName': companyName,
      'companySlug': _activeCompanySlug(),
      'createdAt': now.toIso8601String(),
      'folderPath': folder.path,
      'modules': modules,
      'moduleStatus': moduleStatus.map(
        (key, value) => MapEntry(key, value.toMap()),
      ),
      'failedModules': failures,
      'backupStatus': _statusName(status),
      'recordCounts': moduleStatus.map(
        (key, value) => MapEntry(key, value.records),
      ),
      'checksums': moduleStatus.map(
        (key, value) => MapEntry(key, value.checksum),
      ),
      'restoreNote':
          'Este respaldo contiene JSON por modulo. La restauracion cloud requiere un flujo transaccional servidor-side antes de habilitarse.',
    };
    await writeJson('manifest', manifest);

    final zipPath = await _availableZipPath(
      root.path,
      'cloud_backup_${safeCompany}_$stamp.zip',
    );
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(folder);
    encoder.close();
    await _verifyCreatedZip(zipPath);
    await inspectBackupZipForCompany(zipPath, expectedCompanyId: companyId);
    if (status == CloudBackupStatus.complete) {
      await folder.delete(recursive: true);
    }

    final result = CloudBackupResult(
      backupId: backupId,
      folderPath: folder.path,
      zipPath: zipPath,
      modules: modules,
      failedModules: failures,
      moduleStatus: moduleStatus,
      status: status,
      type: type,
      createdAt: now,
    );
    await _rememberBackup(result);
    if (type == CloudBackupType.automatic &&
        status == CloudBackupStatus.complete) {
      await cleanupAutomaticBackups(companyId: companyId);
    }
    return result;
  }

  Future<int> cleanupAutomaticBackups({String? companyId}) async {
    if (kIsWeb) return 0;
    final activeCompanyId = (companyId ?? _activeCompanyId()).trim();
    if (activeCompanyId.isEmpty) return 0;
    final root = await _backupRoot(companyId: activeCompanyId);
    if (!await root.exists()) return 0;
    final backups = <CloudBackupInspection>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.zip') {
        continue;
      }
      try {
        final inspection = await inspectBackupZipForCompany(
          entity.path,
          expectedCompanyId: activeCompanyId,
        );
        if (inspection.backupType == CloudBackupType.automatic &&
            inspection.backupStatus == CloudBackupStatus.complete &&
            inspection.companyId == activeCompanyId) {
          backups.add(inspection);
        }
      } catch (_) {
        // Unknown or malformed files are never retention-deleted.
      }
    }
    backups.sort((a, b) {
      final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    var deleted = 0;
    for (final backup in backups.skip(maxAutomaticBackupsPerCompany)) {
      await File(backup.path).delete();
      deleted += 1;
    }
    return deleted;
  }

  Future<void> assertBackupRestorable(String zipPath) async {
    final inspection = await inspectBackupZip(zipPath);
    if (inspection.backupStatus != CloudBackupStatus.complete) {
      throw StateError('Los backups parciales no se restauran por defecto.');
    }
    if (!inspection.isCanonical) {
      throw UnsupportedError('Solo backups canonicos .dvbackup se restauran.');
    }
  }

  Future<CloudBackupServerPreview> validateCanonicalUpload({
    String? path,
    Uint8List? bytes,
    String? fileName,
  }) async {
    final payload = await _backupUploadPayload(
      path: path,
      bytes: bytes,
      fileName: fileName,
    );
    final response = await _dio.post(
      ApiRoutes.backupsValidateUpload,
      data: payload.formData,
      options: Options(extra: const {'skipLoader': true}),
    );
    return CloudBackupServerPreview.fromMap(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<CloudBackupServerMetadata> importCanonicalUpload({
    String? path,
    Uint8List? bytes,
    String? fileName,
  }) async {
    final payload = await _backupUploadPayload(
      path: path,
      bytes: bytes,
      fileName: fileName,
    );
    final response = await _dio.post(
      ApiRoutes.backupsImport,
      data: payload.formData,
      options: Options(extra: const {'skipLoader': true}),
    );
    return CloudBackupServerMetadata.fromMap(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<CloudBackupRestoreResult> restoreCanonicalBackup(
    String backupId,
  ) async {
    final response = await _dio.post(
      ApiRoutes.backupRestore(backupId),
      options: Options(extra: const {'skipLoader': true}),
    );
    return CloudBackupRestoreResult.fromMap(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<void> _rememberBackup(CloudBackupResult result) async {
    final prefs = await SharedPreferences.getInstance();
    final companyId = _activeCompanyId();
    await prefs.setString(
      _lastBackupAtKeyForCompany(companyId),
      result.createdAt.toIso8601String(),
    );
    await prefs.setString(
      _lastBackupZipKeyForCompany(companyId),
      result.zipPath,
    );
  }

  Future<Directory> _backupRoot({required String companyId}) async {
    final safeCompany = _safePathSegment(
      companyId.trim().isEmpty ? 'unknown_company' : companyId,
    );
    final overrideRoot = _backupRootOverride;
    if (overrideRoot != null) {
      final dir = Directory(p.join(overrideRoot.path, safeCompany));
      await dir.create(recursive: true);
      return dir;
    }
    final windowsBackups = WindowsProductPaths.folder(
      WindowsProductFolder.backups,
    );
    final dir = windowsBackups == null
        ? Directory(
            p.join(
              (await getApplicationDocumentsDirectory()).path,
              'FullPOS Cloud',
              'backups',
              safeCompany,
            ),
          )
        : Directory(p.join(windowsBackups.path, safeCompany));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _availableZipPath(String directory, String fileName) async {
    var candidate = p.join(directory, fileName);
    var suffix = 1;
    while (await File(candidate).exists()) {
      final extension = p.extension(fileName);
      final baseName = p.basenameWithoutExtension(fileName);
      candidate = p.join(directory, '${baseName}_$suffix$extension');
      suffix += 1;
    }
    return candidate;
  }

  Future<_BackupUploadPayload> _backupUploadPayload({
    String? path,
    Uint8List? bytes,
    String? fileName,
  }) async {
    final effectiveFileName = (fileName?.trim().isNotEmpty == true)
        ? fileName!.trim()
        : path == null
        ? 'backup.dvbackup'
        : p.basename(path);
    final data = bytes ?? await File(path!).readAsBytes();
    if (data.isEmpty) {
      throw const FormatException('El archivo de backup esta vacio.');
    }
    return _BackupUploadPayload(
      formData: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          data,
          filename: effectiveFileName,
          contentType: MediaType('application', 'vnd.daleventas.backup+zip'),
        ),
      }),
    );
  }

  Future<Object?> _captureModuleData(String path) async {
    final response = await _dio
        .get(path, options: Options(extra: const {'skipLoader': true}))
        .timeout(_timeout);
    return response.data;
  }

  Future<void> _verifyCreatedZip(String zipPath) async {
    final file = File(zipPath);
    if (!await file.exists()) {
      throw const FileSystemException('No se creo el archivo de backup.');
    }
    final size = await file.length();
    if (size <= 22) {
      throw const FileSystemException('El archivo de backup quedo vacio.');
    }
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    if (archive.files.isEmpty) {
      throw const FormatException('El backup no contiene archivos.');
    }
  }

  Future<String> _sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  int _recordCount(Object? data) {
    if (data is List) return data.length;
    if (data is Map) {
      final items = data['items'];
      if (items is List) return items.length;
      final dataList = data['data'];
      if (dataList is List) return dataList.length;
      final total = data['total'];
      if (total is int) return total;
    }
    return data == null ? 0 : 1;
  }

  String _stamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  String _friendlyError(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      final message = error.response?.data;
      if (code != null) return 'HTTP $code: $message';
      return error.message ?? error.type.name;
    }
    return error.toString();
  }

  String _activeCompanyId() =>
      _ref.read(authStateProvider).user?.companyId?.trim() ?? '';

  String _activeCompanyName() =>
      _ref.read(authStateProvider).user?.companyName?.trim() ?? '';

  String _activeCompanySlug() =>
      _ref.read(authStateProvider).user?.companySlug?.trim() ?? '';

  String _lastBackupAtKeyForCompany(String companyId) {
    return '$_lastBackupAtKey:${_safePathSegment(companyId.isEmpty ? 'unknown_company' : companyId)}';
  }

  String _lastBackupZipKeyForCompany(String companyId) {
    return '$_lastBackupZipKey:${_safePathSegment(companyId.isEmpty ? 'unknown_company' : companyId)}';
  }

  String _safePathSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'unknown';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}

class _BackupUploadPayload {
  const _BackupUploadPayload({required this.formData});

  final FormData formData;
}

CloudBackupInspection _inspectCanonicalArchive(
  Map<String, dynamic> data,
  Archive archive, {
  required String zipPath,
  required int fileSize,
  String? expectedCompanyId,
}) {
  final version = _readInt(data['backupFormatVersion']);
  if (version != CloudBackupService.backupFormatVersion) {
    throw const FormatException('Version de backup no soportada.');
  }
  final backupId = (data['backupId'] ?? '').toString().trim();
  if (backupId.isEmpty) {
    throw const FormatException('El backup no contiene backupId.');
  }
  final manifestCompanyId = (data['companyId'] ?? '').toString().trim();
  if (manifestCompanyId.isEmpty) {
    throw const FormatException('El backup no identifica la empresa.');
  }
  final activeCompanyId = expectedCompanyId?.trim() ?? '';
  if (activeCompanyId.isNotEmpty && manifestCompanyId != activeCompanyId) {
    throw const FormatException(
      'Este backup pertenece a otra empresa y no puede restaurarse aquí.',
    );
  }
  final backupStatus = _statusFromName(data['backupStatus']);
  if (backupStatus == null) {
    throw const FormatException('Estado de backup invalido.');
  }
  final backupType = _typeFromName(data['backupType']);
  if (backupType == null) {
    throw const FormatException('Tipo de backup invalido.');
  }
  final modules = _stringList(data['modules']);
  if (modules.isEmpty) {
    throw const FormatException('El backup no contiene modulos.');
  }
  final names = archive.files
      .map((entry) => entry.name.replaceAll('\\', '/'))
      .toSet();
  final warnings = <String>[];
  for (final module in modules) {
    if (!names.contains('data/$module.json')) {
      throw FormatException('Archivo faltante para $module.');
    }
  }
  if (backupStatus != CloudBackupStatus.complete) {
    warnings.add('backupStatus: ${_statusName(backupStatus)}');
  }
  return CloudBackupInspection(
    path: zipPath,
    modules: modules,
    createdAt: data['createdAt'] is String
        ? DateTime.tryParse(data['createdAt'] as String)
        : null,
    validationStatus: warnings.isEmpty
        ? CloudBackupValidationStatus.valid
        : CloudBackupValidationStatus.validWithWarnings,
    backupStatus: backupStatus,
    backupFormatVersion: version,
    backupId: backupId,
    backupType: backupType,
    fileSize: fileSize,
    warnings: warnings,
    format: CloudBackupFormat.canonical,
    isCanonical: true,
    companyId: manifestCompanyId,
    companyName: (data['companyNameSnapshot'] ?? '').toString().trim().isEmpty
        ? null
        : (data['companyNameSnapshot'] ?? '').toString().trim(),
  );
}

String _statusName(CloudBackupStatus status) {
  return switch (status) {
    CloudBackupStatus.complete => 'COMPLETE',
    CloudBackupStatus.partial => 'PARTIAL',
    CloudBackupStatus.failed => 'FAILED',
  };
}

CloudBackupStatus? _statusFromName(Object? value) {
  return switch ('$value'.trim().toUpperCase()) {
    'COMPLETE' => CloudBackupStatus.complete,
    'PARTIAL' => CloudBackupStatus.partial,
    'FAILED' => CloudBackupStatus.failed,
    _ => null,
  };
}

CloudBackupValidationStatus _validationStatusFromName(Object? value) {
  return switch ('$value'.trim().toUpperCase()) {
    'VALID' => CloudBackupValidationStatus.valid,
    'VALID_WITH_WARNINGS' => CloudBackupValidationStatus.validWithWarnings,
    _ => CloudBackupValidationStatus.invalid,
  };
}

CloudBackupFormat _formatFromName(Object? value) {
  return switch ('$value'.trim().toUpperCase()) {
    'CANONICAL' => CloudBackupFormat.canonical,
    'LEGACY' => CloudBackupFormat.legacy,
    _ => CloudBackupFormat.invalid,
  };
}

String _typeName(CloudBackupType type) {
  return switch (type) {
    CloudBackupType.manual => 'MANUAL',
    CloudBackupType.automatic => 'AUTOMATIC',
    CloudBackupType.preRestoreSafety => 'PRE_RESTORE_SAFETY',
  };
}

CloudBackupType? _typeFromName(Object? value) {
  return switch ('$value'.trim().toUpperCase()) {
    'MANUAL' => CloudBackupType.manual,
    'AUTOMATIC' => CloudBackupType.automatic,
    'PRE_RESTORE_SAFETY' => CloudBackupType.preRestoreSafety,
    _ => null,
  };
}

int? _readInt(Object? value) {
  if (value is int) return value;
  return int.tryParse('$value');
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => '$item').toList(growable: false);
}

Map<String, int> _intMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, item) => MapEntry('$key', _readInt(item) ?? 0));
}

const Set<String> _requiredModuleNames = {
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
};

const Map<String, String> _remoteModules = {
  'usuarios': ApiRoutes.users,
  'clientes': ApiRoutes.clients,
  'productos': ApiRoutes.products,
  'ventas': ApiRoutes.sales,
  'facturas_ventas': ApiRoutes.salesInvoices,
  'creditos_ventas': ApiRoutes.salesCredits,
  'suplidores': ApiRoutes.purchaseSuppliers,
  'compras': ApiRoutes.purchaseOrders,
  'facturas_compras': ApiRoutes.purchaseInvoices,
  'movimientos_caja': ApiRoutes.cashMovementsHistory,
  'nomina_empleados': ApiRoutes.payrollEmployees,
  'nomina_periodos': ApiRoutes.payrollPeriods,
  'nomina_configuracion': ApiRoutes.payrollConfig,
  'depositos_contabilidad': ApiRoutes.contabilidadDepositOrders,
  'pagos_pendientes': ApiRoutes.contabilidadPayableServices,
  'pagos_realizados': ApiRoutes.contabilidadPayablePayments,
};
