import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/models/user_model.dart';

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  return UsersRepository(dio: ref.watch(dioProvider));
});

class UsersRepository {
  UsersRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  List<UserModel>? _usersCache;
  DateTime? _usersCacheAt;
  static const Duration _usersCacheTtl = Duration(minutes: 5);

  Future<List<UserModel>> fetchUsers({bool skipLoader = false}) async {
    final res = await _dio.get(
      ApiRoutes.users,
      options: skipLoader ? Options(extra: {'skipLoader': true}) : null,
    );
    final data = res.data as List<dynamic>;
    return data
        .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final res = await _dio.post(ApiRoutes.users, data: payload);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> updateUser(String id, Map<String, dynamic> payload) async {
    final res = await _dio.patch(ApiRoutes.updateUser(id), data: payload);
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<UserModel> updateUserPermissions(
    String id,
    Map<String, bool> permissions,
  ) async {
    final res = await _dio.patch(
      ApiRoutes.updateUserPermissions(id),
      data: {'userPermissions': permissions},
    );
    return UserModel.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteUser(String id) async {
    await _dio.delete(ApiRoutes.deleteUser(id));
  }

  Future<UserModel> setBlocked(String id, bool blocked) async {
    final res = await _dio.patch(
      ApiRoutes.blockUser(id),
      data: {'blocked': blocked},
    );
    return UserModel.fromJson(res.data as Map<String, dynamic>);
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
      if (value is String && value.trim().isEmpty) return true;
      return false;
    });

    final res = await _dio.patch(ApiRoutes.usersMe, data: payload);
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
