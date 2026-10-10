import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_session_events.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/user_model.dart';
import '../../../features/user/data/users_repository.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../data/service_orders_api.dart';
import '../data/service_orders_local_repository.dart';
import '../service_order_models.dart';

class ServiceOrdersListState {
  final bool loading;
  final bool refreshing;
  final String? error;
  final List<ServiceOrderModel> items;
  final Map<String, ClienteModel> clientsById;
  final Map<String, UserModel> usersById;

  const ServiceOrdersListState({
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.items = const [],
    this.clientsById = const {},
    this.usersById = const {},
  });

  ServiceOrdersListState copyWith({
    bool? loading,
    bool? refreshing,
    String? error,
    List<ServiceOrderModel>? items,
    Map<String, ClienteModel>? clientsById,
    Map<String, UserModel>? usersById,
    bool clearError = false,
  }) {
    return ServiceOrdersListState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      error: clearError ? null : (error ?? this.error),
      items: items ?? this.items,
      clientsById: clientsById ?? this.clientsById,
      usersById: usersById ?? this.usersById,
    );
  }
}

final serviceOrdersListControllerProvider =
    StateNotifierProvider.autoDispose<
      ServiceOrdersListController,
      ServiceOrdersListState
    >((ref) {
      // Recreate the operations list when the authenticated user changes so
      // we never keep list state from a previous session.
      ref.watch(authStateProvider);
      return ServiceOrdersListController(ref);
    });

class ServiceOrdersListController
    extends StateNotifier<ServiceOrdersListState> {
  ServiceOrdersListController(this.ref)
    : super(const ServiceOrdersListState()) {
    load();
  }

  final Ref ref;
  Future<void>? _inFlightLoad;
  Future<void>? _inFlightDeltaSync;

  Map<String, ClienteModel> _clientMapFromOrders(
    List<ServiceOrderModel> orders,
  ) {
    return {
      for (final order in orders)
        if (order.client != null) order.client!.id: order.client!,
    };
  }

  DateTime _orderActivityAt(ServiceOrderModel order) {
    return order.lastStatusChangedAt ?? order.createdAt;
  }

  Future<void> _persistSnapshot({
    required List<ServiceOrderModel> items,
    required Map<String, ClienteModel> clientsById,
    required Map<String, UserModel> usersById,
  }) {
    return ref
        .read(serviceOrdersLocalRepositoryProvider)
        .saveSnapshot(
          orders: items,
          clientsById: clientsById,
          usersById: usersById,
        );
  }

  Future<void> _runIncrementalSync({
    required ServiceOrdersLocalRepository localRepository,
  }) {
    if (_inFlightDeltaSync != null) return _inFlightDeltaSync!;
    _inFlightDeltaSync =
        () async {
          var cursor = await localRepository.readSyncCursor();
          var hasMore = true;
          while (hasMore && mounted) {
            final page = await ref
                .read(serviceOrdersApiProvider)
                .syncOrders(cursor: cursor, limit: 200);
            await localRepository.applySyncPage(
              items: page.items,
              tombstones: page.tombstones,
              nextCursor: page.nextCursor,
            );
            cursor = page.nextCursor;
            hasMore = page.hasMore && (cursor ?? '').trim().isNotEmpty;
            final snapshot = await localRepository.readSnapshot(limit: 200);
            if (!mounted) return;
            final syncedOrders = [...snapshot.orders]
              ..sort(
                (a, b) => _orderActivityAt(b).compareTo(_orderActivityAt(a)),
              );
            state = state.copyWith(
              items: syncedOrders,
              clientsById: {
                ...snapshot.clientsById,
                ..._clientMapFromOrders(syncedOrders),
              },
              usersById: {...state.usersById, ...snapshot.usersById},
              refreshing: hasMore,
              clearError: true,
            );
          }
        }().whenComplete(() {
          _inFlightDeltaSync = null;
          if (mounted) {
            state = state.copyWith(refreshing: false);
          }
        });
    return _inFlightDeltaSync!;
  }

  String _friendlyListMessage(Object error) {
    if (error is ApiException) {
      if (error.type == ApiErrorType.forbidden || error.code == 403) {
        return 'No tienes permiso para ver las órdenes de servicio';
      }
      return error.message;
    }
    return 'No se pudieron cargar las órdenes. Error inesperado.';
  }

  String get _ownerId => ref.read(authStateProvider).user?.id ?? '';
  String get _viewerUserId => ref.read(authStateProvider).user?.id ?? '';

  Future<void> load({bool refresh = false}) async {
    if (_inFlightLoad != null) {
      return _inFlightLoad!;
    }

    if (!refresh && state.items.isEmpty) {
      final localRepository = ref.read(serviceOrdersLocalRepositoryProvider);
      await localRepository.prepareForViewer(_viewerUserId);
      final snapshot = await localRepository.readSnapshot(limit: 200);
      if (!mounted) return;
      if (snapshot.orders.isNotEmpty ||
          snapshot.clientsById.isNotEmpty ||
          snapshot.usersById.isNotEmpty) {
        final cachedOrders = [...snapshot.orders]
          ..sort((a, b) => _orderActivityAt(b).compareTo(_orderActivityAt(a)));
        state = state.copyWith(
          loading: false,
          refreshing: true,
          items: cachedOrders,
          clientsById: {
            ...snapshot.clientsById,
            ..._clientMapFromOrders(cachedOrders),
          },
          usersById: snapshot.usersById,
          clearError: true,
        );
      }
    }

    state = state.copyWith(
      loading: !refresh && state.items.isEmpty,
      refreshing: refresh || state.items.isNotEmpty,
      clearError: true,
    );
    _inFlightLoad = () async {
      try {
        final localRepository = ref.read(serviceOrdersLocalRepositoryProvider);
        await localRepository.prepareForViewer(_viewerUserId);
        if (!mounted) return;
        final orders = await ref.read(serviceOrdersApiProvider).listAllOrders();
        if (!mounted) return;
        final clients = await ref
            .read(clientesRepositoryProvider)
            .listClients(ownerId: _ownerId, pageSize: 200, skipLoader: true)
            .catchError((_) => <ClienteModel>[]);
        if (!mounted) return;
        final users = await ref
            .read(usersRepositoryProvider)
            .getAllUsers(skipLoader: true)
            .catchError((_) => <UserModel>[]);
        if (!mounted) return;
        final clientMap = <String, ClienteModel>{
          for (final client in clients) client.id: client,
        };
        final userMap = <String, UserModel>{
          for (final user in users) user.id: user,
        };

        for (final order in orders) {
          final embeddedClient = order.client;
          if (embeddedClient != null) {
            clientMap[embeddedClient.id] = embeddedClient;
          }
        }

        orders.sort(
          (a, b) => _orderActivityAt(b).compareTo(_orderActivityAt(a)),
        );
        await _persistSnapshot(
          items: orders,
          clientsById: clientMap,
          usersById: userMap,
        );
        unawaited(
          _runIncrementalSync(localRepository: localRepository).catchError((
            Object _,
          ) {
            return null;
          }),
        );
        if (!mounted) return;
        state = state.copyWith(
          loading: false,
          refreshing: false,
          items: orders,
          clientsById: clientMap,
          usersById: userMap,
        );
      } catch (error) {
        if (!mounted) return;
        if (error is ApiException && error.type == ApiErrorType.unauthorized) {
          ref.read(authSessionEventsProvider).requestUnauthorizedLogout();
          return;
        }
        final message = _friendlyListMessage(error);
        state = state.copyWith(
          loading: false,
          refreshing: false,
          error: message,
        );
      } finally {
        _inFlightLoad = null;
      }
    }();

    return _inFlightLoad!;
  }

  Future<void> refresh() => load(refresh: true);

  Future<void> retry() => load(refresh: true);

  Future<void> deleteOrder(String id) async {
    await ref.read(serviceOrdersApiProvider).deleteOrder(id);
    if (!mounted) return;
    final items = state.items
        .where((item) => item.id != id)
        .toList(growable: false);
    state = state.copyWith(items: items);
    await _persistSnapshot(
      items: items,
      clientsById: state.clientsById,
      usersById: state.usersById,
    );
    final localRepository = ref.read(serviceOrdersLocalRepositoryProvider);
    await localRepository.prepareForViewer(_viewerUserId);
    await localRepository.deleteOrder(id);
  }

  Future<int> purgeAllDebug() async {
    final result = await ref.read(serviceOrdersApiProvider).purgeAllDebug();
    final localRepository = ref.read(serviceOrdersLocalRepositoryProvider);
    await localRepository.prepareForViewer(_viewerUserId);
    await localRepository.clearSnapshot();
    if (!mounted) return 0;
    state = state.copyWith(
      items: const [],
      clientsById: const {},
      usersById: const {},
      clearError: true,
    );
    return (result['deletedServiceOrders'] as num?)?.toInt() ?? 0;
  }

  void upsertOrder(ServiceOrderModel order) {
    if (!mounted) return;
    final nextClientMap = {...state.clientsById};
    if (order.client != null) {
      nextClientMap[order.client!.id] = order.client!;
    }
    final items = [...state.items];
    final index = items.indexWhere((item) => item.id == order.id);
    if (index >= 0) {
      items[index] = order;
    } else {
      items.add(order);
    }
    items.sort((a, b) => _orderActivityAt(b).compareTo(_orderActivityAt(a)));
    final usersById = state.usersById;
    state = state.copyWith(items: items, clientsById: nextClientMap);
    unawaited(
      _persistSnapshot(
        items: items,
        clientsById: nextClientMap,
        usersById: usersById,
      ),
    );
    unawaited(
      Future<void>(() async {
        final localRepository = ref.read(serviceOrdersLocalRepositoryProvider);
        await localRepository.prepareForViewer(_viewerUserId);
        await localRepository.saveOrder(
          order: order,
          client: order.client,
          usersById: usersById,
        );
      }),
    );
  }

  void replaceOrderStatus({
    required String orderId,
    required ServiceOrderStatus status,
    DateTime? scheduledFor,
  }) {
    if (!mounted) return;
    final items = state.items
        .map(
          (item) => item.id == orderId
              ? item.copyWith(
                  status: status,
                  scheduledFor: scheduledFor ?? item.scheduledFor,
                )
              : item,
        )
        .toList(growable: false);
    state = state.copyWith(items: items);
    unawaited(
      _persistSnapshot(
        items: items,
        clientsById: state.clientsById,
        usersById: state.usersById,
      ),
    );
  }
}
