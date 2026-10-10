import 'dart:async';

import 'package:daleventa_pos/core/pagination/paged_list_controller.dart';
import 'package:daleventa_pos/core/pagination/paged_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Registro de una peticion recibida por el fetcher falso.
class _Call {
  _Call(this.page, this.query, this.filters);
  final int page;
  final String query;
  final Map<String, dynamic> filters;
}

/// Fetcher programable: cada pagina puede responder, tardar o fallar.
class _FakeFetcher {
  _FakeFetcher();

  final List<_Call> calls = <_Call>[];
  final Map<int, Object Function()> _handlers = <int, Object Function()>{};

  void onPage(int page, Object Function() handler) {
    _handlers[page] = handler;
  }

  Future<PagedResult<int>> call(PagedFetchRequest request) async {
    calls.add(_Call(request.page, request.query, request.filters));
    final handler = _handlers[request.page];
    if (handler == null) {
      return PagedResult<int>(
        items: const <int>[],
        page: request.page,
        limit: request.limit,
        hasMore: false,
        total: 0,
        nextPage: null,
      );
    }
    final result = handler();
    if (result is Future<PagedResult<int>>) return result;
    if (result is PagedResult<int>) return result;
    throw result; // excepcion programada
  }
}

PagedResult<int> _page({
  required List<int> items,
  required int page,
  int limit = 50,
  int? total,
  bool hasMore = false,
  int? nextPage,
}) {
  return PagedResult<int>(
    items: items,
    page: page,
    limit: limit,
    total: total,
    hasMore: hasMore,
    nextPage: nextPage,
  );
}

PagedListController<int> _controller(_FakeFetcher fetcher, {int pageSize = 50}) {
  return PagedListController<int>(
    fetcher: fetcher.call,
    idOf: (value) => '$value',
    pageSize: pageSize,
  );
}

void main() {
  group('PagedListController', () {
    test('loadInitial carga SOLO la primera pagina y expone total/hasMore', () async {
      final fetcher = _FakeFetcher()
        ..onPage(
          1,
          () => _page(items: List.generate(50, (i) => i + 1), page: 1, total: 103, hasMore: true, nextPage: 2),
        );
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      await controller.loadInitial();

      expect(controller.state.items, hasLength(50));
      expect(controller.state.total, 103);
      expect(controller.state.hasMore, isTrue);
      expect(controller.state.isInitialLoading, isFalse);
      expect(fetcher.calls, hasLength(1));
      expect(fetcher.calls.first.page, 1);
      expect(controller.state.progressLabel, '50 de 103');
    });

    test('loadMore agrega sin duplicar (dedupe por id)', () async {
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1, 2, 3], page: 1, hasMore: true, nextPage: 2))
        // la pagina 2 repite el id 3 a proposito
        ..onPage(2, () => _page(items: [3, 4, 5], page: 2, hasMore: false));
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.state.items, [1, 2, 3, 4, 5]);
      expect(controller.state.hasMore, isFalse);
    });

    test('si falla la pagina 2 se conserva la pagina 1 y retry recupera', () async {
      var failNext = true;
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1, 2], page: 1, hasMore: true, nextPage: 2))
        ..onPage(2, () {
          if (failNext) {
            failNext = false;
            return StateError('network down');
          }
          return _page(items: [3], page: 2, hasMore: false);
        });
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      await controller.loadInitial();
      await controller.loadMore();

      // La pagina 1 NO se pierde.
      expect(controller.state.items, [1, 2]);
      expect(controller.state.error, isNotNull);
      expect(controller.state.hasMore, isTrue);

      await controller.retryLoadMore();

      expect(controller.state.items, [1, 2, 3]);
      expect(controller.state.error, isNull);
    });

    test('no deja que una respuesta vieja pise a la nueva (race)', () async {
      final slow = Completer<PagedResult<int>>();
      final fetcher = _FakeFetcher()
        ..onPage(1, () => slow.future); // la primera consulta se queda colgada
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      // query "ma": peticion lenta
      controller.setQuery('ma', immediate: true);
      await Future<void>.delayed(Duration.zero);

      // query "martillo": llega despues y responde primero
      fetcher.onPage(1, () => _page(items: [77], page: 1, hasMore: false));
      controller.setQuery('martillo', immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.items, [77]);
      expect(controller.state.query, 'martillo');

      // Ahora responde la consulta vieja: NO debe sobrescribir.
      slow.complete(_page(items: [1, 2, 3], page: 1, hasMore: false));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.items, [77]);
      expect(controller.state.query, 'martillo');
    });

    test('setQuery reinicia a la pagina 1 y reemplaza los items', () async {
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1, 2, 3], page: 1, hasMore: true, nextPage: 2))
        ..onPage(2, () => _page(items: [4], page: 2, hasMore: false));
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      await controller.loadInitial();
      await controller.loadMore();
      expect(controller.state.items, hasLength(4));

      fetcher.onPage(1, () => _page(items: [9], page: 1, hasMore: false));
      controller.setQuery('martillo', immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.items, [9]);
      expect(controller.state.page, 1);
      // La ultima llamada vuelve a page 1 con la query nueva.
      expect(fetcher.calls.last.page, 1);
      expect(fetcher.calls.last.query, 'martillo');
    });

    test('setFilters reinicia a la pagina 1 y envia el filtro al servidor', () async {
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1], page: 1, hasMore: false));
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      await controller.loadInitial();
      controller.patchFilter('category', 'Herramientas');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fetcher.calls.last.page, 1);
      expect(fetcher.calls.last.filters['category'], 'Herramientas');
    });

    test('categoria + busqueda viajan en la MISMA peticion', () async {
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1], page: 1, hasMore: false));
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      controller.patchFilter('category', 'Herramientas');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final before = fetcher.calls.length;
      controller.setQuery('bosch', immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fetcher.calls.length, greaterThan(before));
      expect(fetcher.calls.last.filters['category'], 'Herramientas');
      expect(fetcher.calls.last.query, 'bosch');
    });

    test('la busqueda se debounce: no dispara una peticion por tecla', () async {
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1], page: 1, hasMore: false));
      final controller = PagedListController<int>(
        fetcher: fetcher.call,
        idOf: (value) => '$value',
        pageSize: 50,
        debounce: const Duration(milliseconds: 60),
      );
      addTearDown(controller.dispose);

      controller.setQuery('m');
      controller.setQuery('ma');
      controller.setQuery('mar');
      controller.setQuery('martillo');

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(fetcher.calls, hasLength(1));
      expect(fetcher.calls.single.query, 'martillo');
    });

    test('reset vuelve al estado inicial', () async {
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1, 2], page: 1, hasMore: false));
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      await controller.loadInitial();
      controller.setQuery('x', immediate: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.query, 'x');

      await controller.reset();

      expect(controller.state.query, '');
      expect(controller.state.filters, isEmpty);
      expect(controller.state.items, [1, 2]);
    });

    test('dispose durante una peticion en vuelo no lanza', () async {
      final slow = Completer<PagedResult<int>>();
      final fetcher = _FakeFetcher()..onPage(1, () => slow.future);
      final controller = _controller(fetcher);

      unawaited(controller.loadInitial());
      await Future<void>.delayed(Duration.zero);
      controller.dispose();

      slow.complete(_page(items: [1], page: 1, hasMore: false));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Si hubo setState tras dispose, el test fallaria aqui.
    });

    test('no lanza dos peticiones de loadMore simultaneas', () async {
      final first = Completer<PagedResult<int>>();
      final fetcher = _FakeFetcher()
        ..onPage(1, () => _page(items: [1], page: 1, hasMore: true, nextPage: 2))
        ..onPage(2, () => first.future);
      final controller = _controller(fetcher);
      addTearDown(controller.dispose);

      await controller.loadInitial();
      final a = controller.loadMore();
      final b = controller.loadMore();
      await Future<void>.delayed(Duration.zero);

      expect(fetcher.calls.where((call) => call.page == 2), hasLength(1));

      first.complete(_page(items: [2], page: 2, hasMore: false));
      await a;
      await b;

      expect(controller.state.items, [1, 2]);
    });
  });
}
