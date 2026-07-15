import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/errors/api_exception.dart';
import '../data/media_gallery_local_repository.dart';
import '../data/media_gallery_repository.dart';
import '../data/media_gallery_sync_utils.dart';
import '../media_gallery_models.dart';

class MediaGalleryState {
  const MediaGalleryState({
    this.items = const [],
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.nextCursor,
    this.lastSyncedAt,
    this.typeFilter = MediaGalleryTypeFilter.all,
    this.installationFilter = MediaGalleryInstallationFilter.all,
  });

  final List<MediaGalleryItem> items;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final String? nextCursor;
  final DateTime? lastSyncedAt;
  final MediaGalleryTypeFilter typeFilter;
  final MediaGalleryInstallationFilter installationFilter;

  List<MediaGalleryItem> get visibleItems {
    return uniqueMediaGalleryItems(items)
        .where((item) {
          final matchesType = switch (typeFilter) {
            MediaGalleryTypeFilter.all => true,
            MediaGalleryTypeFilter.image => item.isImage,
            MediaGalleryTypeFilter.video => item.isVideo,
          };
          if (!matchesType) return false;

          return switch (installationFilter) {
            MediaGalleryInstallationFilter.all => true,
            MediaGalleryInstallationFilter.completed =>
              item.isInstallationCompleted,
            MediaGalleryInstallationFilter.pending =>
              !item.isInstallationCompleted,
          };
        })
        .toList(growable: false);
  }

  MediaGalleryState copyWith({
    List<MediaGalleryItem>? items,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    String? error,
    String? nextCursor,
    DateTime? lastSyncedAt,
    MediaGalleryTypeFilter? typeFilter,
    MediaGalleryInstallationFilter? installationFilter,
    bool clearError = false,
    bool clearNextCursor = false,
  }) {
    return MediaGalleryState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      nextCursor: clearNextCursor ? null : (nextCursor ?? this.nextCursor),
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      typeFilter: typeFilter ?? this.typeFilter,
      installationFilter: installationFilter ?? this.installationFilter,
    );
  }
}

final mediaGalleryControllerProvider =
    StateNotifierProvider<MediaGalleryController, MediaGalleryState>((ref) {
      return MediaGalleryController(ref);
    });

class MediaGalleryController extends StateNotifier<MediaGalleryState> {
  MediaGalleryController(this.ref) : super(const MediaGalleryState()) {
    unawaited(load());
  }

  static const _pageSize = 48;
  static const _staleAfter = Duration(minutes: 2);
  static const _silentRefreshMinInterval = Duration(seconds: 20);

  final Ref ref;
  Future<void>? _inFlightLoad;
  DateTime? _lastSuccessfulRemoteSyncAt;

  bool get _canViewGallery {
    final auth = ref.read(authStateProvider);
    final role = auth.user?.appRole;
    return auth.isAuthenticated &&
        role != null &&
        hasPermission(role, AppPermission.viewMediaGallery);
  }

  String get _viewerUserId => ref.read(authStateProvider).user?.id ?? '';

  Future<MediaGalleryLocalSnapshot> _readLocalSnapshot() {
    return ref
        .read(mediaGalleryLocalRepositoryProvider)
        .readSnapshot(viewerUserId: _viewerUserId);
  }

  Future<void> _persistSnapshot({
    required List<MediaGalleryItem> items,
    required DateTime syncedAt,
    required String? nextCursor,
  }) {
    return ref
        .read(mediaGalleryLocalRepositoryProvider)
        .saveSnapshot(
          viewerUserId: _viewerUserId,
          items: items,
          syncedAt: syncedAt,
          nextCursor: nextCursor,
        );
  }

  String _friendlyMessage(Object error) {
    if (error is ApiException) {
      if (error.type == ApiErrorType.forbidden || error.code == 403) {
        return 'No tienes permiso para ver la galería de medios';
      }
      return error.message;
    }
    return 'No se pudo cargar la galería de medios';
  }

  Future<void> load({bool refresh = false, bool forceRemote = false}) {
    if (!_canViewGallery) {
      state = const MediaGalleryState();
      return Future.value();
    }
    if (_inFlightLoad != null) return _inFlightLoad!;
    _inFlightLoad = _loadImpl(
      refresh: refresh,
      forceRemote: forceRemote,
    ).whenComplete(() => _inFlightLoad = null);
    return _inFlightLoad!;
  }

  Future<void> _loadImpl({
    required bool refresh,
    required bool forceRemote,
  }) async {
    final snapshot = await _readLocalSnapshot();
    if (state.items.isEmpty && snapshot.items.isNotEmpty) {
      _lastSuccessfulRemoteSyncAt ??= snapshot.lastSyncedAt;
      final uniqueSnapshotItems = uniqueMediaGalleryItems(snapshot.items);
      state = state.copyWith(
        items: uniqueSnapshotItems,
        nextCursor: snapshot.nextCursor,
        lastSyncedAt: snapshot.lastSyncedAt,
        loading: false,
        refreshing: false,
        clearError: true,
      );
    }

    final hasLocalData = state.items.isNotEmpty || snapshot.items.isNotEmpty;
    final effectiveLastSyncedAt = state.lastSyncedAt ?? snapshot.lastSyncedAt;
    final shouldFetchRemote =
        forceRemote ||
        refresh ||
        !hasLocalData ||
        effectiveLastSyncedAt == null ||
        DateTime.now().difference(effectiveLastSyncedAt) > _staleAfter;

    if (!shouldFetchRemote) {
      state = state.copyWith(
        loading: false,
        refreshing: false,
        nextCursor: state.nextCursor ?? snapshot.nextCursor,
        lastSyncedAt: effectiveLastSyncedAt,
        clearError: true,
      );
      return;
    }

    if (forceRemote &&
        state.items.isNotEmpty &&
        _lastSuccessfulRemoteSyncAt != null &&
        DateTime.now().difference(_lastSuccessfulRemoteSyncAt!) <
            _silentRefreshMinInterval) {
      return;
    }

    state = state.copyWith(
      loading: !hasLocalData,
      refreshing: hasLocalData,
      loadingMore: false,
      clearError: true,
    );

    try {
      final page = await ref
          .read(mediaGalleryRepositoryProvider)
          .fetchPage(limit: _pageSize, forceRefresh: forceRemote || refresh);
      final previousItems = state.items.isEmpty
          ? uniqueMediaGalleryItems(snapshot.items)
          : uniqueMediaGalleryItems(state.items);
      final merged = mergeMediaGalleryItems(
        previousItems: previousItems,
        freshItems: page.items,
      );
      final syncedAt = DateTime.now();
      final previousCursor = state.nextCursor ?? snapshot.nextCursor;
      final nextCursor =
          previousItems.length > page.items.length && previousCursor != null
          ? previousCursor
          : page.nextCursor;

      await _persistSnapshot(
        items: merged,
        syncedAt: syncedAt,
        nextCursor: nextCursor,
      );
      state = state.copyWith(
        items: merged,
        nextCursor: nextCursor,
        lastSyncedAt: syncedAt,
        loading: false,
        refreshing: false,
        loadingMore: false,
        clearError: true,
      );
      _lastSuccessfulRemoteSyncAt = syncedAt;
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          merged.where((item) => item.isImage).map((item) => item.url),
          maxUrls: 60,
        ),
      );
    } catch (error) {
      if (state.items.isNotEmpty || snapshot.items.isNotEmpty) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          loadingMore: false,
        );
        return;
      }
      state = state.copyWith(
        loading: false,
        refreshing: false,
        loadingMore: false,
        error: _friendlyMessage(error),
      );
    }
  }

  Future<void> refresh() => load(refresh: true, forceRemote: true);

  Future<void> retry() => load(refresh: true, forceRemote: true);

  Future<void> loadMore() async {
    if (!_canViewGallery || state.loadingMore) return;
    final cursor = (state.nextCursor ?? '').trim();
    if (cursor.isEmpty) return;

    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref
          .read(mediaGalleryRepositoryProvider)
          .fetchPage(cursor: cursor, limit: _pageSize);
      final merged = mergeMediaGalleryItems(
        previousItems: state.items,
        freshItems: page.items,
      );
      final syncedAt = DateTime.now();
      await _persistSnapshot(
        items: merged,
        syncedAt: syncedAt,
        nextCursor: page.nextCursor,
      );
      state = state.copyWith(
        items: merged,
        nextCursor: page.nextCursor,
        lastSyncedAt: syncedAt,
        loadingMore: false,
      );
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          page.items.where((item) => item.isImage).map((item) => item.url),
          maxUrls: 24,
        ),
      );
    } catch (error) {
      state = state.copyWith(
        loadingMore: false,
        error: _friendlyMessage(error),
      );
    }
  }

  void setTypeFilter(MediaGalleryTypeFilter filter) {
    if (filter == state.typeFilter) return;
    state = state.copyWith(typeFilter: filter);
  }

  void setInstallationFilter(MediaGalleryInstallationFilter filter) {
    if (filter == state.installationFilter) return;
    state = state.copyWith(installationFilter: filter);
  }

  Future<void> deleteItem(String id) async {
    if (!_canViewGallery) return;
    try {
      await ref.read(mediaGalleryRepositoryProvider).deleteItem(id);
      final updatedItems = state.items
          .where((item) => item.id != id)
          .toList(growable: false);
      state = state.copyWith(items: updatedItems);
      // Update local cache
      final syncedAt = state.lastSyncedAt ?? DateTime.now();
      await _persistSnapshot(
        items: updatedItems,
        syncedAt: syncedAt,
        nextCursor: state.nextCursor,
      );
    } catch (error) {
      state = state.copyWith(error: _friendlyMessage(error));
    }
  }

  Future<void> markForPublicidad(String id) async {
    if (!_canViewGallery) return;
    try {
      await ref.read(mediaGalleryRepositoryProvider).markForPublicidad(id);
      final updatedItems = state.items
          .map((item) {
            if (item.id != id) return item;
            return MediaGalleryItem(
              id: item.id,
              url: item.url,
              type: item.type,
              comment: item.comment,
              orderId: item.orderId,
              createdAt: item.createdAt,
              uploadedByRole: item.uploadedByRole,
              orderStatus: item.orderStatus,
              isInstallationCompleted: item.isInstallationCompleted,
              forPublicidad: true,
            );
          })
          .toList(growable: false);
      state = state.copyWith(items: updatedItems);
      await _persistSnapshot(
        items: updatedItems,
        syncedAt: state.lastSyncedAt ?? DateTime.now(),
        nextCursor: state.nextCursor,
      );
    } catch (error) {
      state = state.copyWith(error: _friendlyMessage(error));
    }
  }
}
