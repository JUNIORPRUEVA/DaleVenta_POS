import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

Future<void> main(List<String> args) async {
  final baseUrl =
      _readEnvFromDotEnv('.env', 'API_BASE_URL') ??
      _readEnvFromDotEnv('apps/fulltech_app/.env', 'API_BASE_URL') ??
      Platform.environment['API_BASE_URL'];
  if (baseUrl == null || baseUrl.trim().isEmpty) {
    stderr.writeln(
      'Missing API_BASE_URL in apps/fulltech_app/.env or env var.',
    );
    exitCode = 2;
    return;
  }

  final identifier =
      Platform.environment['ADMIN_EMAIL'] ??
      _readEnvFromDotEnv('../api/.env', 'ADMIN_EMAIL') ??
      _readEnvFromDotEnv('apps/api/.env', 'ADMIN_EMAIL') ??
      'admin@fulltech.local';
  final password =
      Platform.environment['ADMIN_PASSWORD'] ??
      _readEnvFromDotEnv('../api/.env', 'ADMIN_PASSWORD') ??
      _readEnvFromDotEnv('apps/api/.env', 'ADMIN_PASSWORD');

  if (password == null || password.isEmpty) {
    stderr.writeln('Missing ADMIN_PASSWORD (set env var or apps/api/.env).');
    exitCode = 2;
    return;
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl.trim().replaceAll(RegExp(r'/$'), ''),
      headers: const {'Accept': 'application/json'},
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );

  final token = await _login(dio, identifier: identifier, password: password);
  stdout.writeln('Logged in as: $identifier');

  Future<void> fetch({required String label, required Options options}) async {
    stdout.writeln('\n=== $label ===');
    final res = await dio.get<dynamic>(
      '/company-manual',
      queryParameters: {'includeHidden': 'true'},
      options: options.copyWith(
        headers: {...?options.headers, 'Authorization': 'Bearer $token'},
      ),
    );

    stdout.writeln('Status: ${res.statusCode}');
    stdout.writeln('Content-Type: ${res.headers.value('content-type')}');
    stdout.writeln(
      'Content-Encoding: ${res.headers.value('content-encoding')}',
    );
    stdout.writeln('Content-Length: ${res.headers.value('content-length')}');
    stdout.writeln('DataType: ${res.data.runtimeType}');

    final data = res.data;
    Uint8List? bytes;
    String? text;

    if (data is Uint8List) bytes = data;
    if (data is List<int>) bytes = Uint8List.fromList(data);
    if (data is ByteBuffer) bytes = data.asUint8List();
    if (data is String) text = data;

    if (bytes != null) {
      stdout.writeln('BytesLen: ${bytes.length}');
      final take = bytes.length > 32 ? bytes.sublist(0, 32) : bytes;
      final hex = take
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      stdout.writeln('FirstBytes(hex): $hex');

      final preview = utf8.decode(
        bytes.length > 200 ? bytes.sublist(0, 200) : bytes,
        allowMalformed: true,
      );
      stdout.writeln(
        'Preview(utf8, malformed ok): ${preview.replaceAll(RegExp(r"\s+"), " ")}',
      );

      try {
        final decoded = jsonDecode(utf8.decode(bytes));
        stdout.writeln('jsonDecode OK: ${decoded.runtimeType}');
        if (decoded is Map && decoded['items'] is List) {
          stdout.writeln('items: ${(decoded['items'] as List).length}');
        }
      } catch (e) {
        stdout.writeln('jsonDecode FAILED: $e');
      }
    }

    if (text != null) {
      stdout.writeln('TextLen: ${text.length}');
      stdout.writeln(
        'TextPreview: ${text.substring(0, text.length > 200 ? 200 : text.length).replaceAll(RegExp(r"\s+"), " ")}',
      );
      try {
        final decoded = jsonDecode(text);
        stdout.writeln('jsonDecode OK: ${decoded.runtimeType}');
      } catch (e) {
        stdout.writeln('jsonDecode FAILED: $e');
      }
    }
  }

  await fetch(
    label: 'bytes + identity',
    options: Options(
      responseType: ResponseType.bytes,
      headers: const {'Accept-Encoding': 'identity'},
    ),
  );

  await fetch(
    label: 'plain + identity',
    options: Options(
      responseType: ResponseType.plain,
      headers: const {'Accept-Encoding': 'identity'},
    ),
  );

  await fetch(
    label: 'bytes + (default encoding)',
    options: Options(responseType: ResponseType.bytes),
  );
}

Future<String> _login(
  Dio dio, {
  required String identifier,
  required String password,
}) async {
  final res = await dio.post<Map<String, dynamic>>(
    '/auth/login',
    data: {'identifier': identifier, 'password': password},
    options: Options(responseType: ResponseType.json),
  );
  final token = res.data?['accessToken'];
  if (token is String && token.isNotEmpty) return token;
  throw StateError('Login succeeded but accessToken missing.');
}

String? _readEnvFromDotEnv(String path, String key) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    for (final rawLine in file.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final k = line.substring(0, idx).trim();
      if (k != key) continue;
      var v = line.substring(idx + 1).trim();
      if ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'"))) {
        v = v.substring(1, v.length - 1);
      }
      return v;
    }
  } catch (_) {
    return null;
  }
  return null;
}
