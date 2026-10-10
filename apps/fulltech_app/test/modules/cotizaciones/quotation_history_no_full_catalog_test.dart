import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String screenSource;
  late String repositorySource;

  setUpAll(() {
    screenSource = File(
      'lib/modules/cotizaciones/cotizaciones_historial_screen.dart',
    ).readAsStringSync();
    repositorySource = File(
      'lib/modules/cotizaciones/data/cotizaciones_repository.dart',
    ).readAsStringSync();
  });

  test('historial de cotizaciones no descarga catalogo completo', () {
    expect(screenSource, isNot(contains('fetchProducts(')));
    expect(screenSource, isNot(contains('loadAllProductPages')));
    expect(screenSource, isNot(contains('ventasRepositoryProvider')));
    expect(screenSource, contains('listClients('));
  });

  test('historial de cotizaciones usa paginacion remota incremental', () {
    expect(screenSource, contains('static const int _historyPageSize = 50'));
    expect(screenSource, contains('listPage('));
    expect(screenSource, contains('Future<void> _loadMore()'));
    expect(screenSource, contains('_hasMore'));
    expect(screenSource, contains('_nextPage'));
    expect(
      screenSource,
      isNot(contains('final rows = await repo.listAndCache')),
    );
  });

  test(
    'repositorio de cotizaciones envia page/limit/search/filtros remotos',
    () {
      expect(
        repositorySource,
        contains('Future<PagedResult<CotizacionModel>> listPage'),
      );
      expect(repositorySource, contains("'page': page < 1 ? 1 : page"));
      expect(
        repositorySource,
        contains("'limit': limit.clamp(1, 200).toInt()"),
      );
      expect(repositorySource, contains("'search': search.trim()"));
      expect(repositorySource, contains("'customerId': customerId.trim()"));
      expect(repositorySource, contains("'userId': userId.trim()"));
    },
  );
}
