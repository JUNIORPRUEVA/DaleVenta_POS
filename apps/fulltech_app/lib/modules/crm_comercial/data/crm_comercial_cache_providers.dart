import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/crm_comercial_models.dart';
import 'crm_comercial_local_db.dart';

/// Provider que expone la instancia de base de datos local
final crmComercialLocalDbProvider = Provider<CrmComercialLocalDb>((ref) {
  return CrmComercialLocalDb.instance;
});

/// Provider que carga las conversaciones desde el caché local
final crmComercialCachedConversationsProvider =
    FutureProvider<List<CrmComercialInboxConversation>>((ref) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getConversations();
    });

/// Provider que carga los mensajes de una conversación desde el caché local
final crmComercialCachedMessagesProvider =
    FutureProvider.family<List<CrmComercialInboxMessage>, String>((
      ref,
      conversationId,
    ) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getMessages(conversationId);
    });

/// Provider que carga los clientes desde el caché local
final crmComercialCachedCustomersProvider =
    FutureProvider<List<CrmComercialCustomer>>((ref) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getCustomers();
    });

/// Provider que carga un cliente específico desde el caché local
final crmComercialCachedCustomerProvider =
    FutureProvider.family<CrmComercialCustomer?, String>((
      ref,
      customerId,
    ) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getCustomer(customerId);
    });

/// Provider que carga las tareas de seguimiento desde el caché local
final crmComercialCachedFollowupTasksProvider =
    FutureProvider<List<CrmComercialFollowupTask>>((ref) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getFollowupTasks();
    });

/// Provider que carga la configuración desde el caché local
final crmComercialCachedSettingsProvider =
    FutureProvider<CrmComercialSettings?>((ref) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getSettings();
    });

/// Provider que carga las instancias de WhatsApp desde el caché local
final crmComercialCachedWhatsappInstancesProvider =
    FutureProvider<List<CrmComercialWhatsappInstance>>((ref) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getWhatsappInstances();
    });

/// Provider que carga los usuarios desde el caché local
final crmComercialCachedUsersProvider =
    FutureProvider<List<CrmComercialUserRef>>((ref) async {
      final db = ref.watch(crmComercialLocalDbProvider);
      return db.getUsers();
    });

/// Notifier que maneja la sincronización del caché con el servidor
class CrmComercialCacheSyncNotifier
    extends StateNotifier<CrmComercialCacheSyncState> {
  CrmComercialCacheSyncNotifier() : super(CrmComercialCacheSyncState.initial());

  void startSync() {
    state = state.copyWith(isSyncing: true);
  }

  void syncComplete() {
    state = state.copyWith(isSyncing: false, lastSyncAt: DateTime.now());
  }

  void syncError(String error) {
    state = state.copyWith(isSyncing: false, lastError: error);
  }

  void clearError() {
    state = state.copyWith(lastError: null);
  }

  void markDataStale() {
    state = state.copyWith(isStale: true);
  }

  void markDataFresh() {
    state = state.copyWith(isStale: false);
  }
}

/// Estado del sincronizador de caché
class CrmComercialCacheSyncState {
  final bool isSyncing;
  final bool isStale;
  final DateTime? lastSyncAt;
  final String? lastError;

  CrmComercialCacheSyncState({
    required this.isSyncing,
    required this.isStale,
    this.lastSyncAt,
    this.lastError,
  });

  factory CrmComercialCacheSyncState.initial() {
    return CrmComercialCacheSyncState(
      isSyncing: false,
      isStale:
          true, // Inicialmente los datos están "stale" hasta que se carguen
    );
  }

  CrmComercialCacheSyncState copyWith({
    bool? isSyncing,
    bool? isStale,
    DateTime? lastSyncAt,
    String? lastError,
  }) {
    return CrmComercialCacheSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      isStale: isStale ?? this.isStale,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: lastError ?? this.lastError,
    );
  }

  bool get hasData => lastSyncAt != null;
  bool get shouldRefresh => isStale || lastSyncAt == null;
}

/// Provider que expone el estado de sincronización
final crmComercialCacheSyncProvider =
    StateNotifierProvider<
      CrmComercialCacheSyncNotifier,
      CrmComercialCacheSyncState
    >((ref) {
      return CrmComercialCacheSyncNotifier();
    });
