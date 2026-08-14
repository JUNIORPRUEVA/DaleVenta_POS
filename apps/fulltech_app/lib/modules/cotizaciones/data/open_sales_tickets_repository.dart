import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';

final openSalesTicketsRepositoryProvider = Provider<OpenSalesTicketsRepository>(
  (ref) {
    return OpenSalesTicketsRepository(dio: ref.watch(dioProvider));
  },
);

class OpenSalesTicketsRepository {
  OpenSalesTicketsRepository({required Dio dio}) : _dio = dio;

  final Dio _dio;

  Future<Map<String, dynamic>?> fetch() async {
    final res = await _dio.get(
      ApiRoutes.salesOpenTickets,
      options: Options(extra: {'skipLoader': true, 'silent': true}),
    );
    final data = res.data;
    if (data is Map) return data.cast<String, dynamic>();
    return null;
  }

  Future<void> replace({
    required String? activeId,
    required List<Map<String, dynamic>> tickets,
  }) async {
    await _dio.put(
      ApiRoutes.salesOpenTickets,
      data: {'activeId': activeId, 'tickets': tickets},
      options: Options(extra: {'skipLoader': true, 'silent': true}),
    );
  }
}
