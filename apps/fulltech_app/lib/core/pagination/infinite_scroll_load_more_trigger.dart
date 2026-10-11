import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

typedef InfiniteScrollLoadMoreCallback = void Function();
typedef InfiniteScrollClock = DateTime Function();

DateTime _systemNow() => DateTime.now();

/// Gates automatic infinite-scroll pagination so one scroll gesture can request
/// at most one additional page.
///
/// A plain `extentAfter < threshold` listener can cascade when the backend is
/// fast: page 2 appends, layout changes, the viewport remains near the bottom,
/// and the listener immediately asks for page 3, 4, ... without a new user
/// gesture. This trigger disarms after one request and rearms only after the
/// scroll activity has ended and a small quiet window has elapsed, or when the
/// caller explicitly resets it after a query/filter change.
class InfiniteScrollLoadMoreTrigger {
  InfiniteScrollLoadMoreTrigger({
    this.threshold = 420,
    this.rearmDelay = const Duration(milliseconds: 700),
    InfiniteScrollClock? clock,
  }) : _clock = clock ?? _systemNow;

  final double threshold;
  final Duration rearmDelay;
  final InfiniteScrollClock _clock;
  bool _armed = true;
  DateTime? _blockedUntil;
  bool _needsNewScrollStart = false;
  bool _scrollEndedAfterTrigger = true;

  bool get armed => _armed;

  void reset() {
    _armed = true;
    _blockedUntil = null;
    _needsNewScrollStart = false;
    _scrollEndedAfterTrigger = true;
  }

  bool handleUserScrollIntent(
    ScrollMetrics? metrics, {
    required bool canLoadMore,
    required bool isLoadingMore,
  }) {
    if (metrics == null || metrics.extentAfter > threshold) return false;

    if (!_armed) {
      if (!_canRearmAfterCompletedGesture()) return false;
      _armed = true;
      _blockedUntil = null;
      _needsNewScrollStart = false;
      _scrollEndedAfterTrigger = true;
    }

    return _trigger(canLoadMore: canLoadMore, isLoadingMore: isLoadingMore);
  }

  bool handleNotification(
    ScrollNotification notification, {
    required bool canLoadMore,
    required bool isLoadingMore,
  }) {
    if (notification is ScrollStartNotification) {
      _rearmIfQuietWindowElapsed();
      return false;
    }

    if (notification is ScrollEndNotification) {
      if (_needsNewScrollStart) {
        _scrollEndedAfterTrigger = true;
      }
      _extendQuietWindowIfWaitingForNewGesture();
      return false;
    }

    final isScrollMovement =
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification;
    if (!isScrollMovement) {
      return false;
    }

    if (!_armed) {
      return false;
    }

    if (notification.metrics.extentAfter > threshold) return false;

    return _trigger(canLoadMore: canLoadMore, isLoadingMore: isLoadingMore);
  }

  bool _trigger({required bool canLoadMore, required bool isLoadingMore}) {
    if (!canLoadMore || isLoadingMore) return false;

    _armed = false;
    _blockedUntil = _clock().add(rearmDelay);
    _needsNewScrollStart = true;
    _scrollEndedAfterTrigger = false;
    return true;
  }

  void _rearmIfQuietWindowElapsed() {
    final blockedUntil = _blockedUntil;
    if (!_needsNewScrollStart ||
        (_scrollEndedAfterTrigger &&
            (blockedUntil == null || !_clock().isBefore(blockedUntil)))) {
      _armed = true;
      _blockedUntil = null;
      _needsNewScrollStart = false;
      _scrollEndedAfterTrigger = false;
    }
  }

  void _extendQuietWindowIfWaitingForNewGesture() {
    if (!_needsNewScrollStart) return;
    _blockedUntil = _clock().add(rearmDelay);
  }

  bool _canRearmAfterCompletedGesture() {
    if (!_needsNewScrollStart || !_scrollEndedAfterTrigger) return false;
    final blockedUntil = _blockedUntil;
    return blockedUntil == null || !_clock().isBefore(blockedUntil);
  }
}

/// Reusable listener for paged lists that load more data near the end.
///
/// Callers provide the current pagination state and this widget guarantees that
/// layout changes after appending a page cannot immediately request the next
/// page. It should wrap the scrollable that owns the paged content.
class InfiniteScrollLoadMoreListener extends StatefulWidget {
  const InfiniteScrollLoadMoreListener({
    super.key,
    required this.child,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    this.threshold = 420,
    this.rearmDelay = const Duration(milliseconds: 700),
    this.resetKeys = const <Object?>[],
  });

  final Widget child;
  final bool hasMore;
  final bool isLoadingMore;
  final InfiniteScrollLoadMoreCallback onLoadMore;
  final double threshold;
  final Duration rearmDelay;
  final List<Object?> resetKeys;

  @override
  State<InfiniteScrollLoadMoreListener> createState() =>
      _InfiniteScrollLoadMoreListenerState();
}

class _InfiniteScrollLoadMoreListenerState
    extends State<InfiniteScrollLoadMoreListener> {
  late final InfiniteScrollLoadMoreTrigger _trigger;
  ScrollMetrics? _lastMetrics;

  @override
  void initState() {
    super.initState();
    _trigger = InfiniteScrollLoadMoreTrigger(
      threshold: widget.threshold,
      rearmDelay: widget.rearmDelay,
    );
  }

  @override
  void didUpdateWidget(InfiniteScrollLoadMoreListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameKeys(oldWidget.resetKeys, widget.resetKeys)) {
      _trigger.reset();
    }
  }

  bool _onNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    _lastMetrics = notification.metrics;
    final shouldLoad = _trigger.handleNotification(
      notification,
      canLoadMore: widget.hasMore,
      isLoadingMore: widget.isLoadingMore,
    );
    if (shouldLoad) widget.onLoadMore();
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy <= 0) return;
    final shouldLoad = _trigger.handleUserScrollIntent(
      _lastMetrics,
      canLoadMore: widget.hasMore,
      isLoadingMore: widget.isLoadingMore,
    );
    if (shouldLoad) widget.onLoadMore();
  }

  bool _sameKeys(List<Object?> a, List<Object?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      ),
    );
  }
}
