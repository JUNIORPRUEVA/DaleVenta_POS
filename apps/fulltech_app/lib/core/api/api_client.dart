import 'package:dio/dio.dart';
import 'env.dart';

class ApiClient {
  final Dio dio;

  ApiClient()
    : dio = Dio(
        BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: Duration(milliseconds: Env.apiTimeoutMs),
          sendTimeout: Duration(milliseconds: Env.apiTimeoutMs),
          receiveTimeout: Duration(milliseconds: Env.apiTimeoutMs),
          headers: {'Accept': 'application/json'},
        ),
      );
}
