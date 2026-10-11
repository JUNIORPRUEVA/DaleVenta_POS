import 'package:daleventa_pos/core/pagination/infinite_scroll_load_more_trigger.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

FixedScrollMetrics _metrics({required double extentAfter}) {
  return FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 1000,
    pixels: 1000 - extentAfter,
    viewportDimension: 500,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );
}

ScrollUpdateNotification _update(
  double extentAfter, {
  required BuildContext context,
}) {
  return ScrollUpdateNotification(
    metrics: _metrics(extentAfter: extentAfter),
    context: context,
  );
}

ScrollStartNotification _start(
  double extentAfter, {
  required BuildContext context,
}) {
  return ScrollStartNotification(
    metrics: _metrics(extentAfter: extentAfter),
    context: context,
  );
}

ScrollEndNotification _end(
  double extentAfter, {
  required BuildContext context,
}) {
  return ScrollEndNotification(
    metrics: _metrics(extentAfter: extentAfter),
    context: context,
  );
}

class _FakeClock {
  DateTime value = DateTime(2026, 1, 1);

  DateTime call() => value;

  void elapse(Duration duration) {
    value = value.add(duration);
  }
}

void main() {
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return captured;
  }

  testWidgets('one scroll activity can trigger only one loadMore', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    final trigger = InfiniteScrollLoadMoreTrigger(threshold: 400);

    expect(
      trigger.handleNotification(
        _update(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
    expect(
      trigger.handleNotification(
        _update(200, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    expect(
      trigger.handleNotification(
        _update(50, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
  });

  testWidgets('new scroll from away from end rearms the next page', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    final clock = _FakeClock();
    final trigger = InfiniteScrollLoadMoreTrigger(
      threshold: 400,
      clock: clock.call,
    );

    expect(
      trigger.handleNotification(
        _update(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
    expect(
      trigger.handleNotification(
        _end(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    expect(
      trigger.handleNotification(
        _update(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );

    clock.elapse(const Duration(milliseconds: 2500));

    expect(
      trigger.handleNotification(
        _start(900, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    expect(
      trigger.handleNotification(
        _update(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
  });

  testWidgets('quiet rearm delay blocks fast backend cascades', (tester) async {
    final context = await pumpContext(tester);
    final clock = _FakeClock();
    final trigger = InfiniteScrollLoadMoreTrigger(
      threshold: 400,
      clock: clock.call,
    );

    expect(
      trigger.handleNotification(
        _update(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );

    clock.elapse(const Duration(milliseconds: 50));

    expect(
      trigger.handleNotification(
        _end(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    expect(
      trigger.handleNotification(
        _update(120, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
  });

  testWidgets(
    'wheel intent at bottom can load next page without scrolling away',
    (tester) async {
      final context = await pumpContext(tester);
      final clock = _FakeClock();
      final trigger = InfiniteScrollLoadMoreTrigger(
        threshold: 400,
        clock: clock.call,
      );

      expect(
        trigger.handleNotification(
          _update(250, context: context),
          canLoadMore: true,
          isLoadingMore: false,
        ),
        isTrue,
      );
      expect(
        trigger.handleNotification(
          _end(0, context: context),
          canLoadMore: true,
          isLoadingMore: false,
        ),
        isFalse,
      );

      clock.elapse(const Duration(milliseconds: 2500));

      expect(
        trigger.handleUserScrollIntent(
          _metrics(extentAfter: 0),
          canLoadMore: true,
          isLoadingMore: false,
        ),
        isTrue,
      );
    },
  );

  testWidgets('bottom wheel intent respects the rearm delay', (tester) async {
    final context = await pumpContext(tester);
    final clock = _FakeClock();
    final trigger = InfiniteScrollLoadMoreTrigger(
      threshold: 400,
      clock: clock.call,
    );

    expect(
      trigger.handleNotification(
        _update(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
    expect(
      trigger.handleNotification(
        _end(0, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    clock.elapse(const Duration(milliseconds: 250));

    expect(
      trigger.handleUserScrollIntent(
        _metrics(extentAfter: 0),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
  });

  testWidgets('same long scroll cannot rearm even after quiet window elapsed', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    final clock = _FakeClock();
    final trigger = InfiniteScrollLoadMoreTrigger(
      threshold: 400,
      clock: clock.call,
    );

    expect(
      trigger.handleNotification(
        _start(900, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    expect(
      trigger.handleNotification(
        _update(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );

    clock.elapse(const Duration(milliseconds: 3000));

    expect(
      trigger.handleNotification(
        _update(900, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    clock.elapse(const Duration(milliseconds: 1000));
    expect(
      trigger.handleNotification(
        _update(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );

    clock.elapse(const Duration(milliseconds: 2500));
    expect(
      trigger.handleNotification(
        _end(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    clock.elapse(const Duration(milliseconds: 700));
    expect(
      trigger.handleNotification(
        _start(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );
    expect(
      trigger.handleNotification(
        _update(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
  });

  testWidgets(
    'does not trigger while loading or when there are no more pages',
    (tester) async {
      final context = await pumpContext(tester);
      final trigger = InfiniteScrollLoadMoreTrigger(threshold: 400);

      expect(
        trigger.handleNotification(
          _update(250, context: context),
          canLoadMore: true,
          isLoadingMore: true,
        ),
        isFalse,
      );
      expect(
        trigger.handleNotification(
          _update(250, context: context),
          canLoadMore: false,
          isLoadingMore: false,
        ),
        isFalse,
      );
    },
  );

  testWidgets('reset query rearms the trigger cleanly', (tester) async {
    final context = await pumpContext(tester);
    final trigger = InfiniteScrollLoadMoreTrigger(threshold: 400);

    expect(
      trigger.handleNotification(
        _update(250, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
    expect(
      trigger.handleNotification(
        _update(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isFalse,
    );

    trigger.reset();

    expect(
      trigger.handleNotification(
        _update(240, context: context),
        canLoadMore: true,
        isLoadingMore: false,
      ),
      isTrue,
    );
  });

  testWidgets(
    'listener ignores idle, rebuilds and layout changes until a new scroll',
    (tester) async {
      var loadMoreCalls = 0;
      var itemCount = 80;
      var queryKey = 'initial';

      Widget buildHarness() {
        return Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            height: 320,
            child: InfiniteScrollLoadMoreListener(
              threshold: 400,
              rearmDelay: Duration.zero,
              hasMore: true,
              isLoadingMore: false,
              resetKeys: <Object?>[queryKey],
              onLoadMore: () => loadMoreCalls++,
              child: ListView.builder(
                itemExtent: 40,
                itemCount: itemCount,
                itemBuilder: (_, index) => Text('Item $index'),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildHarness());
      await tester.pump();
      expect(loadMoreCalls, 0);

      await tester.drag(find.byType(ListView), const Offset(0, -2600));
      await tester.pump();
      expect(loadMoreCalls, 1);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 1200));

      itemCount = 130;
      await tester.pumpWidget(buildHarness());
      await tester.pump();
      expect(loadMoreCalls, 1);

      await tester.pump(const Duration(milliseconds: 250));
      expect(loadMoreCalls, 1);

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump();
      expect(loadMoreCalls, 2);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(loadMoreCalls, 2);
    },
  );
}
