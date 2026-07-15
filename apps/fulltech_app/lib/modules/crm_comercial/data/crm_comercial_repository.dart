import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:typed_data';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../models/crm_comercial_models.dart';
import 'crm_comercial_local_db.dart';
import 'crm_comercial_cache_providers.dart';

final crmComercialRepositoryProvider = Provider<CrmComercialRepository>((ref) {
  return CrmComercialRepository(
    ref.watch(dioProvider),
    ref.watch(crmComercialLocalDbProvider),
  );
});

class CrmComercialRepository {
  CrmComercialRepository(this._dio, this._localDb);

  final Dio _dio;
  final CrmComercialLocalDb _localDb;

  static final Options _silentRequestOptions = Options(
    extra: {'skipLoader': true, 'silent': true},
  );

  String _extractErrorMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data.trim();
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first.trim();
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    }
    return fallback;
  }

  ApiException _mapError(DioException error, String fallback) {
    final message = _extractErrorMessage(error.response?.data, fallback);
    return ApiException.detailed(
      message: message,
      code: error.response?.statusCode,
      responseBody: error.response?.data?.toString(),
      uri: error.requestOptions.uri,
      method: error.requestOptions.method,
      technicalDetails: error.message,
    );
  }

  Future<CrmComercialCustomerListResponse> listCustomers({
    String? q,
    String? status,
    bool onlyMine = false,
    int page = 1,
    int pageSize = 30,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomers,
      options: _silentRequestOptions,
      queryParameters: {
        if ((q ?? '').trim().isNotEmpty) 'q': q!.trim(),
        if ((status ?? '').trim().isNotEmpty) 'status': status,
        'onlyMine': onlyMine,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return CrmComercialCustomerListResponse.fromJson(res.data ?? const {});
  }

  Future<CrmComercialCustomer> getCustomer(String id) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerById(id),
      options: _silentRequestOptions,
    );
    return CrmComercialCustomer.fromJson(res.data ?? const {});
  }

  Future<CrmComercialCustomer> updateCustomer(
    String id, {
    String? responsableUserId,
    String? nextAction,
    DateTime? nextActionAt,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerById(id),
      data: {
        if (responsableUserId != null) 'responsableUserId': responsableUserId,
        if (nextAction != null) 'nextAction': nextAction,
        if (nextActionAt != null)
          'nextActionAt': nextActionAt.toIso8601String(),
      },
    );
    return CrmComercialCustomer.fromJson(res.data ?? const {});
  }

  Future<CrmComercialCustomer> changeStatus(
    String id,
    String status, {
    String? note,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerStatus(id),
      data: {
        'status': status,
        if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
      },
    );
    return CrmComercialCustomer.fromJson(res.data ?? const {});
  }

  Future<CrmComercialNote> addNote(String id, String note) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerNotes(id),
      data: {'note': note.trim()},
    );
    return CrmComercialNote.fromJson(res.data ?? const {});
  }

  Future<CrmComercialActivity> addActivity(
    String id, {
    required String type,
    required String description,
    String? assignedToUserId,
    DateTime? dueAt,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerActivities(id),
      data: {
        'type': type.trim(),
        'description': description.trim(),
        if ((assignedToUserId ?? '').trim().isNotEmpty)
          'assignedToUserId': assignedToUserId,
        if (dueAt != null) 'dueAt': dueAt.toIso8601String(),
      },
    );
    return CrmComercialActivity.fromJson(res.data ?? const {});
  }

  Future<List<CrmComercialUserRef>> listUsers() async {
    final res = await _dio.get<List<dynamic>>(
      ApiRoutes.users,
      options: _silentRequestOptions,
    );
    final rows = (res.data ?? const [])
        .whereType<Map>()
        .map(
          (entry) =>
              CrmComercialUserRef.fromJson(entry.cast<String, dynamic>()),
        )
        .toList(growable: false);
    return rows;
  }

  Future<CrmCommercialLibraryListResponse> listLibrary({
    String? type,
    String? category,
    String? search,
    bool? isActive,
    int? limit,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialLibrary,
      queryParameters: {
        if ((type ?? '').trim().isNotEmpty) 'type': type,
        if ((category ?? '').trim().isNotEmpty) 'category': category,
        if ((search ?? '').trim().isNotEmpty) 'search': search,
        if (isActive != null) 'isActive': isActive,
        if (limit != null) 'limit': limit,
      },
    );
    return CrmCommercialLibraryListResponse.fromJson(res.data ?? const {});
  }

  Future<CrmComercialLibraryItem> createLibraryItem(
    Map<String, dynamic> payload,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialLibrary,
      data: payload,
    );
    return CrmComercialLibraryItem.fromJson(res.data ?? const {});
  }

  Future<CrmComercialLibraryItem> updateLibraryItem(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialLibraryItem(id),
      data: payload,
    );
    return CrmComercialLibraryItem.fromJson(res.data ?? const {});
  }

  Future<CrmComercialLibraryItem> deleteLibraryItem(String id) async {
    final res = await _dio.delete<Map<String, dynamic>>(
      ApiRoutes.crmCommercialLibraryItem(id),
    );
    return CrmComercialLibraryItem.fromJson(res.data ?? const {});
  }

  Future<CrmComercialLibraryItem> useLibraryItem(String id) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialLibraryUse(id),
    );
    return CrmComercialLibraryItem.fromJson(res.data ?? const {});
  }

  Future<CrmComercialSettings> getSettings() async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialSettings,
      options: _silentRequestOptions,
    );
    return CrmComercialSettings.fromJson(res.data ?? const {});
  }

  Future<CrmComercialSettings> updateSettings({
    bool? enabled,
    String? selectedWhatsappInstanceId,
    String? selectedWhatsappInstanceName,
  }) async {
    final payload = <String, dynamic>{
      if (enabled != null) 'enabled': enabled,
      if (selectedWhatsappInstanceId != null)
        'selectedWhatsappInstanceId': selectedWhatsappInstanceId,
      if (selectedWhatsappInstanceName != null)
        'selectedWhatsappInstanceName': selectedWhatsappInstanceName,
    };
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialSettings,
      data: payload,
    );
    final data = res.data ?? const {};
    final nested = data['settings'];
    if (nested is Map<String, dynamic>) {
      return CrmComercialSettings.fromJson(nested);
    }
    return CrmComercialSettings.fromJson(data);
  }

  Future<List<CrmComercialWhatsappInstance>>
  listAvailableWhatsappInstances() async {
    final res = await _dio.get<List<dynamic>>(
      ApiRoutes.crmCommercialAvailableWhatsappInstances,
      options: _silentRequestOptions,
    );
    return (res.data ?? const [])
        .whereType<Map>()
        .map(
          (entry) => CrmComercialWhatsappInstance.fromJson(
            entry.cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  Future<CrmComercialInboxConversationListResponse> listConversations({
    int limit = 100,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialConversations,
      options: _silentRequestOptions,
      queryParameters: {'limit': limit},
    );
    return CrmComercialInboxConversationListResponse.fromJson(
      res.data ?? const {},
    );
  }

  Future<CrmComercialInboxMessageListResponse> getConversationMessages(
    String conversationId, {
    int limit = 200,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialConversationMessages(conversationId),
      options: _silentRequestOptions,
      queryParameters: {'limit': limit},
    );
    return CrmComercialInboxMessageListResponse.fromJson(res.data ?? const {});
  }

  Future<void> markConversationRead(String conversationId) async {
    final id = conversationId.trim();
    if (id.isEmpty) return;
    try {
      await _dio.post<Map<String, dynamic>>(
        ApiRoutes.crmCommercialConversationRead(id),
        options: _silentRequestOptions,
      );
    } catch (_) {
      // Silencioso: el UI ya hace override local a unreadCount=0.
    }
  }

  /// Downloads media bytes using the authenticated backend proxy.
  /// For WhatsappMessage media, the endpoint is /whatsapp-inbox/media/:messageId.
  /// The [mediaUrl] may be a full internal path like /whatsapp-inbox/media/UUID
  /// or a relative path — it is forwarded as-is through the Dio client (which
  /// already carries the JWT auth header).
  Future<Uint8List> downloadMediaBytes(String mediaUrl) async {
    try {
      final res = await _dio.get<dynamic>(
        mediaUrl,
        options: Options(
          responseType: ResponseType.bytes,
          extra: const {'skipLoader': true, 'silent': true},
        ),
      );
      final data = res.data;
      if (data is Uint8List) return data;
      if (data is List<int>) return Uint8List.fromList(data);
      if (data is ByteBuffer) return data.asUint8List();
      return Uint8List(0);
    } catch (_) {
      return Uint8List(0);
    }
  }

  Future<Map<String, dynamic>> startConversationMessage({
    required String phone,
    required String text,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialStartConversationMessage,
      data: {'phone': phone.trim(), 'text': text.trim()},
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> replyConversation({
    required String conversationId,
    required String text,
  }) async {
    final payload = <String, dynamic>{'text': text.trim()};
    final url = ApiRoutes.crmCommercialConversationReply(conversationId);

    try {
      if (kDebugMode) {
        debugPrint('[CRM][replyConversation] POST $url body=$payload');
      }
      final res = await _dio.post<Map<String, dynamic>>(url, data: payload);
      if (kDebugMode) {
        debugPrint(
          '[CRM][replyConversation] OK status=${res.statusCode} response=${res.data}',
        );
      }
      return res.data ?? const <String, dynamic>{};
    } on DioException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[CRM][replyConversation] ERROR url=${error.requestOptions.uri} '
          'status=${error.response?.statusCode} '
          'body=${error.requestOptions.data} '
          'response=${error.response?.data}',
        );
      }
      throw _mapError(error, 'No se pudo enviar el mensaje.');
    }
  }

  Future<String?> suggestOrthography({
    required String text,
    String? previousText,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    try {
      final payload = <String, dynamic>{
        'text': text,
        if ((previousText ?? '').trim().isNotEmpty)
          'previousText': previousText,
      };
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.crmCommercialOrthographySuggestion,
        data: payload,
        options: Options(extra: const {'skipLoader': true, 'silent': true}),
      );
      final data = res.data ?? const <String, dynamic>{};
      final changed = data['changed'] == true;
      if (!changed) return null;
      final suggestion = data['suggestion']?.toString().trim() ?? '';
      if (suggestion.isEmpty || suggestion == trimmed) return null;
      return suggestion;
    } on DioException {
      return null;
    }
  }

  Future<CrmComercialAiReplySuggestion?> suggestReply({
    required String conversationId,
    required String lastCustomerMessage,
    required List<CrmComercialInboxMessage> recentMessages,
    String? crmStatus,
    Map<String, dynamic>? customerInfo,
    Map<String, dynamic>? availableBusinessData,
  }) async {
    final text = lastCustomerMessage.trim();
    if (conversationId.trim().isEmpty || text.isEmpty) return null;
    try {
      final payload = <String, dynamic>{
        'conversationId': conversationId,
        'lastCustomerMessage': text,
        'recentMessages': recentMessages
            .map(
              (msg) => {
                'direction': msg.direction,
                'text': (msg.body ?? msg.caption ?? '').trim(),
              },
            )
            .where(
              (entry) => (entry['text'] ?? '').toString().trim().isNotEmpty,
            )
            .toList(growable: false),
        if ((crmStatus ?? '').trim().isNotEmpty) 'crmStatus': crmStatus,
        if (customerInfo != null) 'customerInfo': customerInfo,
        if (availableBusinessData != null)
          'availableBusinessData': availableBusinessData,
      };
      final res = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.crmCommercialAiSuggestReply,
        data: payload,
        options: Options(extra: const {'skipLoader': true, 'silent': true}),
      );
      final data = res.data ?? const <String, dynamic>{};
      final suggestion = CrmComercialAiReplySuggestion.fromJson(data);
      final hasPayload =
          suggestion.intent.trim().isNotEmpty ||
          suggestion.suggestedReply.trim().isNotEmpty ||
          suggestion.message?.trim().isNotEmpty == true ||
          suggestion.aiConfigured == false;
      if (!hasPayload) return null;
      return suggestion;
    } on DioException catch (error) {
      throw _mapError(error, 'No se pudo generar sugerencia de IA.');
    }
  }

  Future<Map<String, dynamic>> replyConversationMedia({
    required String conversationId,
    required String mediaType, // 'image', 'video', 'audio', 'document'
    required String mimeType,
    required String fileName,
    required String base64Data,
    String? caption,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialConversationReplyMedia(conversationId),
      data: {
        'mediaType': mediaType,
        'mimeType': mimeType,
        'fileName': fileName,
        'base64Data': base64Data,
        if ((caption ?? '').trim().isNotEmpty) 'caption': caption!.trim(),
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> deleteConversationMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final res = await _dio.delete<Map<String, dynamic>>(
      ApiRoutes.crmCommercialConversationMessageDelete(
        conversationId,
        messageId,
      ),
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> startConversationMediaMessage({
    required String phone,
    required String mediaType, // 'image', 'video', 'audio', 'document'
    required String mimeType,
    required String fileName,
    required String base64Data,
    String? caption,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialStartConversationMedia,
      data: {
        'phone': phone.trim(),
        'mediaType': mediaType,
        'mimeType': mimeType,
        'fileName': fileName,
        'base64Data': base64Data,
        if ((caption ?? '').trim().isNotEmpty) 'caption': caption!.trim(),
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  // Phase 2: Follow-up Tasks

  Future<List<CrmComercialFollowupTask>> listFollowupTasks({
    String? customerId,
    bool overdueOnly = false,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      ApiRoutes.crmCommercialFollowupTasks,
      options: _silentRequestOptions,
      queryParameters: {
        if ((customerId ?? '').isNotEmpty) 'customerId': customerId,
        if (overdueOnly) 'overdueOnly': 'true',
      },
    );
    return (res.data ?? const [])
        .whereType<Map>()
        .map(
          (e) => CrmComercialFollowupTask.fromJson(e.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  Future<CrmComercialFollowupTask> createFollowupTask(
    String customerId, {
    required String title,
    String? description,
    DateTime? dueDate,
    String priority = 'NORMAL',
    String? assignedUserId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialCustomerFollowupTasks(customerId),
      data: {
        'title': title.trim(),
        if ((description ?? '').trim().isNotEmpty)
          'description': description!.trim(),
        if (dueDate != null) 'dueDate': dueDate.toIso8601String(),
        'priority': priority,
        if ((assignedUserId ?? '').isNotEmpty) 'assignedUserId': assignedUserId,
      },
    );
    return CrmComercialFollowupTask.fromJson(res.data ?? const {});
  }

  Future<CrmComercialFollowupTask> completeFollowupTask(String taskId) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialFollowupTaskComplete(taskId),
    );
    return CrmComercialFollowupTask.fromJson(res.data ?? const {});
  }

  Future<CrmComercialFollowupTask> cancelFollowupTask(String taskId) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialFollowupTaskCancel(taskId),
    );
    return CrmComercialFollowupTask.fromJson(res.data ?? const {});
  }

  // ==================== CACHE METHODS ====================

  /// Carga datos desde caché local para mostrar al instante.
  /// Devuelve null si no hay datos en caché.
  Future<CrmComercialCacheData?> getCachedData() async {
    try {
      final conversations = await _localDb.getConversations();
      final customers = await _localDb.getCustomers();
      final tasks = await _localDb.getFollowupTasks();
      final settings = await _localDb.getSettings();
      final instances = await _localDb.getWhatsappInstances();
      final users = await _localDb.getUsers();

      return CrmComercialCacheData(
        conversations: conversations,
        customers: customers,
        tasks: tasks,
        settings: settings,
        whatsappInstances: instances,
        users: users,
      );
    } catch (_) {
      return null;
    }
  }

  /// Guarda datos en caché local después de obtenerlos del servidor.
  Future<void> cacheData(CrmComercialCacheData data) async {
    await _localDb.saveConversations(data.conversations);
    await _localDb.saveCustomers(data.customers);
    await _localDb.saveFollowupTasks(data.tasks);
    if (data.settings != null) {
      await _localDb.saveSettings(data.settings!);
    }
    await _localDb.saveWhatsappInstances(data.whatsappInstances);
    await _localDb.saveUsers(data.users);
  }

  /// Guarda mensajes de una conversación en caché.
  Future<void> cacheMessages(
    String conversationId,
    List<CrmComercialInboxMessage> messages,
  ) async {
    await _localDb.saveMessages(conversationId, messages);
  }

  /// Obtiene mensajes de una conversación desde el caché.
  Future<List<CrmComercialInboxMessage>> getCachedMessages(
    String conversationId,
  ) async {
    return _localDb.getMessages(conversationId);
  }

  /// Agrega un mensaje enviado al caché local (optimistic UI).
  Future<void> addMessageToCache(
    String conversationId,
    CrmComercialInboxMessage message,
  ) async {
    await _localDb.saveMessage(conversationId, message);
  }

  /// Limpia todo el caché local.
  Future<void> clearCache() async {
    await _localDb.clearCache();
  }

  // ──── Bot AI methods ──────────────────────────────────────────────────────

  /// Obtiene la configuración global del bot.
  Future<Map<String, dynamic>> getBotSettings() async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotSettings,
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Actualiza la configuración global del bot.
  Future<Map<String, dynamic>> updateBotSettings(
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotSettings,
      data: data,
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Obtiene el estado del bot para una conversación específica.
  Future<Map<String, dynamic>> getConversationBotStatus(
    String conversationId,
  ) async {
    final res = await _dio.get<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotConversationStatus(conversationId),
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Pausa el bot para una conversación.
  Future<Map<String, dynamic>> pauseBotForConversation(
    String conversationId, {
    String? reason,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotConversationPause(conversationId),
      data: reason != null ? {'reason': reason} : {},
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Reanuda el bot para una conversación.
  Future<Map<String, dynamic>> resumeBotForConversation(
    String conversationId,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotConversationResume(conversationId),
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Excluye un número del bot.
  Future<Map<String, dynamic>> excludeNumberFromBot(
    String conversationId,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotConversationExclude(conversationId),
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Incluye un número en el bot (quita exclusión).
  Future<Map<String, dynamic>> includeNumberInBot(String conversationId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotConversationInclude(conversationId),
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Solicita una sugerencia de respuesta del bot para una conversación.
  Future<Map<String, dynamic>> suggestBotReply(
    String conversationId, {
    String? lastCustomerMessage,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotConversationSuggest(conversationId),
      data: lastCustomerMessage != null
          ? {'lastCustomerMessage': lastCustomerMessage}
          : {},
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }

  /// Envía una respuesta generada por el bot a una conversación.
  Future<Map<String, dynamic>> sendBotReply(
    String conversationId, {
    String? lastCustomerMessage,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      ApiRoutes.crmCommercialBotConversationSend(conversationId),
      data: lastCustomerMessage != null
          ? {'lastCustomerMessage': lastCustomerMessage}
          : {},
      options: _silentRequestOptions,
    );
    return res.data ?? {};
  }
}

/// Datos cacheados del CRM Comercial.
class CrmComercialCacheData {
  final List<CrmComercialInboxConversation> conversations;
  final List<CrmComercialCustomer> customers;
  final List<CrmComercialFollowupTask> tasks;
  final CrmComercialSettings? settings;
  final List<CrmComercialWhatsappInstance> whatsappInstances;
  final List<CrmComercialUserRef> users;

  CrmComercialCacheData({
    required this.conversations,
    required this.customers,
    required this.tasks,
    this.settings,
    required this.whatsappInstances,
    required this.users,
  });
}
