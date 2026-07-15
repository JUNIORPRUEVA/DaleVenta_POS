import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/cache/fulltech_cache_manager.dart';
import '../data/media_gallery_local_repository.dart';
import '../data/media_gallery_repository.dart';
import '../data/media_gallery_sync_utils.dart';

final mediaGalleryBackgroundSyncServiceProvider =
    Provider<MediaGalleryBackgroundSyncService>((ref) {
      final service = MediaGalleryBackgroundSyncService(
        repository: ref.watch(mediaGalleryRepositoryProvider),
        localRepository: ref.watch(mediaGalleryLocalRepositoryProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    });

final mediaGalleryBackgroundSyncBootstrapProvider = Provider<void>((ref) {
  final authState = ref.watch(authStateProvider);
  final service = ref.watch(mediaGalleryBackgroundSyncServiceProvider);
  final role = authState.user?.appRole;
  final viewerUserId = authState.user?.id ?? '';

  final canSync =
      authState.isAuthenticated &&
      role != null &&
      viewerUserId.trim().isNotEmpty &&
      hasPermission(role, AppPermission.viewMediaGallery);

  if (canSync) {
    unawaited(service.start(viewerUserId: viewerUserId));
  } else {
    service.stop();
  }
});

class MediaGalleryBackgroundSyncService {
  MediaGalleryBackgroundSyncService({
    required MediaGalleryRepository repository,
    required MediaGalleryLocalRepository localRepository,
  }) : _repository = repository,
       _localRepository = localRepository;

  static const _pageSize = 48;
  static const _liveSyncInterval = Duration(minutes: 3);
  static const _staleAfter = Duration(minutes: 2);

  final MediaGalleryRepository _repository;
  final MediaGalleryLocalRepository _localRepository;

  Timer? _timer;
  bool _started = false;
  bool _syncInFlight = false;
  bool _queuedForceRemoteSync = false;
  String? _viewerUserId;

  Future<void> start({required String viewerUserId}) async {
    if (_started && _viewerUserId == viewerUserId) return;
    stop();
    _started = true;
    _viewerUserId = viewerUserId;
    _timer = Timer.periodic(_liveSyncInterval, (_) {
      unawaited(syncNow(forceRemote: true));
    });

    final snapshot = await _localRepository.readSnapshot(
      viewerUserId: viewerUserId,
    );
    final shouldRefresh =
        snapshot.items.isEmpty ||
        snapshot.lastSyncedAt == null ||
        DateTime.now().difference(snapshot.lastSyncedAt!) > _staleAfter;
    if (shouldRefresh) {
      await syncNow(forceRemote: true);
    }
  }

  void stop() {
    _started = false;
    _viewerUserId = null;
    _queuedForceRemoteSync = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> syncNow({bool forceRemote = false}) async {
    final viewerUserId = _viewerUserId;
    if (!_started || viewerUserId == null || viewerUserId.trim().isEmpty) {
      return;
    }

    if (_syncInFlight) {
      _queuedForceRemoteSync = _queuedForceRemoteSync || forceRemote;
      return;
    }

    _syncInFlight = true;
    try {
      final snapshot = await _localRepository.readSnapshot(
        viewerUserId: viewerUserId,
      );
      if (!forceRemote &&
          snapshot.lastSyncedAt != null &&
          DateTime.now().difference(snapshot.lastSyncedAt!) <= _staleAfter) {
        return;
      }

      final page = await _repository.fetchPage(
        limit: _pageSize,
        forceRefresh: forceRemote,
      );
      final merged = mergeMediaGalleryItems(
        previousItems: snapshot.items,
        freshItems: page.items,
      );
      final nextCursor =
          snapshot.items.length > page.items.length &&
              snapshot.nextCursor != null
          ? snapshot.nextCursor
          : page.nextCursor;
      final syncedAt = DateTime.now();
      await _localRepository.saveSnapshot(
        viewerUserId: viewerUserId,
        items: merged,
        syncedAt: syncedAt,
        nextCursor: nextCursor,
      );
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          merged.where((item) => item.isImage).map((item) => item.url),
          maxUrls: 60,
        ),
      );
    } catch (_) {
      // Preserve the last local snapshot if the refresh fails.
    } finally {
      _syncInFlight = false;
      if (_queuedForceRemoteSync) {
        _queuedForceRemoteSync = false;
        unawaited(syncNow(forceRemote: true));
      }
    }
  }

  void dispose() {
    stop();
  }
}
