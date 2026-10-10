import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/user/data/users_repository.dart';

void main() {
  UsersRepository buildRepository(
    ResponseBody Function(RequestOptions options) handler,
  ) {
    return UsersRepository(
      dio: Dio()
        ..httpClientAdapter = _FakeHttpClientAdapter(
          (options) async => handler(options),
        ),
    );
  }

  ResponseBody jsonResponse(dynamic body, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, dynamic> userRow({String id = 'user-1'}) {
    return {
      'id': id,
      'email': '$id@example.test',
      'nombreCompleto': 'Usuario $id',
      'telefono': '',
      'role': 'CAJERO',
      'blocked': false,
    };
  }

  test('fetchUsersPage envia page/limit y conserva metadatos', () async {
    RequestOptions? request;
    final repository = buildRepository((options) {
      request = options;
      return jsonResponse({
        'items': [userRow()],
        'page': 2,
        'limit': 50,
        'hasMore': true,
        'nextPage': 3,
      });
    });

    final page = await repository.fetchUsersPage(page: 2, limit: 50);

    expect(request!.queryParameters['page'], 2);
    expect(request!.queryParameters['limit'], 50);
    expect(page.items.single.id, 'user-1');
    expect(page.hasMore, isTrue);
    expect(page.nextPage, 3);
  });

  test('fetchUsers mantiene compatibilidad con lista plana legacy', () async {
    final repository = buildRepository((_) => jsonResponse([userRow()]));

    final users = await repository.fetchUsers();

    expect(users, hasLength(1));
    expect(users.single.id, 'user-1');
  });
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
