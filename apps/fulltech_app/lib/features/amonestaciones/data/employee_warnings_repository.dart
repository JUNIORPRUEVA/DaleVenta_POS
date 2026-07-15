import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/api/env.dart';
import '../../../core/auth/auth_repository.dart';
import 'employee_warning_model.dart';

final employeeWarningsRepositoryProvider = Provider<EmployeeWarningsRepository>(
  (ref) {
    return EmployeeWarningsRepository(ref.watch(dioProvider));
  },
);

class EmployeeWarningsRepository {
  final Dio _dio;

  EmployeeWarningsRepository(this._dio);

  // ── Admin ──────────────────────────────────────────────────────────────────

  Future<EmployeeWarningsPage> listAll({
    String? employeeUserId,
    String? status,
    String? warningType,
    String? search,
    String? fromDate,
    String? toDate,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _dio.get(
      ApiRoutes.employeeWarnings,
      queryParameters: {
        if (employeeUserId != null) 'employeeUserId': employeeUserId,
        if (status != null) 'status': status,
        if (warningType != null) 'warningType': warningType,
        if (search != null && search.isNotEmpty) 'search': search,
        if (fromDate != null) 'fromDate': fromDate,
        if (toDate != null) 'toDate': toDate,
        'page': page,
        'limit': limit,
      },
    );
    return EmployeeWarningsPage.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> getOne(String id) async {
    final res = await _dio.get(ApiRoutes.employeeWarningDetail(id));
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> create(Map<String, dynamic> data) async {
    final res = await _dio.post(ApiRoutes.employeeWarnings, data: data);
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EmployeeWarning> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.put(ApiRoutes.employeeWarningUpdate(id), data: data);
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete(ApiRoutes.employeeWarningDelete(id));
  }

  Future<EmployeeWarning> annul(String id, String reason) async {
    final res = await _dio.post(
      ApiRoutes.employeeWarningAnnul(id),
      data: {'annulmentReason': reason},
    );
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String> generatePdf(String id) async {
    final res = await _dio.post(ApiRoutes.employeeWarningPdf(id));
    return (res.data as Map<String, dynamic>)['pdfUrl'] as String;
  }

  Future<void> uploadEvidence(String id, FormData formData) async {
    await _dio.post(ApiRoutes.employeeWarningEvidences(id), data: formData);
  }

  // ── Employee ───────────────────────────────────────────────────────────────

  Future<List<EmployeeWarning>> myPending() async {
    final res = await _dio.get(ApiRoutes.employeeWarningsMyPending);
    final list = res.data as List<dynamic>;
    return list
        .map((e) => EmployeeWarning.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmployeeWarning> myWarning(String id) async {
    final res = await _dio.get(ApiRoutes.employeeWarningsMy(id));
    return EmployeeWarning.fromJson(res.data as Map<String, dynamic>);
  }

  List<String> _buildPdfCandidates(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) return const [];

    final out = <String>[];
    final seen = <String>{};
    void addCandidate(String? v) {
      final candidate = (v ?? '').trim();
      if (candidate.isEmpty) return;
      if (seen.add(candidate)) out.add(candidate);
    }

    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      addCandidate(uri.toString());
    } else {
      final normalized = value.replaceAll('\\', '/');
      final baseUrl = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      if (baseUrl.isNotEmpty) {
        if (normalized.startsWith('/')) {
          addCandidate('$baseUrl$normalized');
        } else if (normalized.startsWith('./')) {
          addCandidate('$baseUrl/${normalized.substring(2)}');
        } else {
          addCandidate('$baseUrl/$normalized');
        }
      }
      addCandidate(normalized);
    }

    final baseUri = Uri.tryParse(Env.apiBaseUrl.trim());
    if (baseUri != null) {
      final originals = List<String>.from(out);
      for (final candidate in originals) {
        final cUri = Uri.tryParse(candidate);
        if (cUri == null || !cUri.hasScheme) continue;
        if (cUri.host != baseUri.host) continue;

        final segments = cUri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isEmpty) continue;
        if (segments.first == 'api') {
          final noApi = cUri.replace(pathSegments: segments.skip(1));
          addCandidate(noApi.toString());
        } else {
          final withApi = cUri.replace(pathSegments: ['api', ...segments]);
          addCandidate(withApi.toString());
        }
      }
    }

    return out;
  }

  /// Download PDF bytes with auth.
  /// First tries /employee-warnings/me/:id/pdf; if it returns 404, falls back
  /// to candidate URLs built from the warning pdfUrl field.
  Future<Uint8List> getMyWarningPdfBytes({
    required String id,
    String? rawPdfUrl,
  }) async {
    try {
      final res = await _dio.get<List<int>>(
        ApiRoutes.employeeWarningPdfDownload(id),
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.data != null && res.data!.isNotEmpty) {
        return Uint8List.fromList(res.data!);
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status != 403 && status != 404) rethrow;
    }

    try {
      final res = await _dio.get<List<int>>(
        ApiRoutes.employeeWarningsMyPdf(id),
        options: Options(responseType: ResponseType.bytes),
      );
      if (res.data != null && res.data!.isNotEmpty) {
        return Uint8List.fromList(res.data!);
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status != 404) rethrow;
    }

    final raw = (rawPdfUrl ?? '').trim();
    if (raw.isEmpty) {
      throw Exception('No hay URL de PDF disponible para esta amonestacion');
    }

    final candidates = _buildPdfCandidates(raw);
    DioException? lastDioError;
    for (final candidate in candidates) {
      try {
        final res = await _dio.get<List<int>>(
          candidate,
          options: Options(responseType: ResponseType.bytes),
        );
        if (res.data != null && res.data!.isNotEmpty) {
          return Uint8List.fromList(res.data!);
        }
      } on DioException catch (e) {
        lastDioError = e;
      }
    }

    if (lastDioError != null) {
      throw lastDioError;
    }
    throw Exception('No se pudo descargar el PDF');
  }
}
