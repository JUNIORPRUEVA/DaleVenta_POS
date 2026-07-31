import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/company/company_settings_repository.dart';
import 'printer_settings_repository.dart';

final cloudBackupServiceProvider = Provider<CloudBackupService>((ref) {
  return CloudBackupService(ref, ref.watch(dioProvider));
});

class CloudBackupResult {
  const CloudBackupResult({
    required this.folderPath,
    required this.zipPath,
    required this.modules,
    required this.failedModules,
    required this.createdAt,
  });

  final String folderPath;
  final String zipPath;
  final List<String> modules;
  final Map<String, String> failedModules;
  final DateTime createdAt;

  bool get hasFailures => failedModules.isNotEmpty;
}

class CloudBackupService {
  CloudBackupService(this._ref, this._dio);

  final Ref _ref;
  final Dio _dio;

  static const _timeout = Duration(seconds: 25);

  Future<CloudBackupResult> createCloudBackup() async {
    final now = DateTime.now();
    final stamp = _stamp(now);
    final root = await _backupRoot();
    final folder = Directory(p.join(root.path, 'cloud_backup_$stamp'));
    await folder.create(recursive: true);

    final modules = <String>[];
    final failures = <String, String>{};

    Future<void> writeJson(String name, Object? data) async {
      final file = File(p.join(folder.path, '$name.json'));
      const encoder = JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(data), encoding: utf8);
    }

    Future<void> captureRemote(String name, String path) async {
      try {
        final response = await _dio
            .get(
              path,
              queryParameters: const {'page': 1, 'limit': 5000},
              options: Options(extra: const {'skipLoader': true}),
            )
            .timeout(_timeout);
        await writeJson(name, response.data);
        modules.add(name);
      } catch (error) {
        failures[name] = _friendlyError(error);
      }
    }

    try {
      final settings = await _ref
          .read(companySettingsRepositoryProvider)
          .getSettingsRemoteAndCache();
      await writeJson('empresa', settings.toMap());
      modules.add('empresa');
    } catch (error) {
      failures['empresa'] = _friendlyError(error);
    }

    try {
      final printer = await _ref
          .read(printerSettingsRepositoryProvider)
          .getOrCreate();
      await writeJson('impresora_local', printer.toMap());
      modules.add('impresora_local');
    } catch (error) {
      failures['impresora_local'] = _friendlyError(error);
    }

    for (final entry in _remoteModules.entries) {
      await captureRemote(entry.key, entry.value);
    }

    final manifest = {
      'app': 'FullPOS Cloud',
      'kind': 'cloud-local-backup',
      'createdAt': now.toIso8601String(),
      'folderPath': folder.path,
      'modules': modules,
      'failedModules': failures,
      'restoreNote':
          'Este respaldo contiene JSON por modulo para restauracion asistida o reimportacion futura a la nube.',
    };
    await writeJson('manifest', manifest);

    final zipPath = p.join(root.path, 'cloud_backup_$stamp.zip');
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    encoder.addDirectory(folder);
    encoder.close();

    return CloudBackupResult(
      folderPath: folder.path,
      zipPath: zipPath,
      modules: modules,
      failedModules: failures,
      createdAt: now,
    );
  }

  Future<Directory> _backupRoot() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'FullPOS Cloud', 'backups'));
    await dir.create(recursive: true);
    return dir;
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
}

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
