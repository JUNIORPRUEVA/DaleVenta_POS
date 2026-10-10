import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/api/api_error_mapper.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/models/user_model.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(dio: ref.watch(dioProvider));
});

class UsersPage {
  const UsersPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.hasMore,
    this.nextPage,
  });

  final List<UserModel> items;
  final int page;
  final int limit;
  final bool hasMore;
  final int? nextPage;

  factory UsersPage.fromJson(dynamic data, {required int fallbackPage}) {
    if (data is List) {
      return UsersPage(
        items: data
            .whereType<Map>()
            .map((row) => UserModel.fromJson(row.cast<String, dynamic>()))
            .toList(growable: false),
        page: fallbackPage,
        limit: data.length,
        hasMore: false,
      );
    }
    if (data is Map) {
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => UserModel.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
      return UsersPage(
        items: items,
        page: (data['page'] as num?)?.toInt() ?? fallbackPage,
        limit: (data['limit'] as num?)?.toInt() ?? items.length,
        hasMore: data['hasMore'] == true,
        nextPage: (data['nextPage'] as num?)?.toInt(),
      );
    }
    return UsersPage(items: const [], page: fallbackPage, limit: 0, hasMore: false);
  }
}

class UsersRepository {
  UsersRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  List<UserModel>? _usersCache;
  DateTime? _usersCacheAt;
  static const Duration _usersCacheTtl = Duration(minutes: 5);

  Future<List<UserModel>> fetchUsers({
    bool skipLoader = false,
    int? page,
    int? limit,
  }) async {
    if (page == null && limit == null) {
      final res = await _dio.get(
        ApiRoutes.users,
        options: skipLoader ? Options(extra: {'skipLoader': true}) : null,
      );
      final data = res.data as List<dynamic>;
      return data
          .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    final result = await fetchUsersPage(
      skipLoader: skipLoader,
      page: page ?? 1,
      limit: limit,
    );
    return result.items;
  }

  Future<UsersPage> fetchUsersPage({
    bool skipLoader = false,
    int page = 1,
    int? limit,
  }) async {
    final res = await _dio.get(
      ApiRoutes.users,
      queryParameters: {
        if (page > 0) 'page': page,
        if (limit != null && limit > 0) 'limit': limit,
      },
      options: skipLoader ? Options(extra: {'skipLoader': true}) : null,
    );
    return UsersPage.fromJson(res.data, fallbackPage: page);
  }

  Future<List<UserModel>> getAllUsers({
    bool forceRefresh = false,
    bool skipLoader = false,
  }) async {
    if (!forceRefresh && _usersCache != null && _usersCacheAt != null) {
      final age = DateTime.now().difference(_usersCacheAt!);
      if (age < _usersCacheTtl) return _usersCache!;
    }

    final users = await fetchUsers(skipLoader: skipLoader);
    _usersCache = users;
    _usersCacheAt = DateTime.now();
    return users;
  }

  Future<UserModel> createUser(Map<String, dynamic> payload) async {
    try {
      final res = await _dio.post(ApiRoutes.users, data: payload);
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiErrorMapper.fromDio(
        error,
        fallbackMessage: 'No se pudo crear el usuario',
        dio: _dio,
      );
    }
  }

  Future<UserModel> updateUser(String id, Map<String, dynamic> payload) async {
    try {
      final res = await _dio.patch(ApiRoutes.updateUser(id), data: payload);
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiErrorMapper.fromDio(
        error,
        fallbackMessage: 'No se pudo actualizar el usuario',
        dio: _dio,
      );
    }
  }

  Future<UserModel> updateUserPermissions(
    String id,
    Map<String, bool> permissions,
  ) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.updateUserPermissions(id),
        data: {'userPermissions': permissions},
      );
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiErrorMapper.fromDio(
        error,
        fallbackMessage: 'No se pudieron actualizar los permisos',
        dio: _dio,
      );
    }
  }

  Future<void> deleteUser(String id) async {
    try {
      await _dio.delete(ApiRoutes.deleteUser(id));
    } on DioException catch (error) {
      throw ApiErrorMapper.fromDio(
        error,
        fallbackMessage: 'No se pudo eliminar el usuario',
        dio: _dio,
      );
    }
  }

  Future<UserModel> setBlocked(String id, bool blocked) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.blockUser(id),
        data: {'blocked': blocked},
      );
      return UserModel.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (error) {
      throw ApiErrorMapper.fromDio(
        error,
        fallbackMessage: 'No se pudo cambiar el estado del usuario',
        dio: _dio,
      );
    }
  }

  Future<UserModel> fetchMe() async {
    final res = await _dio.get(ApiRoutes.usersMe);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> updateMe({
    String? email,
    String? nombreCompleto,
    String? telefono,
    String? password,
    String? fotoPersonalUrl,
  }) async {
    final payload = <String, dynamic>{
      'email': email,
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'password': password,
      'fotoPersonalUrl': fotoPersonalUrl,
    };
    payload.removeWhere((key, value) {
      if (value == null) return true;
      if (key == 'fotoPersonalUrl') return false;
      if (value is String && value.trim().isEmpty) return true;
      return false;
    });

    final res = await _dio.patch(ApiRoutes.usersMe, data: payload);
    _usersCache = null;
    _usersCacheAt = null;
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> signWorkContract({
    required String version,
    required String signatureUrl,
  }) async {
    final payload = {'version': version, 'signatureUrl': signatureUrl};
    final res = await _dio.post(
      ApiRoutes.usersMeWorkContractSign,
      data: payload,
    );
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<WorkContractAiEditResult> applyAiWorkContractEdit({
    required String userId,
    required String instruction,
    required Map<String, dynamic> currentFields,
    required List<Map<String, dynamic>> currentClauses,
  }) async {
    final res = await _dio.post(
      ApiRoutes.userWorkContractAiEdit(userId),
      data: {
        'instruction': instruction,
        'currentFields': currentFields,
        'currentClauses': currentClauses,
      },
    );
    return WorkContractAiEditResult.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String> uploadUserDocument({
    required List<int> bytes,
    required String fileName,
    String? kind,
    String? userId,
  }) async {
    final lower = fileName.toLowerCase();
    final mediaType = lower.endsWith('.png')
        ? MediaType('image', 'png')
        : lower.endsWith('.webp')
        ? MediaType('image', 'webp')
        : MediaType('image', 'jpeg');

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: mediaType,
      ),
      if (kind != null && kind.trim().isNotEmpty) 'kind': kind.trim(),
      if (userId != null && userId.trim().isNotEmpty) 'userId': userId.trim(),
    });

    final res = await _dio.post(ApiRoutes.usersUpload, data: formData);
    final data = res.data as Map<String, dynamic>;
    return (data['url'] ?? data['path'] ?? '') as String;
  }
}

class WorkContractAiEditResult {
  final UserModel user;
  final String summary;
  final String source;
  final String? selectedModel;

  const WorkContractAiEditResult({
    required this.user,
    required this.summary,
    required this.source,
    this.selectedModel,
  });

  factory WorkContractAiEditResult.fromJson(Map<String, dynamic> json) {
    return WorkContractAiEditResult(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      summary: (json['summary'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      selectedModel: json['selectedModel']?.toString(),
    );
  }
}
