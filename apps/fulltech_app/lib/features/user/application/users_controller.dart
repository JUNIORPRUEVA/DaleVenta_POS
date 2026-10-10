import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_model.dart';
import '../data/users_repository.dart';

final usersControllerProvider =
    StateNotifierProvider<UsersController, AsyncValue<List<UserModel>>>(
      (ref) =>
          UsersController(ref: ref, repo: ref.watch(usersRepositoryProvider)),
    );

class UsersController extends StateNotifier<AsyncValue<List<UserModel>>> {
  UsersController({required this.ref, required this.repo})
    : super(const AsyncLoading()) {
    load();
  }

  final Ref ref;
  final UsersRepository repo;
  static const _pageLimit = 50;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextPage = 2;

  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;

  Future<void> load() async {
    try {
      final page = await repo.fetchUsersPage(page: 1, limit: _pageLimit);
      _hasMore = page.hasMore;
      _nextPage = page.nextPage ?? 2;
      state = AsyncData(page.items);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    state = AsyncData(state.value ?? const []);
    try {
      final page = await repo.fetchUsersPage(
        page: _nextPage,
        limit: _pageLimit,
        skipLoader: true,
      );
      final current = state.value ?? const <UserModel>[];
      final existingIds = current.map((item) => item.id).toSet();
      _hasMore = page.hasMore;
      _nextPage = page.nextPage ?? (_nextPage + 1);
      _loadingMore = false;
      state = AsyncData([
        ...current,
        ...page.items.where((item) => !existingIds.contains(item.id)),
      ]);
    } catch (e, st) {
      _loadingMore = false;
      state = AsyncError(e, st);
    }
  }

  Future<void> create(Map<String, dynamic> payload) async {
    final previous = state;
    state = const AsyncLoading();
    try {
      await repo.createUser(payload);
      await load();
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> update(String id, Map<String, dynamic> payload) async {
    final previous = state;
    state = const AsyncLoading();
    try {
      await repo.updateUser(id, payload);
      await load();
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> updatePermissions(
    String id,
    Map<String, bool> permissions,
  ) async {
    final previous = state;
    state = const AsyncLoading();
    try {
      await repo.updateUserPermissions(id, permissions);
      await load();
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final previous = state;
    state = const AsyncLoading();
    try {
      await repo.deleteUser(id);
      await load();
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<void> toggleBlock(String id, bool next) async {
    final previous = state;
    state = const AsyncLoading();
    try {
      await repo.setBlocked(id, next);
      await load();
    } catch (e) {
      state = previous;
      rethrow;
    }
  }

  Future<String> uploadDocument({
    required List<int> bytes,
    required String fileName,
    String? kind,
    String? userId,
  }) {
    return repo.uploadUserDocument(
      bytes: bytes,
      fileName: fileName,
      kind: kind,
      userId: userId,
    );
  }
}
