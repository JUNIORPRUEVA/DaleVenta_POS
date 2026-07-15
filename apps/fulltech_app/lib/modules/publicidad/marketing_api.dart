import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error_mapper.dart';
import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import 'marketing_campaign_models.dart';
import 'marketing_models.dart';
import 'marketing_social_accounts_models.dart';

final marketingApiProvider = Provider<MarketingApi>((ref) {
  return MarketingApi(ref.watch(dioProvider));
});

class MarketingApi {
  MarketingApi(this._dio);

  final Dio _dio;
  static final _backgroundOptions = Options(extra: {'skipLoader': true});
  static final _publishOptions = Options(
    // Meta publishing may take longer than the default API timeout.
    connectTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 3),
  );

  Never _rethrow(DioException error, String fallback) {
    throw ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  String _dateOnly(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<MarketingDashboard> loadDashboard(DateTime date) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingDashboard,
        queryParameters: {'date': _dateOnly(date)},
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingDashboard.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar el dashboard de Publicidad');
    }
  }

  Future<MarketingFlowConfig> loadConfig() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingConfig,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingFlowConfig.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la configuracion de Publicidad');
    }
  }

  Future<List<MarketingStory>> loadStories(DateTime date) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingStories,
        queryParameters: {'date': _dateOnly(date)},
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map((item) => MarketingStory.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron cargar los estados diarios');
    }
  }

  Future<MarketingHistoryResponse> loadHistory({
    required DateTime from,
    required DateTime to,
    int page = 1,
    int limit = 20,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit < 1 ? 1 : (limit > 100 ? 100 : limit);

    try {
      final res = await _dio.get(
        ApiRoutes.marketingHistory,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          'page': safePage,
          'limit': safeLimit,
        },
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingHistoryResponse.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar el historial');
    }
  }

  Future<void> generateMissing(
    DateTime date, {
    List<String> selectedMediaAssetIds = const [],
  }) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoriesGenerateMissing,
        data: {
          'date': _dateOnly(date),
          if (selectedMediaAssetIds.isNotEmpty)
            'selected_media_asset_ids': selectedMediaAssetIds,
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron generar los contenidos faltantes');
    }
  }

  Future<MarketingRepairIncompleteSummary> repairIncomplete(
    DateTime date,
  ) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingStoriesRepairIncomplete,
        data: {'date': _dateOnly(date)},
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingRepairIncompleteSummary.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron reparar los anuncios incompletos');
    }
  }

  Future<void> approve(
    String storyId, {
    String contentType = 'post',
    List<MarketingPublishTarget> publishTargets = const [],
  }) async {
    try {
      final targetValues = publishTargets
          .map(publishTargetApiValue)
          .toList(growable: false);
      final targetSet = targetValues.toSet();
      await _dio.post(
        ApiRoutes.marketingStoryApprove(storyId),
        data: {
          'contentType': contentType,
          'publishTargets': targetValues,
          'publishFacebookStory': targetSet.contains('facebook_story'),
          'publishInstagramStory': targetSet.contains('instagram_story'),
          'publishFacebookPost': targetSet.contains('facebook_post'),
          'publishInstagramPost': targetSet.contains('instagram_post'),
        },
        options: _publishOptions,
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo aprobar el contenido');
    }
  }

  Future<void> retryPublish(String storyId) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoryRetryPublish(storyId),
        options: _publishOptions,
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo reintentar la publicación');
    }
  }

  Future<void> reject(String storyId, {String reason = ''}) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoryReject(storyId),
        data: {'reason': reason.trim()},
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo rechazar el contenido');
    }
  }

  Future<void> regenerate(String storyId) async {
    try {
      await _dio.post(ApiRoutes.marketingStoryRegenerate(storyId));
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo regenerar el contenido');
    }
  }

  Future<void> regenerateCopyFromDesignImage(String storyId) async {
    try {
      await _dio.post(
        '${ApiRoutes.marketingStories}/$storyId/regenerate-copy-from-design',
      );
    } on DioException catch (error) {
      _rethrow(
        error,
        'No se pudo regenerar el copy desde el diseño (imagen o video)',
      );
    }
  }

  Future<void> regenerateImage(String storyId, {String? customPrompt}) async {
    try {
      await _dio.post(
        ApiRoutes.marketingStoryRegenerateImage(storyId),
        data: {
          if ((customPrompt ?? '').trim().isNotEmpty)
            'reason': customPrompt!.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo regenerar la imagen');
    }
  }

  Future<void> changeBaseImage(String storyId, String mediaAssetId) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingStoryChangeBaseImage(storyId, mediaAssetId),
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cambiar la imagen base');
    }
  }

  Future<void> confirmBaseImage(String storyId) async {
    try {
      await _dio.post(
        '${ApiRoutes.marketingStories}/$storyId/confirm-base-image',
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo confirmar la imagen base');
    }
  }

  Future<void> generateDesign(String storyId, {String? customPrompt}) async {
    try {
      await _dio.post(
        '${ApiRoutes.marketingStories}/$storyId/generate-design',
        data: {
          if ((customPrompt ?? '').trim().isNotEmpty)
            'reason': customPrompt!.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo generar el diseño');
    }
  }

  Future<void> regenerateDesign(String storyId, {String? customPrompt}) async {
    try {
      await _dio.post(
        '${ApiRoutes.marketingStories}/$storyId/regenerate-design',
        data: {
          if ((customPrompt ?? '').trim().isNotEmpty)
            'reason': customPrompt!.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo regenerar el diseño');
    }
  }

  Future<void> editStory(
    String storyId, {
    required String title,
    required String shortText,
    required String longText,
    required List<String> hashtags,
    required String imagePrompt,
    required String imageUrl,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingStoryEdit(storyId),
        data: {
          'title': title.trim(),
          'shortText': shortText.trim(),
          'longText': longText.trim(),
          'hashtags': hashtags,
          'imagePrompt': imagePrompt.trim(),
          'imageUrl': imageUrl.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo editar el contenido');
    }
  }

  Future<void> updateConfig({
    required bool flujoActivo,
    required bool pausado,
    required int cantidadEstadosDiarios,
    required String horaGeneracion,
    required bool autoRegenerarSiNoAprueba,
    required int horasParaRegenerar,
    required List<String> productosPrioritarios,
    required String ciudadObjetivo,
    required String tonoDeMarca,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingConfig,
        data: {
          'flujo_activo': flujoActivo,
          'pausado': pausado,
          'cantidad_estados_diarios': cantidadEstadosDiarios,
          'hora_generacion': horaGeneracion.trim(),
          'auto_regenerar_si_no_aprueba': autoRegenerarSiNoAprueba,
          'horas_para_regenerar': horasParaRegenerar,
          'productos_prioritarios': productosPrioritarios,
          'ciudad_objetivo': ciudadObjetivo.trim(),
          'tono_de_marca': tonoDeMarca.trim(),
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo guardar la configuracion');
    }
  }

  Future<void> activateFlow() async {
    try {
      await _dio.post(ApiRoutes.marketingFlowActivate);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo activar el flujo');
    }
  }

  Future<void> pauseFlow() async {
    try {
      await _dio.post(ApiRoutes.marketingFlowPause);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo pausar el flujo');
    }
  }

  Future<void> resetFlow() async {
    try {
      await _dio.post(ApiRoutes.marketingFlowReset);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo reiniciar el flujo');
    }
  }

  Future<MarketingResetCleanSummary> resetClean({
    bool includeResearch = false,
    bool includeDraftMedia = true,
    bool includeGeneratedImages = true,
    bool includeApprovedStories = false,
    DateTime? date,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingResetClean,
        data: {
          'includeResearch': includeResearch,
          'includeDraftMedia': includeDraftMedia,
          'includeGeneratedImages': includeGeneratedImages,
          'includeApprovedStories': includeApprovedStories,
          if (date != null) 'date': _dateOnly(date),
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingResetCleanSummary.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo ejecutar el reset limpio de Publicidad');
    }
  }

  Future<List<MarketingMediaAsset>> loadMediaAssets({
    String? category,
    String? relatedService,
    bool activeOnly = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingMediaAssets,
        options: _backgroundOptions,
        queryParameters: {
          if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
          if ((relatedService ?? '').trim().isNotEmpty)
            'related_service': relatedService!.trim(),
          if (activeOnly) 'active_only': true,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) =>
                MarketingMediaAsset.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la galería publicitaria');
    }
  }

  Future<List<MarketingMediaAsset>> loadContentGallery() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingContentGallery,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) =>
                MarketingMediaAsset.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(
        error,
        'No se pudo cargar la Galería de contenido autorizada de Publicidad',
      );
    }
  }

  /// Analyzes multiple media assets and returns AI recommendations ranked by suitability
  Future<Map<String, dynamic>> analyzeMediaAssets({
    required List<String> mediaAssetIds,
    required String storyType,
  }) async {
    try {
      final res = await _dio.post(
        '${ApiRoutes.marketingMediaAssets}/analyze',
        data: {'mediaAssetIds': mediaAssetIds, 'storyType': storyType},
        options: _backgroundOptions,
      );
      return (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron analizar las imágenes disponibles');
    }
  }

  Future<MarketingMediaAsset> createMediaAsset({
    required String fileUrl,
    required String fileName,
    required String mimeType,
    required String category,
    String? relatedService,
    List<String> tags = const [],
    String? description,
    bool isActive = true,
    bool isFeatured = false,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingMediaAssets,
        data: {
          'file_url': fileUrl.trim(),
          'file_name': fileName.trim(),
          'mime_type': mimeType.trim(),
          'category': category.trim(),
          'related_service': relatedService?.trim(),
          'tags': tags,
          'description': description?.trim(),
          'is_active': isActive,
          'is_featured': isFeatured,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if ('${raw['id'] ?? ''}'.trim().isNotEmpty) {
        return MarketingMediaAsset.fromJson(raw);
      }
      throw StateError('Respuesta inválida al crear asset de galería');
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo crear el asset de galería');
    }
  }

  Future<void> updateMediaAsset(
    String id, {
    String? category,
    String? relatedService,
    List<String>? tags,
    String? description,
    bool? isActive,
    bool? isFeatured,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.marketingMediaAssetById(id),
        data: {
          if (category != null) 'category': category.trim(),
          if (relatedService != null) 'related_service': relatedService.trim(),
          if (tags != null) 'tags': tags,
          if (description != null) 'description': description.trim(),
          if (isActive != null) 'is_active': isActive,
          if (isFeatured != null) 'is_featured': isFeatured,
        },
      );
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo actualizar el asset');
    }
  }

  Future<void> deleteMediaAsset(String id) async {
    try {
      await _dio.delete(ApiRoutes.marketingMediaAssetById(id));
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo eliminar el asset');
    }
  }

  Future<MarketingResearchDetail?> loadLatestResearch() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingResearchLatest,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if ('${raw['id'] ?? ''}'.trim().isEmpty) return null;
      return MarketingResearchDetail.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la investigación más reciente');
    }
  }

  Future<List<MarketingResearchDetail>> loadResearchHistory() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingResearchList,
        options: _backgroundOptions,
      );
      final rows = (res.data is List) ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) =>
                MarketingResearchDetail.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar el historial de investigaciones');
    }
  }

  Future<void> forceResearchNow() async {
    try {
      await _dio.post(ApiRoutes.marketingResearchForce, data: const {});
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo generar la investigación manual');
    }
  }

  Future<MarketingLearningStats> loadLearningStats() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingResearchLearningStats,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingLearningStats.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar memorias/aprendizajes activos');
    }
  }

  Future<List<MarketingPublishedAsset>> loadPublishedAssets() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingPublishedAssets,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) =>
                MarketingPublishedAsset.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar imágenes publicadas');
    }
  }

  Future<List<MarketingSocialAccount>> loadSocialAccounts({
    MarketingSocialAccountType? type,
    String? search,
    bool activeOnly = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingSocialAccounts,
        options: _backgroundOptions,
        queryParameters: {
          if (type != null) 'type': marketingSocialAccountTypeApiValue(type),
          if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
          if (activeOnly) 'activeOnly': true,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (item) =>
                MarketingSocialAccount.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron cargar las cuentas empresariales');
    }
  }

  Future<MarketingSocialAccount> createSocialAccount({
    required MarketingSocialAccountType type,
    required String accountName,
    String? username,
    String? password,
    String? profileLink,
    String? whatsappNumber,
    String? observations,
    String? avatarUrl,
    bool isActive = true,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingSocialAccounts,
        data: {
          'type': marketingSocialAccountTypeApiValue(type),
          'accountName': accountName.trim(),
          if ((username ?? '').trim().isNotEmpty) 'username': username!.trim(),
          if ((password ?? '').trim().isNotEmpty) 'password': password!.trim(),
          if ((profileLink ?? '').trim().isNotEmpty)
            'profileLink': profileLink!.trim(),
          if ((whatsappNumber ?? '').trim().isNotEmpty)
            'whatsappNumber': whatsappNumber!.trim(),
          if ((observations ?? '').trim().isNotEmpty)
            'observations': observations!.trim(),
          if ((avatarUrl ?? '').trim().isNotEmpty)
            'avatarUrl': avatarUrl!.trim(),
          'isActive': isActive,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingSocialAccount.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo crear la cuenta empresarial');
    }
  }

  Future<MarketingSocialAccount> updateSocialAccount(
    String id, {
    MarketingSocialAccountType? type,
    String? accountName,
    String? username,
    String? password,
    String? profileLink,
    String? whatsappNumber,
    String? observations,
    String? avatarUrl,
    bool? isActive,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.marketingSocialAccountById(id),
        data: {
          if (type != null) 'type': marketingSocialAccountTypeApiValue(type),
          if (accountName != null) 'accountName': accountName.trim(),
          if (username != null) 'username': username.trim(),
          if (password != null) 'password': password.trim(),
          if (profileLink != null) 'profileLink': profileLink.trim(),
          if (whatsappNumber != null) 'whatsappNumber': whatsappNumber.trim(),
          if (observations != null) 'observations': observations.trim(),
          if (avatarUrl != null) 'avatarUrl': avatarUrl.trim(),
          if (isActive != null) 'isActive': isActive,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingSocialAccount.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo actualizar la cuenta empresarial');
    }
  }

  Future<void> deleteSocialAccount(String id) async {
    try {
      await _dio.delete(ApiRoutes.marketingSocialAccountById(id));
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo eliminar la cuenta empresarial');
    }
  }

  Future<(List<MarketingCampaign>, MetaAdsConfigDebug)> loadCampaigns({
    DateTime? date,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingCampaigns,
        queryParameters: {if (date != null) 'date': _dateOnly(date)},
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final rows = (raw['items'] is List) ? (raw['items'] as List) : const [];
      final items = rows
          .whereType<Map>()
          .map(
            (item) => MarketingCampaign.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false);
      final configRaw = (raw['config'] is Map)
          ? (raw['config'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      return (items, MetaAdsConfigDebug.fromJson(configRaw));
    } on DioException catch (error) {
      _rethrow(error, 'No se pudieron cargar las campañas publicitarias');
    }
  }

  Future<MarketingCampaign> generateCampaignDraft({DateTime? date}) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingCampaignsGenerateMissing,
        data: {if (date != null) 'date': _dateOnly(date)},
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo generar el borrador de campaña');
    }
  }

  Future<MarketingCampaign> confirmCampaignBaseImage(String id) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingCampaignConfirmBaseImage(id),
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo confirmar la imagen base de la campaña');
    }
  }

  Future<MarketingCampaign> changeCampaignBaseImage(
    String id,
    String mediaAssetId,
  ) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.marketingCampaignChangeBaseImage(id, mediaAssetId),
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cambiar la imagen base de la campaña');
    }
  }

  Future<MarketingCampaign> uploadCampaignDesign(
    String id, {
    required String finalDesignUrl,
    String? fileName,
    String? mimeType,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingCampaignUploadDesign(id),
        data: {
          'finalDesignUrl': finalDesignUrl,
          if ((fileName ?? '').trim().isNotEmpty) 'fileName': fileName,
          if ((mimeType ?? '').trim().isNotEmpty) 'mimeType': mimeType,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo subir el diseño final de campaña');
    }
  }

  Future<MarketingCampaign> regenerateCampaignCopy(String id) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingCampaignRegenerateCopy(id),
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo regenerar el copy y segmentación de campaña');
    }
  }

  Future<MarketingCampaign> updateCampaign(
    String id, {
    String? headline,
    String? primaryText,
    String? description,
    String? cta,
    List<String>? hashtags,
    String? aiAngle,
    Map<String, dynamic>? recommendedAudience,
    Map<String, dynamic>? finalAudience,
    double? dailyBudget,
    double? totalBudget,
    MarketingCampaignCurrency? currency,
    String? whatsappPhone,
    String? whatsappMessageTemplate,
    String? destinationUrl,
    DateTime? startTime,
    DateTime? endTime,
    bool? keepRunningUntilPaused,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.marketingCampaignUpdate(id),
        data: {
          if (headline != null) 'headline': headline,
          if (primaryText != null) 'primaryText': primaryText,
          if (description != null) 'description': description,
          if (cta != null) 'cta': cta,
          if (hashtags != null) 'hashtags': hashtags,
          if (aiAngle != null) 'aiAngle': aiAngle,
          if (recommendedAudience != null)
            'recommendedAudienceJson': recommendedAudience,
          if (finalAudience != null) 'finalAudienceJson': finalAudience,
          if (dailyBudget != null) 'dailyBudget': dailyBudget,
          if (totalBudget != null) 'totalBudget': totalBudget,
          if (currency != null)
            'currency': marketingCampaignCurrencyApi(currency),
          if (whatsappPhone != null) 'whatsappPhone': whatsappPhone,
          if (whatsappMessageTemplate != null)
            'whatsappMessageTemplate': whatsappMessageTemplate,
          if (destinationUrl != null) 'destinationUrl': destinationUrl,
          if (startTime != null) 'startTime': startTime.toIso8601String(),
          if (endTime != null) 'endTime': endTime.toIso8601String(),
          if (keepRunningUntilPaused != null)
            'keepRunningUntilPaused': keepRunningUntilPaused,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo actualizar la campaña');
    }
  }

  Future<MarketingCampaign> createMetaCampaign(
    String id, {
    String objective = 'OUTCOME_ENGAGEMENT',
    bool activateAfterCreate = false,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingCampaignCreateMeta(id),
        data: {
          'objective': objective,
          'activateAfterCreate': activateAfterCreate,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo crear la campaña en Meta Ads');
    }
  }

  Future<MarketingCampaign> activateCampaign(String id) async {
    try {
      final res = await _dio.post(ApiRoutes.marketingCampaignActivate(id));
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo activar la campaña');
    }
  }

  Future<MarketingCampaign> pauseCampaign(String id) async {
    try {
      final res = await _dio.post(ApiRoutes.marketingCampaignPause(id));
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo pausar la campaña');
    }
  }

  Future<MarketingCampaign> rejectCampaign(String id) async {
    try {
      final res = await _dio.post(ApiRoutes.marketingCampaignReject(id));
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo rechazar la campaña');
    }
  }

  Future<MarketingCampaign> duplicateCampaign(String id) async {
    try {
      final res = await _dio.post(ApiRoutes.marketingCampaignDuplicate(id));
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo duplicar la campaña');
    }
  }

  Future<MarketingCampaign> loadCampaignDetails(String id) async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingCampaignDetails(id),
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MarketingCampaign.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar el detalle de la campaña');
    }
  }

  Future<MetaAdsConfigDebug> loadMetaAdsConfigDebug() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingDebugMetaAdsConfig,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MetaAdsConfigDebug.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo validar la configuración de Meta Ads');
    }
  }

  Future<MetaRuntimeConfigDebug> loadMetaRuntimeConfig() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingDebugMetaRuntimeConfig,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MetaRuntimeConfigDebug.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo cargar la configuración de tokens Meta');
    }
  }

  Future<MetaRuntimeConfigDebug> updateMetaRuntimeConfig({
    String? graphVersion,
    String? appId,
    String? appSecret,
    String? adAccountId,
    String? campaignMode,
    String? pageId,
    String? instagramBusinessId,
    String? whatsappPhoneNumberId,
    String? whatsappBusinessAccountId,
    String? businessId,
    String? adsAccessToken,
    String? userAccessToken,
    String? organicPageAccessToken,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.marketingDebugMetaRuntimeConfig,
        data: {
          if (graphVersion != null) 'graphVersion': graphVersion,
          if (appId != null) 'appId': appId,
          if (appSecret != null) 'appSecret': appSecret,
          if (adAccountId != null) 'adAccountId': adAccountId,
          if (campaignMode != null) 'campaignMode': campaignMode,
          if (pageId != null) 'pageId': pageId,
          if (instagramBusinessId != null)
            'instagramBusinessId': instagramBusinessId,
          if (whatsappPhoneNumberId != null)
            'whatsappPhoneNumberId': whatsappPhoneNumberId,
          if (whatsappBusinessAccountId != null)
            'whatsappBusinessAccountId': whatsappBusinessAccountId,
          if (businessId != null) 'businessId': businessId,
          if (adsAccessToken != null) 'adsAccessToken': adsAccessToken,
          if (userAccessToken != null) 'userAccessToken': userAccessToken,
          if (organicPageAccessToken != null)
            'organicPageAccessToken': organicPageAccessToken,
        },
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MetaRuntimeConfigDebug.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo guardar la configuración de tokens Meta');
    }
  }

  Future<MetaAdsPermissionsDebug> loadMetaAdsPermissionsDebug() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingDebugMetaAdsPermissions,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MetaAdsPermissionsDebug.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo validar permisos de Meta Ads');
    }
  }

  Future<MetaWhatsappDebug> loadMetaWhatsappDebug() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingDebugMetaWhatsapp,
        options: _backgroundOptions,
      );
      final raw =
          (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      return MetaWhatsappDebug.fromJson(raw);
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo validar WhatsApp en Meta Ads');
    }
  }

  Future<Map<String, dynamic>> loadMetaN8nCompatibilityDebug() async {
    try {
      final res = await _dio.get(
        ApiRoutes.marketingDebugMetaN8nCompatibility,
        options: _backgroundOptions,
      );
      return (res.data as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
    } on DioException catch (error) {
      _rethrow(error, 'No se pudo probar la lógica n8n de Meta Ads');
    }
  }
}
