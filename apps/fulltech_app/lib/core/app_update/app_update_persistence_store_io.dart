import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class UpdateStateFileStore {
  const UpdateStateFileStore();

  Future<Directory> _root() async {
    if (Platform.isWindows) {
      final localAppData = (Platform.environment['LOCALAPPDATA'] ?? '').trim();
      if (localAppData.isNotEmpty) {
        return Directory(p.join(localAppData, 'DaleVentas POS', 'updates'));
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
    if (await rootState.exists()) candidates.add(rootState);

    if (await root.exists()) {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (int.tryParse(name) == null) continue;
        final stateFile = File(p.join(entity.path, 'update_state.json'));
        if (await stateFile.exists()) candidates.add(stateFile);
      }
    }

    Map<String, dynamic>? latest;
    DateTime? latestUpdatedAt;
    for (final file in candidates) {
      final parsed = await _readOne(file);
      if (parsed == null) continue;
      final updatedAt = DateTime.tryParse(
        parsed['updatedAt']?.toString() ?? '',
      );
      if (latest == null ||
          updatedAt == null ||
          latestUpdatedAt == null ||
          updatedAt.isAfter(latestUpdatedAt)) {
        latest = parsed;
        latestUpdatedAt = updatedAt;
      }
    }
    return latest;
  }

  Future<Map<String, dynamic>?> _readOne(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  Future<void> writeJson(Map<String, dynamic> json) async {
    final file = await _stateFileForJson(json);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }
}
