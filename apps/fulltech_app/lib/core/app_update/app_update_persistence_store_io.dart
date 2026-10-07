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

  Future<File> _stateFile() async {
    final root = await _root();
    return File(p.join(root.path, 'update_state.json'));
  }

  Future<String> get updateRootPath async => (await _root()).path;

  Future<Map<String, dynamic>?> readJson() async {
    final file = await _stateFile();
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return null;
  }

  Future<void> writeJson(Map<String, dynamic> json) async {
    final file = await _stateFile();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }
}
