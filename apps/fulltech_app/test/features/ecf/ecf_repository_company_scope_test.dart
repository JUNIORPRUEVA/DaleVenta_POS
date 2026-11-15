import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AuthController {
  _Auth(super.ref) {
    switchTo('company-a');
  }

  void switchTo(String companyId, {String userId = 'user-a'}) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: userId,
        email: '$userId@example.test',
        nombreCompleto: 'Empresa sintética',
        telefono: '',
        role: 'ADMIN',
        companyId: companyId,
      ),
    );
  }
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final Future<int> Function() respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode([
      {
        'id': 'synthetic-range',
        'documentType': 'E31',
        'nextNumber': await respond(),
      },
    ]),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('una respuesta tardía de A no sustituye la numeración de B', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    late ProviderContainer container;
    final dio = Dio()
      ..httpClientAdapter = _Adapter(() async {
        final companyId = container.read(authStateProvider).user!.companyId;
        if (companyId == 'company-a') {
          firstStarted.complete();
          await releaseFirst.future;
          return 1;
        }
        return 1001;
      });
    container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        authStateProvider.overrideWith(_Auth.new),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(ecfSequencesProvider, (_, _) {});
    addTearDown(subscription.close);

    final previous = container.read(ecfSequencesProvider.future);
    await firstStarted.future;
    (container.read(authStateProvider.notifier) as _Auth).switchTo('company-b');
    expect(
      (await container.read(ecfSequencesProvider.future)).single.nextNumber,
      1001,
    );

    releaseFirst.complete();
    await previous;
    expect(
      (await container.read(ecfSequencesProvider.future)).single.nextNumber,
      1001,
    );
  });

  test('otra sesión de la misma empresa relee su numeración', () async {
    var calls = 0;
    final dio = Dio()..httpClientAdapter = _Adapter(() async => ++calls);
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
        authStateProvider.overrideWith(_Auth.new),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(ecfSequencesProvider, (_, _) {});
    addTearDown(subscription.close);

    expect(
      (await container.read(ecfSequencesProvider.future)).single.nextNumber,
      1,
    );
    (container.read(authStateProvider.notifier) as _Auth).switchTo(
      'company-a',
      userId: 'user-b',
    );
    expect(
      (await container.read(ecfSequencesProvider.future)).single.nextNumber,
      2,
    );
    expect(calls, 2);
  });
}
