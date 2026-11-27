import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/windows_product_paths.dart';
import 'app_update_models.dart';

class UpdateStateFileStore {
  const UpdateStateFileStore({Directory? rootDirectory})
    : _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;

  Future<Directory> _root() async {
    if (_rootDirectory != null) return _rootDirectory;
    if (Platform.isWindows) {
      final productUpdates = WindowsProductPaths.folder(
        WindowsProductFolder.updates,
      );
      if (productUpdates != null) {
        return productUpdates;
      }
      final localAppData = (Platform.environment['LOCALAPPDATA'] ?? '').trim();
      if (localAppData.isNotEmpty) {
        return Directory(
          p.join(localAppData, WindowsProductPaths.productName, 'updates'),
        );
      }
    }
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'updates'));
  }

  Future<File> _rootStateFile() async {
    final root = await _root();
    return File(p.join(root.path, 'update_state.json'));
  }

  Future<File> _stateFileForJson(Map<String, dynamic> json) async {
    final root = await _root();
    final targetBuild = json['targetBuild'];
    if (targetBuild is int && targetBuild > 0) {
      return File(
        p.join(root.path, targetBuild.toString(), 'update_state.json'),
      );
    }
    return _rootStateFile();
  }

  Future<String> get updateRootPath async => (await _root()).path;

  Future<Map<String, dynamic>?> readJson() async {
    final root = await _root();
    final candidates = <File>[];
    final rootState = await _rootStateFile();
    Future<void> addCandidates(File file) async {
      for (final path in [file.path, '${file.path}.tmp', '${file.path}.bak']) {
        final candidate = File(path);
        if (await candidate.exists()) candidates.add(candidate);
      }
    }

    await addCandidates(rootState);

    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (int.tryParse(name) == null) continue;
        final stateFile = File(p.join(entity.path, 'update_state.json'));
        await addCandidates(stateFile);
      }
    }

    Map<String, dynamic>? latest;
    DateTime? latestUpdatedAt;
    for (final file in candidates) {
      Map<String, dynamic>? parsed;
      try {
        parsed = await _readOne(file);
      } on Object {
        // A damaged/locked old build must not hide another valid candidate.
        continue;
      }
      if (parsed == null) continue;
      final updatedAt = DateTime.tryParse(
        parsed['updatedAt']?.toString() ?? '',
      );
      if (updatedAt == null) continue;
      if (latest == null ||
          latestUpdatedAt == null ||
          updatedAt.isAfter(latestUpdatedAt)) {
        latest = parsed;
        latestUpdatedAt = updatedAt;
      }
    }
    if (latest == null && candidates.isNotEmpty) {
      throw const FormatException('No readable update state');
    }
    return latest;
  }

  Future<Map<String, dynamic>?> _readOne(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic> &&
        AppUpdatePhase.values.any((phase) => phase.code == decoded['state']) &&
        DateTime.tryParse(decoded['createdAt']?.toString() ?? '') != null &&
        DateTime.tryParse(decoded['updatedAt']?.toString() ?? '') != null) {
      return decoded;
    }
    return null;
  }

  Future<void> writeJson(Map<String, dynamic> json) async {
    final file = await _stateFileForJson(json);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    final backup = File('${file.path}.bak');
    if (await file.exists()) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    }
    await temp.rename(file.path);
  }
}
