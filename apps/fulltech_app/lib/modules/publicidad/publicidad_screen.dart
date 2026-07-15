// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/product_model.dart';
import '../../core/api/env.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../features/catalogo/data/catalog_repository.dart';
import '../service_orders/data/upload_repository.dart';
import 'marketing_api.dart';
import 'marketing_models.dart';

enum _PublicidadTab {
  dashboard,
  investigacion,
  galeria,
  estados,
  historial,
  configuracion,
}

enum _EstadosPhase { crearDiseno, copys, aprobarPublicar }

enum _EstadosViewMode { normal, rapido, video }

class MarketingMediaAssetDraft {
  const MarketingMediaAssetDraft({
    required this.fileUrl,
    required this.fileName,
    required this.category,
    this.relatedService = '',
    this.description = '',
    this.tags = const [],
  });

  final String fileUrl;
  final String fileName;
  final String category;
  final String relatedService;
  final String description;
  final List<String> tags;
}

class PublicidadState {
  const PublicidadState({
    required this.loading,
    required this.busy,
    required this.date,
    required this.dashboard,
    required this.config,
    required this.dailyStories,
    required this.mediaAssets,
    required this.contentGalleryAssets,
    required this.history,
    required this.latestResearch,
    required this.researchHistory,
    required this.learningStats,
    required this.publishedAssets,
    required this.imageBusyStoryIds,
    required this.error,
  });

  final bool loading;
  final bool busy;
  final DateTime date;
  final MarketingDashboard? dashboard;
  final MarketingFlowConfig? config;
  final List<MarketingStory> dailyStories;
  final List<MarketingMediaAsset> mediaAssets;
  final List<MarketingMediaAsset> contentGalleryAssets;
  final List<MarketingStory> history;
  final MarketingResearchDetail? latestResearch;
  final List<MarketingResearchDetail> researchHistory;
  final MarketingLearningStats? learningStats;
  final List<MarketingPublishedAsset> publishedAssets;
  final Set<String> imageBusyStoryIds;
  final String? error;

  factory PublicidadState.initial() {
    final now = DateTime.now();
    return PublicidadState(
      loading: true,
      busy: false,
      date: DateTime(now.year, now.month, now.day),
      dashboard: null,
      config: null,
      dailyStories: const [],
      mediaAssets: const [],
      contentGalleryAssets: const [],
      history: const [],
      latestResearch: null,
      researchHistory: const [],
      learningStats: null,
      publishedAssets: const [],
      imageBusyStoryIds: const <String>{},
      error: null,
    );
  }

  PublicidadState copyWith({
    bool? loading,
    bool? busy,
    DateTime? date,
    MarketingDashboard? dashboard,
    MarketingFlowConfig? config,
    List<MarketingStory>? dailyStories,
    List<MarketingMediaAsset>? mediaAssets,
    List<MarketingMediaAsset>? contentGalleryAssets,
    List<MarketingStory>? history,
    MarketingResearchDetail? latestResearch,
    List<MarketingResearchDetail>? researchHistory,
    MarketingLearningStats? learningStats,
    List<MarketingPublishedAsset>? publishedAssets,
    Set<String>? imageBusyStoryIds,
    String? error,
    bool clearError = false,
  }) {
    return PublicidadState(
      loading: loading ?? this.loading,
      busy: busy ?? this.busy,
      date: date ?? this.date,
      dashboard: dashboard ?? this.dashboard,
      config: config ?? this.config,
      dailyStories: dailyStories ?? this.dailyStories,
      mediaAssets: mediaAssets ?? this.mediaAssets,
      contentGalleryAssets: contentGalleryAssets ?? this.contentGalleryAssets,
      history: history ?? this.history,
      latestResearch: latestResearch ?? this.latestResearch,
      researchHistory: researchHistory ?? this.researchHistory,
      learningStats: learningStats ?? this.learningStats,
      publishedAssets: publishedAssets ?? this.publishedAssets,
      imageBusyStoryIds: imageBusyStoryIds ?? this.imageBusyStoryIds,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final publicidadControllerProvider =
    StateNotifierProvider<PublicidadController, PublicidadState>((ref) {
      return PublicidadController(ref.read(marketingApiProvider));
    });

class PublicidadController extends StateNotifier<PublicidadState> {
  PublicidadController(this._api) : super(PublicidadState.initial()) {
    loadInitial();
  }

  final MarketingApi _api;
  static const Duration _imagePollInterval = Duration(seconds: 5);
  static const Duration _imagePollTimeout = Duration(minutes: 5);
  Future<void>? _imagePollingTask;
  DateTime? _imagePollingDeadline;
  final Set<String> _pollingStoryIds = <String>{};
  final Set<String> _autoSelectionAttemptedStoryIds = <String>{};
  bool _autoSelectingBaseImages = false;
  bool _disposed = false;

  Future<void> loadInitial() async {
    await _refresh(keepLoading: true);
  }

  Future<void> refresh() async {
    await _refresh(keepLoading: false);
  }

  Future<void> changeDate(DateTime value) async {
    state = state.copyWith(date: DateTime(value.year, value.month, value.day));
    await _refresh(keepLoading: false);
  }

  Future<void> generateNow({
    List<String> selectedMediaAssetIds = const [],
  }) async {
    await _runBusy(() async {
      await _api.generateMissing(
        state.date,
        selectedMediaAssetIds: selectedMediaAssetIds,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> forceResearchNow() async {
    await _runBusy(() async {
      await _api.forceResearchNow();
      await _refresh(keepLoading: false);
    });
  }

  Future<MarketingRepairIncompleteSummary> repairIncompleteNow() async {
    return _runBusyValue(() async {
      final summary = await _api.repairIncomplete(state.date);
      await _refresh(keepLoading: false);
      return summary;
    });
  }

  Future<void> approve(
    String storyId,
    List<MarketingPublishTarget> publishTargets,
  ) async {
    await _runBusyValue(() async {
      final legacyContentType =
          publishTargets.length == 1 &&
              publishTargets.contains(MarketingPublishTarget.instagramStory)
          ? 'story'
          : 'post';
      try {
        await _api.approve(
          storyId,
          contentType: legacyContentType,
          publishTargets: publishTargets,
        );
      } on ApiException catch (error) {
        final normalized = error.message.trim().toLowerCase();
        final isAlreadyPublished =
            error.code == 409 &&
            (normalized.contains('ya está publicado') ||
                normalized.contains('ya esta publicado') ||
                normalized.contains('already published'));
        if (!isAlreadyPublished) {
          rethrow;
        }
      }
      await _refresh(keepLoading: false);

      MarketingStory? refreshedStory;
      for (final item in state.dailyStories) {
        if (item.id == storyId) {
          refreshedStory = item;
          break;
        }
      }

      if (refreshedStory == null) {
        throw ApiException(
          'No se pudo verificar el estado final de la publicación. Recarga e intenta nuevamente.',
        );
      }

      final publishError = (refreshedStory.publishError ?? '').trim();
      final defaultError = publishError.isNotEmpty
          ? publishError
          : 'Meta no confirmó la publicación en los canales seleccionados.';

      switch (refreshedStory.publishStatus) {
        case MarketingPublishStatus.published:
          return;
        case MarketingPublishStatus.partial:
          throw ApiException(
            publishError.isNotEmpty
                ? 'Publicación parcial: $publishError'
                : 'Publicación parcial: algunos canales no se publicaron. Revisa historial y reintenta.',
          );
        case MarketingPublishStatus.error:
          throw ApiException(defaultError);
        case MarketingPublishStatus.publishing:
          throw ApiException(
            'La solicitud fue aceptada pero sigue en proceso. Revisa historial y usa Reintentar publicación si no aparece en Meta.',
          );
        case MarketingPublishStatus.pending:
          throw ApiException(
            'No se registró publicación en Meta. Verifica conexión de cuentas/token y vuelve a intentar.',
          );
      }
      return null;
    });
  }

  Future<void> retryPublish(String storyId) async {
    await _runBusy(() async {
      await _api.retryPublish(storyId);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> reject(String storyId, {String reason = ''}) async {
    await _runBusy(() async {
      await _api.reject(storyId, reason: reason);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> regenerate(String storyId) async {
    await _runBusy(() async {
      await _api.regenerate(storyId);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> regenerateCopyFromDesign(String storyId) async {
    await _runBusy(() async {
      await _api.regenerateCopyFromDesignImage(storyId);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> regenerateImage(String storyId, {String? customPrompt}) async {
    await _runStoryImageBusy(storyId, () async {
      await _api.regenerateDesign(storyId, customPrompt: customPrompt);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> generateDesign(String storyId, {String? customPrompt}) async {
    await _runStoryImageBusy(storyId, () async {
      await _api.generateDesign(storyId, customPrompt: customPrompt);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> confirmBaseImage(String storyId) async {
    await _runStoryImageBusy(storyId, () async {
      await _api.confirmBaseImage(storyId);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> changeBaseImage(String storyId, String mediaAssetId) async {
    await _runStoryImageBusy(storyId, () async {
      final selectedId = mediaAssetId.trim();
      developer.log('[publicidad-estados] selected asset id=$selectedId');

      var authorizedAssets = state.contentGalleryAssets;
      developer.log(
        '[publicidad-estados] authorized ids count=${authorizedAssets.length}',
      );

      var selected = _findAuthorizedContentAssetByAnyId(
        selectedId,
        authorizedAssets,
      );

      if (selected == null) {
        // Required safeguard: retry loading official content gallery before rejecting.
        authorizedAssets = await _api.loadContentGallery();
        state = state.copyWith(contentGalleryAssets: authorizedAssets);
        developer.log(
          '[publicidad-estados] authorized ids count=${authorizedAssets.length} (after refresh)',
        );
        selected = _findAuthorizedContentAssetByAnyId(
          selectedId,
          authorizedAssets,
        );
      }

      final isValid = selected != null;
      developer.log('[publicidad-estados] validation result=$isValid');
      if (!isValid) {
        throw StateError(
          'Solo se permiten imágenes de la Galería de Contenido autorizada de Publicidad.',
        );
      }

      final selectedContentGalleryItemId =
          selected.contentGalleryItemId?.trim() ?? '';
      final selectedMediaAssetId = selected.mediaAssetId?.trim() ?? '';
      final selectedImageUrl = selected.imageUrl.trim();
      developer.log(
        '[publicidad-estados] selected contentGalleryItemId=${selectedContentGalleryItemId.isEmpty ? 'null' : selectedContentGalleryItemId}',
      );
      developer.log(
        '[publicidad-estados] selected mediaAssetId=${selectedMediaAssetId.isEmpty ? 'null' : selectedMediaAssetId}',
      );
      developer.log('[publicidad-estados] selected imageUrl=$selectedImageUrl');

      final preferredId = _resolvePreferredSelectionId(selected);
      await _api.changeBaseImage(storyId, preferredId);
      await _refresh(keepLoading: false);
    });
  }

  MarketingMediaAsset? _findAuthorizedContentAssetByAnyId(
    String selectedId,
    List<MarketingMediaAsset> authorizedAssets,
  ) {
    final target = selectedId.trim();
    if (target.isEmpty) return null;

    for (final asset in authorizedAssets) {
      if (asset.id == target) return asset;

      final contentGalleryItemId = asset.contentGalleryItemId?.trim() ?? '';
      if (contentGalleryItemId.isNotEmpty && contentGalleryItemId == target) {
        return asset;
      }

      final mediaAssetId = asset.mediaAssetId?.trim() ?? '';
      if (mediaAssetId.isNotEmpty && mediaAssetId == target) {
        return asset;
      }
    }

    return null;
  }

  String _resolvePreferredSelectionId(MarketingMediaAsset selected) {
    final contentGalleryItemId = selected.contentGalleryItemId?.trim() ?? '';
    if (contentGalleryItemId.isNotEmpty) return contentGalleryItemId;

    final mediaAssetId = selected.mediaAssetId?.trim() ?? '';
    if (mediaAssetId.isNotEmpty) return mediaAssetId;

    return selected.id.trim();
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
    await _runBusy(() async {
      await _api.editStory(
        storyId,
        title: title,
        shortText: shortText,
        longText: longText,
        hashtags: hashtags,
        imagePrompt: imagePrompt,
        imageUrl: imageUrl,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> activateFlow() async {
    await _runBusy(() async {
      await _api.activateFlow();
      await _refresh(keepLoading: false);
    });
  }

  Future<void> pauseFlow() async {
    await _runBusy(() async {
      await _api.pauseFlow();
      await _refresh(keepLoading: false);
    });
  }

  Future<void> resetFlow() async {
    await _runBusy(() async {
      await _api.resetFlow();
      await _refresh(keepLoading: false);
    });
  }

  Future<MarketingResetCleanSummary> resetClean({
    bool includeResearch = false,
    bool includeDraftMedia = true,
    bool includeGeneratedImages = true,
    bool includeApprovedStories = false,
    DateTime? date,
  }) async {
    return _runBusyValue(() async {
      final summary = await _api.resetClean(
        includeResearch: includeResearch,
        includeDraftMedia: includeDraftMedia,
        includeGeneratedImages: includeGeneratedImages,
        includeApprovedStories: includeApprovedStories,
        date: date,
      );
      await _refresh(keepLoading: false);
      return summary;
    });
  }

  Future<void> saveConfig(MarketingFlowConfig config) async {
    await _runBusy(() async {
      await _api.updateConfig(
        flujoActivo: config.active,
        pausado: config.paused,
        cantidadEstadosDiarios: config.dailyStoriesCount,
        horaGeneracion: config.generationTime,
        autoRegenerarSiNoAprueba: config.autoRegenerate,
        horasParaRegenerar: config.regenerateAfterHours,
        productosPrioritarios: config.priorityProducts,
        ciudadObjetivo: config.targetCity,
        tonoDeMarca: config.brandTone,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> createMediaAsset({
    required String fileUrl,
    required String fileName,
    required String category,
    String relatedService = '',
    String description = '',
    List<String> tags = const [],
  }) async {
    await _runBusy(() async {
      await _api.createMediaAsset(
        fileUrl: fileUrl,
        fileName: fileName,
        mimeType: _inferMimeType(fileName),
        category: category,
        relatedService: relatedService,
        description: description,
        tags: tags,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<String?> uploadDesignImage(String fileName) async {
    try {
      developer.log('[publicidad-controller] Simulando upload de $fileName');
      return 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEA...';
    } catch (error) {
      developer.log('[publicidad-controller] Error en upload: $error');
      return null;
    }
  }

  Future<void> createMediaAssetsBulk(
    List<MarketingMediaAssetDraft> drafts,
  ) async {
    if (drafts.isEmpty) return;
    await _runBusy(() async {
      for (final draft in drafts) {
        await _api.createMediaAsset(
          fileUrl: draft.fileUrl,
          fileName: draft.fileName,
          mimeType: _inferMimeType(draft.fileName),
          category: draft.category,
          relatedService: draft.relatedService,
          description: draft.description,
          tags: draft.tags,
        );
      }
      await _refresh(keepLoading: false);
    });
  }

  Future<void> toggleAssetActive(MarketingMediaAsset asset) async {
    await _runBusy(() async {
      await _api.updateMediaAsset(asset.id, isActive: !asset.isActive);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> toggleAssetFeatured(MarketingMediaAsset asset) async {
    await _runBusy(() async {
      await _api.updateMediaAsset(asset.id, isFeatured: !asset.isFeatured);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> updateAssetMeta(
    MarketingMediaAsset asset, {
    required String category,
    required String relatedService,
    required String tagsCsv,
    required String description,
  }) async {
    await _runBusy(() async {
      await _api.updateMediaAsset(
        asset.id,
        category: category,
        relatedService: relatedService,
        tags: tagsCsv
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
        description: description,
      );
      await _refresh(keepLoading: false);
    });
  }

  Future<void> deleteMediaAsset(MarketingMediaAsset asset) async {
    await _runBusy(() async {
      await _api.deleteMediaAsset(asset.id);
      await _refresh(keepLoading: false);
    });
  }

  Future<void> duplicatePublishedAsset(MarketingPublishedAsset item) async {
    await _runBusy(() async {
      final imageUrl = _resolvePublishedImageUrl(item);
      if (imageUrl.isEmpty) {
        throw StateError(
          'No se pudo duplicar: el anuncio publicado no tiene imagen válida.',
        );
      }

      final cleanType = _storyTypeLabelFromCode(item.storyType);
      final baseName = item.headline.trim().isEmpty
          ? 'anuncio-publicado'
          : item.headline.trim().toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]+'),
              '-',
            );
      final safeName = '$baseName-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final tags = <String>{
        ...item.hashtags
            .where((tag) => tag.trim().isNotEmpty)
            .map((tag) => tag.trim()),
        'publicado',
        cleanType.toLowerCase(),
      };

      await _api.createMediaAsset(
        fileUrl: imageUrl,
        fileName: safeName,
        mimeType: _inferMimeType(safeName),
        category: 'Clientes / trabajos realizados',
        relatedService: cleanType,
        description: item.shortText,
        tags: tags.toList(growable: false),
      );

      await _refresh(keepLoading: false);
    });
  }

  Future<void> reusePublishedAssetInStory({
    required MarketingPublishedAsset asset,
    required String storyId,
  }) async {
    await _runBusy(() async {
      if (asset.mediaAssetId != null && asset.mediaAssetId!.trim().isNotEmpty) {
        await _api.changeBaseImage(storyId, asset.mediaAssetId!.trim());
        await _refresh(keepLoading: false);
        return;
      }

      final imageUrl = _resolvePublishedImageUrl(asset);
      if (imageUrl.isEmpty) {
        throw StateError(
          'No se puede reutilizar este anuncio: no tiene imagen válida.',
        );
      }

      final tempFileName = 'reuse-${DateTime.now().millisecondsSinceEpoch}.jpg';
      final created = await _api.createMediaAsset(
        fileUrl: imageUrl,
        fileName: tempFileName,
        mimeType: _inferMimeType(tempFileName),
        category: 'Instalaciones reales',
        relatedService: _storyTypeLabelFromCode(asset.storyType),
        description: asset.shortText,
        tags: [...asset.hashtags, 'reutilizado', 'publicado'],
      );

      await _api.changeBaseImage(storyId, created.id);
      await _refresh(keepLoading: false);
    });
  }

  String _resolvePublishedImageUrl(MarketingPublishedAsset item) {
    final generated = item.generatedImageUrl.trim();
    if (generated.isNotEmpty) return generated;
    final fromAsset = item.mediaAsset?.fileUrl.trim() ?? '';
    if (fromAsset.isNotEmpty) return fromAsset;
    return '';
  }

  String _storyTypeLabelFromCode(String rawType) {
    switch (rawType.toUpperCase()) {
      case 'SALES':
        return 'Venta';
      case 'TRUST':
        return 'Confianza';
      case 'EDUCATIONAL':
        return 'Educativo';
      default:
        return rawType.trim().isEmpty ? 'General' : rawType.trim();
    }
  }

  Future<void> _refresh({required bool keepLoading}) async {
    try {
      state = state.copyWith(
        loading: keepLoading,
        busy: !keepLoading && state.busy,
        clearError: true,
      );

      final date = state.date;
      final from = date.subtract(const Duration(days: 14));
      final to = date;
      final dashboard = await _api.loadDashboard(date);
      final config = await _api.loadConfig();
      final mediaAssets = await _api.loadMediaAssets();
      final contentGalleryAssets = await _api.loadContentGallery();
      var stories = const <MarketingStory>[];
      var historyItems = const <MarketingStory>[];
      MarketingResearchDetail? latestResearch;
      var researchHistory = const <MarketingResearchDetail>[];
      MarketingLearningStats? learningStats;
      var publishedAssets = const <MarketingPublishedAsset>[];
      String? softError;

      try {
        stories = await _api.loadStories(date);
        stories = _normalizeDailyStories(stories);
      } catch (error) {
        softError = _friendlyError(
          error,
          fallback: 'No se pudieron cargar los estados diarios.',
        );
      }

      try {
        final history = await _api.loadHistory(from: from, to: to);
        historyItems = history.items;
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar el historial reciente.',
        );
      }

      // If today's list is empty, fallback to the latest available date in recent history
      // so the Estados view doesn't look broken/blank to the user.
      if (stories.isEmpty && historyItems.isNotEmpty) {
        DateTime? latestDate;
        for (final item in historyItems) {
          final candidate = DateTime(
            item.date.year,
            item.date.month,
            item.date.day,
          );
          if (latestDate == null || candidate.isAfter(latestDate)) {
            latestDate = candidate;
          }
        }

        if (latestDate != null) {
          final latest = latestDate;
          final fallback = historyItems
              .where((item) {
                final d = item.date;
                return d.year == latest.year &&
                    d.month == latest.month &&
                    d.day == latest.day;
              })
              .toList(growable: false);

          final normalizedFallback = _normalizeDailyStories(fallback);
          if (normalizedFallback.isNotEmpty) {
            stories = normalizedFallback;
          }
        }
      }

      final partitioned = _partitionStoriesForActiveAndHistory(
        stories,
        historyItems,
      );
      stories = partitioned.active;
      historyItems = partitioned.history;

      try {
        latestResearch = await _api.loadLatestResearch();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar la investigación más reciente.',
        );
      }

      try {
        researchHistory = await _api.loadResearchHistory();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar el historial de investigaciones.',
        );
      }

      try {
        learningStats = await _api.loadLearningStats();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudieron cargar memorias de aprendizaje.',
        );
      }

      try {
        publishedAssets = await _api.loadPublishedAssets();
      } catch (error) {
        softError ??= _friendlyError(
          error,
          fallback: 'No se pudo cargar la sección de imágenes publicadas.',
        );
      }

      state = state.copyWith(
        loading: false,
        dashboard: dashboard,
        config: config,
        dailyStories: stories,
        mediaAssets: mediaAssets,
        contentGalleryAssets: contentGalleryAssets,
        history: historyItems,
        latestResearch: latestResearch,
        researchHistory: researchHistory,
        learningStats: learningStats,
        publishedAssets: publishedAssets,
        error: softError,
      );
      await _autoSelectBaseImagesIfNeeded();
      _syncImagePollingWithStories(stories);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        busy: false,
        error: _friendlyError(
          error,
          fallback: 'No se pudo actualizar el modulo Publicidad.',
        ),
      );
    }
  }

  void _syncImagePollingWithStories(List<MarketingStory> stories) {
    final activeIds = _activeImageStoryIds(stories);
    if (activeIds.isNotEmpty) {
      _ensureStoryImagePolling(activeIds);
      return;
    }

    if (state.imageBusyStoryIds.isEmpty) {
      return;
    }

    final nextBusy = {...state.imageBusyStoryIds}
      ..removeWhere((storyId) => !_storyHasActiveImageStatus(storyId, stories));
    if (!_sameStringSet(nextBusy, state.imageBusyStoryIds)) {
      state = state.copyWith(imageBusyStoryIds: nextBusy);
    }
  }

  void _ensureStoryImagePolling(Set<String> storyIds) {
    final normalized = storyIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) {
      return;
    }

    final newIds = normalized.difference(_pollingStoryIds);
    _pollingStoryIds.addAll(normalized);
    if (newIds.isNotEmpty || _imagePollingTask == null) {
      _imagePollingDeadline = DateTime.now().add(_imagePollTimeout);
    }

    final nextBusy = {...state.imageBusyStoryIds, ...normalized};
    if (!_sameStringSet(nextBusy, state.imageBusyStoryIds)) {
      state = state.copyWith(imageBusyStoryIds: nextBusy);
    }

    _imagePollingTask ??= _runImagePolling();
  }

  Future<void> _runImagePolling() async {
    try {
      while (!_disposed && _pollingStoryIds.isNotEmpty) {
        final deadline = _imagePollingDeadline;
        if (deadline == null || DateTime.now().isAfter(deadline)) {
          final timedOutIds = {..._pollingStoryIds};
          _pollingStoryIds.clear();
          // Do a final refresh so the UI shows the real server state, not a stale one
          if (!_disposed) {
            try {
              await _refresh(keepLoading: false);
            } catch (_) {}
          }
          final stillActive = timedOutIds
              .where((id) => _storyHasActiveImageStatus(id, state.dailyStories))
              .toSet();
          state = state.copyWith(
            imageBusyStoryIds: {...state.imageBusyStoryIds}
              ..removeAll(timedOutIds),
            error: stillActive.isNotEmpty
                ? 'La imagen sigue en proceso. Actualiza en unos momentos si todavía no aparece.'
                : null,
          );
          break;
        }

        await Future<void>.delayed(_imagePollInterval);
        if (_disposed || _pollingStoryIds.isEmpty) {
          break;
        }

        await _refresh(keepLoading: false);

        final activeIds = _activeImageStoryIds(state.dailyStories);
        _pollingStoryIds.removeWhere((storyId) => !activeIds.contains(storyId));

        final nextBusy = {...state.imageBusyStoryIds}
          ..removeWhere((storyId) => !_pollingStoryIds.contains(storyId))
          ..addAll(_pollingStoryIds);
        if (!_sameStringSet(nextBusy, state.imageBusyStoryIds)) {
          state = state.copyWith(imageBusyStoryIds: nextBusy);
        }
      }
    } finally {
      _imagePollingTask = null;
    }
  }

  Set<String> _activeImageStoryIds(List<MarketingStory> stories) {
    return stories
        .where((story) => _isActiveImageStatus(story.imageStatus))
        .map((story) => story.id)
        .toSet();
  }

  bool _storyHasActiveImageStatus(
    String storyId,
    List<MarketingStory> stories,
  ) {
    for (final story in stories) {
      if (story.id == storyId) {
        return _isActiveImageStatus(story.imageStatus);
      }
    }
    return false;
  }

  bool _isActiveImageStatus(MarketingImageStatus status) {
    return status == MarketingImageStatus.queued ||
        status == MarketingImageStatus.processing;
  }

  bool _sameStringSet(Set<String> left, Set<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final value in left) {
      if (!right.contains(value)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _runBusy(Future<void> Function() task) async {
    if (state.busy) return;
    try {
      state = state.copyWith(busy: true, clearError: true);
      await task();
      state = state.copyWith(busy: false);
    } catch (error) {
      state = state.copyWith(
        busy: false,
        error: _friendlyError(
          error,
          fallback: 'No se pudo completar la accion solicitada.',
        ),
      );
    }
  }

  Future<T> _runBusyValue<T>(Future<T> Function() task) async {
    if (state.busy) {
      throw ApiException(
        'Ya hay una accion en proceso. Intentalo nuevamente en unos segundos.',
      );
    }
    try {
      state = state.copyWith(busy: true, clearError: true);
      final result = await task();
      state = state.copyWith(busy: false);
      return result;
    } catch (error) {
      final message = _friendlyError(
        error,
        fallback: 'No se pudo completar la accion solicitada.',
      );
      state = state.copyWith(busy: false, error: message);
      if (error is ApiException) {
        rethrow;
      }
      throw ApiException(message);
    }
  }

  Future<void> _runStoryImageBusy(
    String storyId,
    Future<void> Function() task,
  ) async {
    final nextBusy = {...state.imageBusyStoryIds, storyId};
    state = state.copyWith(imageBusyStoryIds: nextBusy, clearError: true);
    try {
      await task();
    } catch (error) {
      final message = _friendlyError(
        error,
        fallback: 'No se pudo completar la generación de imagen.',
      );
      state = state.copyWith(
        error: message,
        imageBusyStoryIds: {...state.imageBusyStoryIds}..remove(storyId),
      );
      return;
    }
    final busyIds = {...state.imageBusyStoryIds};
    if (!_storyHasActiveImageStatus(storyId, state.dailyStories)) {
      busyIds.remove(storyId);
    }
    state = state.copyWith(imageBusyStoryIds: busyIds);
  }

  String _friendlyError(Object error, {required String fallback}) {
    if (error is ApiException) {
      final raw = error.message.trim();
      final normalized = raw.toLowerCase();
      final paginationError =
          error.code == 400 &&
          (normalized.contains('page must') ||
              normalized.contains('limit must'));
      if (paginationError) {
        return 'Se corrigio automaticamente la paginacion. Intenta actualizar de nuevo.';
      }

      final genericServerError =
          normalized == 'error interno del servidor' ||
          normalized == 'internal server error';
      if (genericServerError) {
        return fallback;
      }

      if (normalized.contains('bad state')) {
        return 'No se pudo completar la accion por un estado invalido del flujo. Actualiza e intenta nuevamente.';
      }

      if (raw.isEmpty || raw.startsWith('{') || raw.startsWith('[')) {
        return fallback;
      }
      return raw;
    }

    final raw = '$error'.trim();
    if (raw.isEmpty || raw.startsWith('{') || raw.startsWith('[')) {
      return fallback;
    }
    return raw;
  }

  String _inferMimeType(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _autoSelectBaseImagesIfNeeded() async {
    if (_autoSelectingBaseImages || _disposed) return;

    final gallery = state.contentGalleryAssets;
    if (gallery.isEmpty) return;

    final candidateMediaAssetIds = gallery
        .map((item) => item.mediaAssetId?.trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (candidateMediaAssetIds.isEmpty) return;

    final pendingStories = state.dailyStories
        .where((story) {
          if (_autoSelectionAttemptedStoryIds.contains(story.id)) return false;
          final hasMediaAsset = (story.mediaAssetId ?? '').trim().isNotEmpty;
          final isConfirmed =
              story.imageGenerationMetadata['imageSelectionConfirmed'] == true;
          return !hasMediaAsset && !isConfirmed;
        })
        .toList(growable: false);
    if (pendingStories.isEmpty) return;

    _autoSelectingBaseImages = true;
    var changedAny = false;
    try {
      for (final story in pendingStories) {
        _autoSelectionAttemptedStoryIds.add(story.id);
        try {
          final analysis = await _api.analyzeMediaAssets(
            mediaAssetIds: candidateMediaAssetIds,
            storyType: _storyTypeApiCode(story.type),
          );
          final rawRecommended = analysis['recommended'];
          final recommended = rawRecommended is Map
              ? rawRecommended.cast<String, dynamic>()
              : const <String, dynamic>{};

          final suggestedId =
              '${recommended['mediaAssetId'] ?? recommended['id'] ?? ''}'
                  .trim();
          if (suggestedId.isEmpty) continue;

          final selected = _findAuthorizedContentAssetByAnyId(
            suggestedId,
            gallery,
          );
          final finalId = selected != null
              ? _resolvePreferredSelectionId(selected)
              : suggestedId;

          developer.log(
            '[publicidad-estados] auto-select story=${story.id} suggested=$suggestedId final=$finalId',
          );
          await _api.changeBaseImage(story.id, finalId);
          changedAny = true;
        } catch (error) {
          developer.log(
            '[publicidad-estados] auto-select skipped story=${story.id}: $error',
          );
        }
      }
    } finally {
      _autoSelectingBaseImages = false;
    }

    if (changedAny && !_disposed) {
      await _refresh(keepLoading: false);
    }
  }

  String _storyTypeApiCode(MarketingStoryType type) {
    switch (type) {
      case MarketingStoryType.sales:
        return 'SALES';
      case MarketingStoryType.trust:
        return 'TRUST';
      case MarketingStoryType.educational:
        return 'EDUCATIONAL';
    }
  }

  List<MarketingStory> _normalizeDailyStories(List<MarketingStory> stories) {
    if (stories.isEmpty) return stories;

    final byType = <MarketingStoryType, MarketingStory>{};
    for (final item in stories) {
      final current = byType[item.type];
      if (current == null) {
        byType[item.type] = item;
        continue;
      }

      final currentActive = !_isStoryFullyPublished(current);
      final nextActive = !_isStoryFullyPublished(item);
      if (currentActive != nextActive) {
        if (nextActive) {
          byType[item.type] = item;
        }
        continue;
      }

      final currentStamp = current.updatedAt ?? current.date;
      final nextStamp = item.updatedAt ?? item.date;
      if (nextStamp.isAfter(currentStamp)) {
        byType[item.type] = item;
      }
    }

    const order = [
      MarketingStoryType.sales,
      MarketingStoryType.trust,
      MarketingStoryType.educational,
    ];

    return order
        .map((type) => byType[type])
        .whereType<MarketingStory>()
        .toList(growable: false);
  }

  ({List<MarketingStory> active, List<MarketingStory> history})
  _partitionStoriesForActiveAndHistory(
    List<MarketingStory> daily,
    List<MarketingStory> history,
  ) {
    final active = daily
        .where((story) => !_isStoryFullyPublished(story))
        .toList(growable: false);

    final mergedById = <String, MarketingStory>{};
    void addStory(MarketingStory item) {
      final id = item.id.trim();
      if (id.isEmpty) return;
      final current = mergedById[id];
      if (current == null) {
        mergedById[id] = item;
        return;
      }
      final currentStamp = current.updatedAt ?? current.date;
      final nextStamp = item.updatedAt ?? item.date;
      if (nextStamp.isAfter(currentStamp)) {
        mergedById[id] = item;
      }
    }

    for (final item in history) {
      addStory(item);
    }
    for (final item in daily.where(_isStoryFullyPublished)) {
      addStory(item);
    }

    final mergedHistory = mergedById.values.toList(growable: false)
      ..sort((a, b) {
        final bStamp = b.updatedAt ?? b.date;
        final aStamp = a.updatedAt ?? a.date;
        return bStamp.compareTo(aStamp);
      });

    return (active: active, history: mergedHistory);
  }

  bool _isStoryFullyPublished(MarketingStory story) {
    return story.publishStatus == MarketingPublishStatus.published;
  }

  @override
  void dispose() {
    _disposed = true;
    _pollingStoryIds.clear();
    super.dispose();
  }
}

class PublicidadScreen extends ConsumerStatefulWidget {
  const PublicidadScreen({super.key})
    : _initialTab = _PublicidadTab.dashboard,
      _lockedTab = null;

  const PublicidadScreen.investigacion({super.key})
    : _initialTab = _PublicidadTab.investigacion,
      _lockedTab = _PublicidadTab.investigacion;

  const PublicidadScreen.estados({super.key})
    : _initialTab = _PublicidadTab.estados,
      _lockedTab = _PublicidadTab.estados;

  final _PublicidadTab _initialTab;
  final _PublicidadTab? _lockedTab;

  @override
  ConsumerState<PublicidadScreen> createState() => _PublicidadScreenState();
}

class _PublicidadScreenState extends ConsumerState<PublicidadScreen> {
  late _PublicidadTab _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget._initialTab;
  }

  /// Opens the file explorer to pick an image, uploads it to the server,
  /// creates a gallery entry with category 'Diseños publicados', and returns
  /// the uploaded image URL. Returns null if the user cancels.
  Future<String?> _pickAndUploadDesignImage(
    BuildContext context,
    WidgetRef ref,
  ) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el explorador: $e')),
        );
      }
      return null;
    }

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    final fileName = file.name;

    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer el archivo seleccionado.'),
          ),
        );
      }
      return null;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subiendo imagen...')));
    }

    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final uploaded = await uploadRepo.uploadImage(
        fileName: fileName,
        bytes: bytes,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagen subida y guardada en galería.')),
        );
      }
      return uploaded.url;
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty ? e.message : 'Error al subir la imagen.',
            ),
          ),
        );
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al subir la imagen: $e')));
      }
      return null;
    }
  }

  Future<String?> _pickAndUploadDesignVideo(
    BuildContext context,
    WidgetRef ref,
  ) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
        allowMultiple: false,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el explorador: $e')),
        );
      }
      return null;
    }

    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    final fileName = file.name;

    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer el video seleccionado.'),
          ),
        );
      }
      return null;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subiendo video...')));
    }

    try {
      final uploadRepo = ref.read(uploadRepositoryProvider);
      final uploaded = await uploadRepo.uploadVideo(
        fileName: fileName,
        bytes: bytes,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video subido correctamente.')),
        );
      }
      return uploaded.url;
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.message.isNotEmpty ? e.message : 'Error al subir el video.',
            ),
          ),
        );
      }
      return null;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al subir el video: $e')));
      }
      return null;
    }
  }

  Future<void> _handleRepairIncomplete(
    BuildContext context,
    PublicidadController controller,
  ) async {
    try {
      final summary = await controller.repairIncompleteNow();
      if (!context.mounted) return;
      final hasErrors = summary.failed.isNotEmpty;
      final message = hasErrors
          ? 'Reparados ${summary.repaired}/${summary.targeted}. Fallaron ${summary.failed.length}.'
          : 'Reparados ${summary.repaired}/${summary.targeted} anuncios incompletos.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.trim().isEmpty
                ? 'No se pudo ejecutar la reparación automática.'
                : error.message,
          ),
        ),
      );
    }
  }

  Future<void> _handleResetClean(
    BuildContext context,
    PublicidadController controller,
    DateTime selectedDate,
  ) async {
    final request = await showDialog<_ResetCleanRequest>(
      context: context,
      builder: (_) => _ResetCleanDialog(currentDate: selectedDate),
    );
    if (request == null) return;

    try {
      await controller.resetClean(
        includeResearch: request.includeResearch,
        includeDraftMedia: true,
        includeGeneratedImages: request.includeGeneratedImages,
        includeApprovedStories: true,
        date: request.cleanAllGenerated ? null : selectedDate,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Publicidad reiniciada correctamente. Puedes generar estados nuevamente.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.trim().isEmpty
                ? 'No se pudo ejecutar el reset limpio.'
                : error.message,
          ),
        ),
      );
    }
  }

  Future<void> _handleForceResearch(
    BuildContext context,
    PublicidadController controller,
  ) async {
    try {
      await controller.forceResearchNow();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Investigación manual generada correctamente.'),
        ),
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message.trim().isEmpty
                ? 'No se pudo generar la investigación manual.'
                : error.message,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final isAdmin =
        user != null &&
        hasPermission(user.appRole, AppPermission.viewPublicidad);

    if (!isAdmin) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad', showLogo: false),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final state = ref.watch(publicidadControllerProvider);
    final controller = ref.read(publicidadControllerProvider.notifier);
    final activeStories = _limitToThreeStoryTypes(state.dailyStories);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const CustomAppBar(title: 'Publicidad'),
      backgroundColor: scheme.surfaceContainerLowest,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.surface, scheme.surfaceContainerLowest],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: _TopToolbar(
                  date: state.date,
                  tab: _tab,
                  busy: state.busy,
                  lockedTab: widget._lockedTab,
                  onPickDate: (value) => controller.changeDate(value),
                  onTabChanged: (value) {
                    if (widget._lockedTab != null) return;
                    setState(() => _tab = value);
                  },
                  onRefresh: controller.refresh,
                ),
              ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _ErrorBanner(message: state.error!),
                ),
              Expanded(
                child: state.loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: controller.refresh,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          children: [
                            if (_tab == _PublicidadTab.dashboard)
                              _DashboardTab(
                                state: state,
                                stories: activeStories,
                                mediaAssets: state.mediaAssets,
                                contentGalleryAssets:
                                    state.contentGalleryAssets,
                                researches: state.researchHistory,
                                onActivate: controller.activateFlow,
                                onPause: controller.pauseFlow,
                                onGenerateNow: (ids) => controller.generateNow(
                                  selectedMediaAssetIds: ids,
                                ),
                                onRepairIncomplete: () =>
                                    _handleRepairIncomplete(
                                      context,
                                      controller,
                                    ),
                                onResetClean: () => _handleResetClean(
                                  context,
                                  controller,
                                  state.date,
                                ),
                                onApprove: (storyId, contentType) =>
                                    controller.approve(storyId, contentType),
                                onRegenerate: controller.regenerate,
                                onRegenerateImage: controller.regenerateImage,
                                onConfirmBaseImage: controller.confirmBaseImage,
                                onGenerateDesign: controller.generateDesign,
                                onChangeBaseImage: controller.changeBaseImage,
                                busy: state.busy,
                                imageBusyStoryIds: state.imageBusyStoryIds,
                              ),
                            if (_tab == _PublicidadTab.investigacion)
                              _ResearchSummaryTab(
                                dashboard: state.dashboard,
                                latestResearch: state.latestResearch,
                                researchHistory: state.researchHistory,
                                learningStats: state.learningStats,
                                busy: state.busy,
                                onForceResearch: () =>
                                    _handleForceResearch(context, controller),
                              ),
                            if (_tab == _PublicidadTab.galeria)
                              _GalleryTab(
                                assets: state.mediaAssets,
                                publishedAssets: state.publishedAssets,
                                busy: state.busy,
                                onCreateAssets:
                                    controller.createMediaAssetsBulk,
                                onToggleActive: controller.toggleAssetActive,
                                onToggleFeatured:
                                    controller.toggleAssetFeatured,
                                onUpdateMeta: controller.updateAssetMeta,
                                onDelete: controller.deleteMediaAsset,
                              ),
                            if (_tab == _PublicidadTab.estados)
                              _DailyStoriesTab(
                                stories: activeStories,
                                mediaAssets: state.contentGalleryAssets,
                                researches: state.researchHistory,
                                busy: state.busy,
                                imageBusyStoryIds: state.imageBusyStoryIds,
                                onApprove: (storyId, contentType) =>
                                    controller.approve(storyId, contentType),
                                onReject: controller.reject,
                                onRegenerate: controller.regenerate,
                                onRegenerateImage: controller.regenerateImage,
                                onConfirmBaseImage: controller.confirmBaseImage,
                                onGenerateDesign: controller.generateDesign,
                                onChangeBaseImage: controller.changeBaseImage,
                                onRegenerateCopyFromDesign:
                                    controller.regenerateCopyFromDesign,
                                onRetryPublish: controller.retryPublish,
                                onEdit: (story, payload) {
                                  return controller.editStory(
                                    story.id,
                                    title: payload.title,
                                    shortText: payload.shortText,
                                    longText: payload.longText,
                                    hashtags: payload.hashtags,
                                    imagePrompt: payload.imagePrompt,
                                    imageUrl: payload.imageUrl,
                                  );
                                },
                                onUploadDesignImage: (context) async {
                                  return _pickAndUploadDesignImage(
                                    context,
                                    ref,
                                  );
                                },
                                onUploadVideo: (context) async {
                                  return _pickAndUploadDesignVideo(
                                    context,
                                    ref,
                                  );
                                },
                              ),
                            if (_tab == _PublicidadTab.historial)
                              _HistoryTab(items: state.history),
                            if (_tab == _PublicidadTab.configuracion)
                              _ConfigTab(
                                config: state.config,
                                busy: state.busy,
                                onSave: controller.saveConfig,
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<MarketingStory> _limitToThreeStoryTypes(List<MarketingStory> stories) {
    if (stories.length <= 3) return stories;

    final byType = <MarketingStoryType, MarketingStory>{};
    for (final item in stories) {
      final current = byType[item.type];
      if (current == null) {
        byType[item.type] = item;
        continue;
      }
      final currentStamp = current.updatedAt ?? current.date;
      final nextStamp = item.updatedAt ?? item.date;
      if (nextStamp.isAfter(currentStamp)) {
        byType[item.type] = item;
      }
    }

    const order = [
      MarketingStoryType.sales,
      MarketingStoryType.trust,
      MarketingStoryType.educational,
    ];
    return order
        .map((type) => byType[type])
        .whereType<MarketingStory>()
        .toList(growable: false);
  }
}

class _TopToolbar extends StatelessWidget {
  const _TopToolbar({
    required this.date,
    required this.tab,
    required this.busy,
    required this.onPickDate,
    required this.onTabChanged,
    required this.onRefresh,
    this.lockedTab,
  });

  final DateTime date;
  final _PublicidadTab tab;
  final bool busy;
  final _PublicidadTab? lockedTab;
  final ValueChanged<DateTime> onPickDate;
  final ValueChanged<_PublicidadTab> onTabChanged;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Flujo de contenidos diarios',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: lockedTab != null
                      ? Chip(
                          avatar: const Icon(Icons.lock_outline, size: 16),
                          label: Text(_tabLabel(lockedTab!)),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SegmentedButton<_PublicidadTab>(
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: _PublicidadTab.dashboard,
                                label: Text(
                                  'Dashboard',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              ButtonSegment(
                                value: _PublicidadTab.investigacion,
                                label: Text(
                                  'Investigación',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              ButtonSegment(
                                value: _PublicidadTab.galeria,
                                label: Text(
                                  'Galería de Publicidad',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              ButtonSegment(
                                value: _PublicidadTab.estados,
                                label: Text(
                                  'Estados diarios',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              ButtonSegment(
                                value: _PublicidadTab.historial,
                                label: Text(
                                  'Historial',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              ButtonSegment(
                                value: _PublicidadTab.configuracion,
                                label: Text(
                                  'Configuración',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                            selected: {tab},
                            onSelectionChanged: (value) {
                              if (value.isNotEmpty) onTabChanged(value.first);
                            },
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: busy ? null : onRefresh,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(6),
                icon: const Icon(Icons.refresh_rounded),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                        );
                        if (selected != null) onPickDate(selected);
                      },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _tabLabel(_PublicidadTab value) {
    switch (value) {
      case _PublicidadTab.dashboard:
        return 'Dashboard';
      case _PublicidadTab.investigacion:
        return 'Investigación';
      case _PublicidadTab.galeria:
        return 'Galería de Publicidad';
      case _PublicidadTab.estados:
        return 'Estados diarios';
      case _PublicidadTab.historial:
        return 'Historial';
      case _PublicidadTab.configuracion:
        return 'Configuración';
    }
  }
}

class _ResetCleanRequest {
  const _ResetCleanRequest({
    required this.cleanAllGenerated,
    required this.includeResearch,
    required this.includeGeneratedImages,
  });

  final bool cleanAllGenerated;
  final bool includeResearch;
  final bool includeGeneratedImages;
}

class _ResetCleanDialog extends StatefulWidget {
  const _ResetCleanDialog({required this.currentDate});

  final DateTime currentDate;

  @override
  State<_ResetCleanDialog> createState() => _ResetCleanDialogState();
}

class _ResetCleanDialogState extends State<_ResetCleanDialog> {
  bool _cleanAllGenerated = false;
  bool _includeResearch = false;
  bool _includeGeneratedImages = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset limpio de publicidad'),
      content: SizedBox(
        width: 620,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Esto limpiará los estados generados y permitirá regenerar todo desde cero. No borrará imágenes publicitarias subidas manualmente ni investigaciones aprobadas.',
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: !_cleanAllGenerated,
              title: const Text('Limpiar estados de hoy'),
              subtitle: Text(
                '${widget.currentDate.day.toString().padLeft(2, '0')}/${widget.currentDate.month.toString().padLeft(2, '0')}/${widget.currentDate.year}',
              ),
              onChanged: (v) => setState(() => _cleanAllGenerated = !v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _cleanAllGenerated,
              title: const Text('Limpiar todos los estados generados'),
              onChanged: (v) => setState(() => _cleanAllGenerated = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _includeResearch,
              title: const Text('Limpiar también investigaciones'),
              onChanged: (v) => setState(() => _includeResearch = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _includeGeneratedImages,
              title: const Text(
                'Limpiar también imágenes generadas temporales',
              ),
              onChanged: (v) => setState(() => _includeGeneratedImages = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop(
              _ResetCleanRequest(
                cleanAllGenerated: _cleanAllGenerated,
                includeResearch: _includeResearch,
                includeGeneratedImages: _includeGeneratedImages,
              ),
            );
          },
          icon: const Icon(Icons.cleaning_services_rounded),
          label: const Text('Ejecutar reset limpio'),
        ),
      ],
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.state,
    required this.stories,
    required this.mediaAssets,
    required this.contentGalleryAssets,
    required this.researches,
    required this.onActivate,
    required this.onPause,
    required this.onGenerateNow,
    required this.onRepairIncomplete,
    required this.onResetClean,
    required this.onApprove,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onConfirmBaseImage,
    required this.onGenerateDesign,
    required this.onChangeBaseImage,
    required this.busy,
    required this.imageBusyStoryIds,
  });

  final PublicidadState state;
  final List<MarketingStory> stories;
  final List<MarketingMediaAsset> mediaAssets;
  final List<MarketingMediaAsset> contentGalleryAssets;
  final List<MarketingResearchDetail> researches;
  final Future<void> Function() onActivate;
  final Future<void> Function() onPause;
  final Future<void> Function(List<String> selectedMediaAssetIds) onGenerateNow;
  final Future<void> Function() onRepairIncomplete;
  final Future<void> Function() onResetClean;
  final Future<void> Function(
    String storyId,
    List<MarketingPublishTarget> publishTargets,
  )
  onApprove;
  final Future<void> Function(String storyId) onRegenerate;
  final Future<void> Function(String storyId, {String? customPrompt})
  onRegenerateImage;
  final Future<void> Function(String storyId) onConfirmBaseImage;
  final Future<void> Function(String storyId, {String? customPrompt})
  onGenerateDesign;
  final Future<void> Function(String storyId, String mediaAssetId)
  onChangeBaseImage;
  final bool busy;
  final Set<String> imageBusyStoryIds;

  @override
  Widget build(BuildContext context) {
    final dashboard = state.dashboard;
    final completeStories = stories.where(_isCompleteStory).length;
    final incompleteStories = stories.length - completeStories;
    final suggestedImages = stories
        .where((s) => _resolveBaseImageUrl(s).isNotEmpty)
        .length;
    final readyBaseImages = stories
        .where(
          (s) =>
              _resolveBaseImageUrl(s).isNotEmpty &&
              s.imagePrompt.trim().isNotEmpty,
        )
        .length;
    final generatedImages = stories
        .where(
          (s) =>
              s.imageStatus == MarketingImageStatus.generated &&
              _safeImageUrl(s.generatedImageUrl).isNotEmpty,
        )
        .length;
    final pendingApproval = stories
        .where(
          (s) =>
              s.status == MarketingStoryStatus.pending ||
              s.status == MarketingStoryStatus.regenerated,
        )
        .length;
    final imagesWithoutLoad = stories
        .where((s) => _safeImageUrl(s.generatedImageUrl).isEmpty)
        .length;
    final generatedCopies = stories
        .where(
          (s) =>
              s.title.trim().isNotEmpty &&
              s.shortText.trim().isNotEmpty &&
              s.usedCTA.trim().isNotEmpty,
        )
        .length;
    final keyMetrics = [
      ('Flujo', dashboard?.flowStatus ?? 'INACTIVO'),
      ('Pendientes', '${dashboard?.pendingApprovalCount ?? 0}'),
      ('Aprobados hoy', '${dashboard?.approvedTodayCount ?? 0}'),
      ('Listos', '$completeStories'),
      ('Incompletos', '$incompleteStories'),
      ('Imágenes sugeridas', '$suggestedImages'),
      ('Imágenes listas', '$readyBaseImages'),
      ('Imágenes generadas', '$generatedImages'),
      ('Imágenes sin cargar', '$imagesWithoutLoad'),
      ('Pendientes aprobación', '$pendingApproval'),
      ('Copys', '$generatedCopies'),
      (
        'Investigación',
        dashboard?.researchUsable == true ? 'Usable' : 'No usable',
      ),
      ('Última', _formatDateTime(dashboard?.lastGenerationAt)),
      ('Próxima', _formatDateTime(dashboard?.nextSuggestedGeneration)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _MetaChip(
                label: 'Flujo',
                value: dashboard?.flowStatus ?? 'INACTIVO',
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: busy ? null : () => onGenerateNow(const []),
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('Generar estados ahora'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final selected = await showDialog<List<String>>(
                          context: context,
                          builder: (_) => _SelectGenerationImagesDialog(
                            assets: mediaAssets,
                          ),
                        );
                        if (selected == null || selected.isEmpty) return;
                        await onGenerateNow(selected);
                      },
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Generar con imágenes'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onRepairIncomplete,
                icon: const Icon(Icons.build_circle_outlined),
                label: const Text('Reparar incompletos'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onResetClean,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset limpio'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onActivate,
                icon: const Icon(Icons.play_circle_fill_rounded),
                label: const Text('Activar'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : onPause,
                icon: const Icon(Icons.pause_circle_filled_rounded),
                label: const Text('Pausar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final metric in keyMetrics) ...[
                _MetaChip(label: metric.$1, value: metric.$2),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Estados diarios',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _DailyStoriesTab(
          stories: stories,
          mediaAssets: contentGalleryAssets,
          researches: researches,
          busy: busy,
          onApprove: (storyId, publishTargets) =>
              onApprove(storyId, publishTargets),
          onReject: (_, {reason = ''}) async {},
          onRegenerate: onRegenerate,
          onRegenerateImage: onRegenerateImage,
          onConfirmBaseImage: onConfirmBaseImage,
          onGenerateDesign: onGenerateDesign,
          onChangeBaseImage: onChangeBaseImage,
          onEdit: (_, __) async {},
          onRegenerateCopyFromDesign: (_) async {},
          onRetryPublish: (_) async {},
          onUploadDesignImage: (context) async {
            return null;
          },
          compactActions: true,
          imageBusyStoryIds: imageBusyStoryIds,
        ),
      ],
    );
  }

  bool _isCompleteStory(MarketingStory story) {
    return validateStoryProgress(story).canApprove;
  }
}

class _DailyStoriesTab extends StatefulWidget {
  const _DailyStoriesTab({
    required this.stories,
    required this.mediaAssets,
    required this.researches,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onConfirmBaseImage,
    required this.onGenerateDesign,
    required this.onChangeBaseImage,
    required this.onEdit,
    required this.onRegenerateCopyFromDesign,
    required this.onRetryPublish,
    required this.imageBusyStoryIds,
    this.onUploadDesignImage,
    this.onUploadVideo,
    this.compactActions = false,
  });

  final List<MarketingStory> stories;
  final List<MarketingMediaAsset> mediaAssets;
  final List<MarketingResearchDetail> researches;
  final bool busy;
  final Future<void> Function(
    String storyId,
    List<MarketingPublishTarget> publishTargets,
  )
  onApprove;
  final Future<void> Function(String storyId, {String reason}) onReject;
  final Future<void> Function(String storyId) onRegenerate;
  final Future<void> Function(String storyId, {String? customPrompt})
  onRegenerateImage;
  final Future<void> Function(String storyId) onConfirmBaseImage;
  final Future<void> Function(String storyId, {String? customPrompt})
  onGenerateDesign;
  final Future<void> Function(String storyId, String mediaAssetId)
  onChangeBaseImage;
  final Future<void> Function(MarketingStory story, _EditStoryPayload payload)
  onEdit;
  final Future<void> Function(String storyId) onRegenerateCopyFromDesign;
  final Future<void> Function(String storyId) onRetryPublish;
  final Set<String> imageBusyStoryIds;
  final Future<String?> Function(BuildContext context)? onUploadDesignImage;
  final Future<String?> Function(BuildContext context)? onUploadVideo;
  final bool compactActions;

  @override
  State<_DailyStoriesTab> createState() => _DailyStoriesTabState();
}

class _DailyStoriesTabState extends State<_DailyStoriesTab> {
  _EstadosPhase _phase = _EstadosPhase.crearDiseno;
  _EstadosViewMode _viewMode = _EstadosViewMode.normal;

  Future<void> _openEstadoRapidoScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EstadoRapidoScreen(
          stories: widget.stories,
          busy: widget.busy,
          onApprove: widget.onApprove,
          onRetryPublish: widget.onRetryPublish,
          onRegenerateCopyFromDesign: widget.onRegenerateCopyFromDesign,
          onEdit: widget.onEdit,
          onUploadDesignImage: widget.onUploadDesignImage,
        ),
      ),
    );
  }

  Future<void> _openEstadoVideoScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EstadoVideoScreen(
          stories: widget.stories,
          busy: widget.busy,
          onApprove: widget.onApprove,
          onRegenerateCopyFromDesign: widget.onRegenerateCopyFromDesign,
          onEdit: widget.onEdit,
          onUploadVideo: widget.onUploadVideo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stories = widget.stories;
    if (stories.isEmpty) {
      return const _EmptyState(
        text:
            'No hay estados generados todavia. Presiona "Generar estados ahora".',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.compactActions)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<_EstadosViewMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment<_EstadosViewMode>(
                        value: _EstadosViewMode.normal,
                        icon: Icon(Icons.view_day_outlined),
                        label: Text('Estado normal'),
                      ),
                      ButtonSegment<_EstadosViewMode>(
                        value: _EstadosViewMode.rapido,
                        icon: Icon(Icons.flash_on_rounded),
                        label: Text('Estado rápido'),
                      ),
                      ButtonSegment<_EstadosViewMode>(
                        value: _EstadosViewMode.video,
                        icon: Icon(Icons.smart_display_rounded),
                        label: Text('Estado video'),
                      ),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (next) {
                      if (next.isEmpty) return;
                      final selected = next.first;
                      setState(() => _viewMode = selected);
                      if (selected == _EstadosViewMode.rapido) {
                        _openEstadoRapidoScreen();
                      } else if (selected == _EstadosViewMode.video) {
                        _openEstadoVideoScreen();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        if (!widget.compactActions) const SizedBox(height: 10),
        if (!widget.compactActions && _viewMode == _EstadosViewMode.rapido)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo rápido listo',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sube imagen, genera copy y publica en Facebook/Instagram (Story + Post) desde una sola pantalla.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _openEstadoRapidoScreen,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Abrir Estado rápido'),
                ),
              ],
            ),
          ),
        if (!widget.compactActions && _viewMode == _EstadosViewMode.rapido)
          const SizedBox(height: 10),
        if (!widget.compactActions && _viewMode == _EstadosViewMode.video)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo video listo',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sube video vertical, asígnalo al estado y publícalo en canales seleccionados.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _openEstadoVideoScreen,
                  icon: const Icon(Icons.smart_display_rounded),
                  label: const Text('Abrir Estado video'),
                ),
              ],
            ),
          ),
        if (!widget.compactActions && _viewMode == _EstadosViewMode.video)
          const SizedBox(height: 10),
        if (widget.compactActions || _viewMode == _EstadosViewMode.normal)
          SegmentedButton<_EstadosPhase>(
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            segments: const [
              ButtonSegment<_EstadosPhase>(
                value: _EstadosPhase.crearDiseno,
                icon: Icon(Icons.design_services_rounded),
                label: Text('1 Crear diseño'),
              ),
              ButtonSegment<_EstadosPhase>(
                value: _EstadosPhase.copys,
                icon: Icon(Icons.text_fields_rounded),
                label: Text('2 Copy final'),
              ),
              ButtonSegment<_EstadosPhase>(
                value: _EstadosPhase.aprobarPublicar,
                icon: Icon(Icons.publish_rounded),
                label: Text('3 Publicar'),
              ),
            ],
            selected: {_phase},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              setState(() => _phase = next.first);
            },
          ),
        if (widget.compactActions || _viewMode == _EstadosViewMode.normal)
          const SizedBox(height: 10),
        if (widget.compactActions || _viewMode == _EstadosViewMode.normal)
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final width = constraints.maxWidth;
              final columns = width >= 1380
                  ? 3
                  : width >= 860
                  ? 2
                  : 1;
              final cardWidth = (width - (spacing * (columns - 1))) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final story in stories)
                    SizedBox(
                      width: cardWidth,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: _StoryCard(
                          story: story,
                          phase: _phase,
                          usedResearch: _findResearch(story.researchId),
                          busy: widget.busy,
                          imageBusy: widget.imageBusyStoryIds.contains(
                            story.id,
                          ),
                          compactActions: widget.compactActions,
                          mediaAssets: widget.mediaAssets,
                          onApprove: (publishTargets) =>
                              widget.onApprove(story.id, publishTargets),
                          onReject: () => widget.onReject(story.id),
                          onRegenerate: () => widget.onRegenerate(story.id),
                          onRegenerateImage: () =>
                              widget.onRegenerateImage(story.id),
                          onConfirmBaseImage: () =>
                              widget.onConfirmBaseImage(story.id),
                          onGenerateDesign: () =>
                              widget.onGenerateDesign(story.id),
                          onRegenerateCopyFromDesign: () =>
                              widget.onRegenerateCopyFromDesign(story.id),
                          onRetryPublish: () => widget.onRetryPublish(story.id),
                          onChangeBaseImage: () async {
                            final chosen = await showDialog<String>(
                              context: context,
                              builder: (_) => _PickMediaAssetDialog(
                                assets: widget.mediaAssets,
                                selectedId: story.mediaAssetId,
                              ),
                            );
                            if (chosen != null && chosen.isNotEmpty) {
                              await widget.onChangeBaseImage(story.id, chosen);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Imagen base seleccionada. Confirma imagen para continuar.',
                                  ),
                                ),
                              );
                            }
                          },
                          onEdit: () async {
                            final payload = await showDialog<_EditStoryPayload>(
                              context: context,
                              builder: (_) => _EditStoryDialog(
                                story: story,
                                mediaAssets: widget.mediaAssets,
                                onUploadImage: widget.onUploadDesignImage,
                              ),
                            );
                            if (payload != null) {
                              await widget.onEdit(story, payload);
                            }
                          },
                          onUploadFinalDesign:
                              widget.onUploadDesignImage == null
                              ? null
                              : (ctx) async {
                                  final uploadedUrl =
                                      await widget.onUploadDesignImage!(ctx);
                                  if (uploadedUrl == null ||
                                      uploadedUrl.isEmpty) {
                                    return;
                                  }
                                  // Save imageUrl to story
                                  await widget.onEdit(
                                    story,
                                    _EditStoryPayload(
                                      title: story.title,
                                      shortText: story.shortText,
                                      longText: story.longText,
                                      hashtags: List<String>.from(
                                        story.hashtags,
                                      ),
                                      imagePrompt: story.imagePrompt,
                                      imageUrl: uploadedUrl,
                                    ),
                                  );
                                  // Trigger AI copy regeneration using the uploaded design image
                                  await widget.onRegenerateCopyFromDesign(
                                    story.id,
                                  );
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Diseño guardado. Analizando imagen para generar copy alineado...',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(seconds: 5),
                                      ),
                                    );
                                  }
                                },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  MarketingResearchDetail? _findResearch(String? id) {
    final target = (id ?? '').trim();
    if (target.isEmpty) return null;
    for (final item in widget.researches) {
      if (item.id == target) return item;
    }
    return null;
  }
}

class _EstadoRapidoScreen extends StatefulWidget {
  const _EstadoRapidoScreen({
    required this.stories,
    required this.busy,
    required this.onApprove,
    required this.onRetryPublish,
    required this.onRegenerateCopyFromDesign,
    required this.onEdit,
    required this.onUploadDesignImage,
  });

  final List<MarketingStory> stories;
  final bool busy;
  final Future<void> Function(
    String storyId,
    List<MarketingPublishTarget> publishTargets,
  )
  onApprove;
  final Future<void> Function(String storyId) onRetryPublish;
  final Future<void> Function(String storyId) onRegenerateCopyFromDesign;
  final Future<void> Function(MarketingStory story, _EditStoryPayload payload)
  onEdit;
  final Future<String?> Function(BuildContext context)? onUploadDesignImage;

  @override
  State<_EstadoRapidoScreen> createState() => _EstadoRapidoScreenState();
}

class _EstadoRapidoScreenState extends State<_EstadoRapidoScreen> {
  static const _allTargets = <MarketingPublishTarget>[
    MarketingPublishTarget.facebookStory,
    MarketingPublishTarget.instagramStory,
    MarketingPublishTarget.facebookPost,
    MarketingPublishTarget.instagramPost,
  ];

  String? _selectedStoryId;
  bool _running = false;
  String _status = '';
  late Set<MarketingPublishTarget> _selectedPublishTargets;

  @override
  void initState() {
    super.initState();
    if (widget.stories.isNotEmpty) {
      _selectedStoryId = widget.stories.first.id;
    }
    _selectedPublishTargets = _allTargets.toSet();
  }

  MarketingStory? get _selectedStory {
    final id = (_selectedStoryId ?? '').trim();
    if (id.isEmpty) return null;
    for (final item in widget.stories) {
      if (item.id == id) return item;
    }
    return null;
  }

  String _normalizeCopyText(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '';
    return text;
  }

  bool _isRecoverablePublishError(ApiException error) {
    final message = error.message.trim().toLowerCase();
    return message.contains('timeout') ||
        message.contains('tard') ||
        message.contains('en proceso') ||
        message.contains('publicacion en proceso') ||
        message.contains('network_timeout') ||
        message.contains('socket') ||
        message.contains('reintentar');
  }

  Future<void> _publishWithRecovery(
    String storyId,
    List<MarketingPublishTarget> selectedTargets,
  ) async {
    try {
      await widget.onApprove(storyId, selectedTargets);
    } on ApiException catch (error) {
      if (!_isRecoverablePublishError(error)) {
        rethrow;
      }
      if (mounted) {
        setState(
          () => _status = 'Detectado envío parcial, reintentando faltantes...',
        );
      }
      await widget.onRetryPublish(storyId);
    }
  }

  Widget _buildGeneratedCopyPanel(BuildContext context, MarketingStory story) {
    final shortText = _normalizeCopyText(story.shortText);
    final longText = _normalizeCopyText(story.longText);
    final hashtags = story.hashtags
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final hasAnyCopy =
        shortText.isNotEmpty || longText.isNotEmpty || hashtags.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Copy generado',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (!hasAnyCopy)
            Text(
              'Todavía no hay copy generado para esta imagen.\nPulsa "Subir imagen" o "Generar copy".',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (hasAnyCopy && shortText.isNotEmpty) ...[
            Text(
              'Texto principal',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            SelectableText(
              shortText,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
          ],
          if (hasAnyCopy && longText.isNotEmpty) ...[
            Text(
              'Copy largo',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            SelectableText(
              longText,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
          ],
          if (hasAnyCopy && hashtags.isNotEmpty) ...[
            Text(
              'Hashtags',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            SelectableText(
              hashtags
                  .map((tag) => tag.startsWith('#') ? tag : '#$tag')
                  .join(' '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }

  Future<String?> _uploadAndAssignImage(MarketingStory story) async {
    if (widget.onUploadDesignImage == null) {
      throw Exception('No está disponible la subida de imagen en este modo.');
    }
    setState(() => _status = 'Subiendo imagen...');
    final uploadedUrl = await widget.onUploadDesignImage!(context);
    if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
      return null;
    }

    setState(() => _status = 'Guardando imagen en el estado...');
    await widget.onEdit(
      story,
      _EditStoryPayload(
        title: story.title,
        shortText: story.shortText,
        longText: story.longText,
        hashtags: List<String>.from(story.hashtags),
        imagePrompt: story.imagePrompt,
        imageUrl: uploadedUrl.trim(),
      ),
    );
    return uploadedUrl.trim();
  }

  Future<void> _runFullQuickFlow() async {
    final story = _selectedStory;
    if (story == null) return;
    if (_running || widget.busy) return;
    if (_selectedPublishTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un canal para publicar.'),
        ),
      );
      return;
    }

    setState(() {
      _running = true;
      _status = 'Iniciando flujo rápido...';
    });
    try {
      final uploaded = await _uploadAndAssignImage(story);
      if (!mounted) return;
      if (uploaded == null || uploaded.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se subió imagen. Flujo cancelado.')),
        );
        return;
      }

      setState(() => _status = 'Generando copy desde el diseño...');
      await widget.onRegenerateCopyFromDesign(story.id);

      setState(() => _status = 'Publicando en los canales seleccionados...');
      await _publishWithRecovery(story.id, _selectedPublishTargets.toList());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Flujo rápido completado: publicación enviada a los canales seleccionados.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _generateCopyOnly() async {
    final story = _selectedStory;
    if (story == null || _running || widget.busy) return;
    setState(() {
      _running = true;
      _status = 'Generando copy...';
    });
    try {
      await widget.onRegenerateCopyFromDesign(story.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copy generado correctamente.')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _publishAllOnly() async {
    final story = _selectedStory;
    if (story == null || _running || widget.busy) return;
    if (_selectedPublishTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un canal para publicar.'),
        ),
      );
      return;
    }
    setState(() {
      _running = true;
      _status = 'Publicando en los canales seleccionados...';
    });
    try {
      await _publishWithRecovery(story.id, _selectedPublishTargets.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publicación enviada a los canales seleccionados.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _uploadImageOnly() async {
    final story = _selectedStory;
    if (story == null || _running || widget.busy) return;
    setState(() {
      _running = true;
      _status = 'Preparando carga de imagen...';
    });
    try {
      final uploaded = await _uploadAndAssignImage(story);
      if (!mounted) return;
      if (uploaded == null || uploaded.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se seleccionó imagen.')),
        );
        return;
      }

      setState(() => _status = 'Generando copy desde la imagen...');
      await widget.onRegenerateCopyFromDesign(story.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Imagen subida. Copy generado automáticamente.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _selectedStory;

    return Scaffold(
      appBar: AppBar(title: const Text('Estado rápido')),
      body: story == null
          ? const Center(child: Text('No hay estados disponibles para hoy.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Flujo express: subir imagen, generar copy y publicar Story + Post en Facebook e Instagram.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedStoryId,
                  decoration: const InputDecoration(
                    labelText: 'Selecciona el estado',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.stories
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(_storyTypeLabel(item.type)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _running || widget.busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _selectedStoryId = value);
                        },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        story.title.trim().isEmpty
                            ? _storyTypeLabel(story.type)
                            : story.title.trim(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final imageUrl = _resolveFinalImageUrl(story);
                          final imageWidget = imageUrl.isNotEmpty
                              ? SizedBox(
                                  height: 280,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: AspectRatio(
                                      aspectRatio: 9 / 16,
                                      child: _StoryImageView(url: imageUrl),
                                    ),
                                  ),
                                )
                              : Container(
                                  height: 180,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                  ),
                                  child: const Text(
                                    'Aún no hay diseño final subido/generado',
                                  ),
                                );

                          final copyWidget = _buildGeneratedCopyPanel(
                            context,
                            story,
                          );
                          final desktopLike = constraints.maxWidth >= 900;

                          if (!desktopLike) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                imageWidget,
                                const SizedBox(height: 10),
                                copyWidget,
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 240, child: imageWidget),
                              const SizedBox(width: 12),
                              Expanded(child: copyWidget),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Canales de publicación',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Facebook Story'),
                        subtitle: const Text(
                          'Publica como historia en Facebook Page',
                        ),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.facebookStory,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.facebookStory,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.facebookStory,
                                    );
                                  }
                                });
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Instagram Story'),
                        subtitle: const Text(
                          'Publica como historia en Instagram Business',
                        ),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.instagramStory,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.instagramStory,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.instagramStory,
                                    );
                                  }
                                });
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Facebook Post'),
                        subtitle: const Text('Publica en la Facebook Page'),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.facebookPost,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.facebookPost,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.facebookPost,
                                    );
                                  }
                                });
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Instagram Post'),
                        subtitle: const Text(
                          'Publica en el feed del Instagram Business',
                        ),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.instagramPost,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.instagramPost,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.instagramPost,
                                    );
                                  }
                                });
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _running || widget.busy
                          ? null
                          : _uploadImageOnly,
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('Subir imagen'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _running || widget.busy
                          ? null
                          : _generateCopyOnly,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('Generar copy'),
                    ),
                    FilledButton.icon(
                      onPressed: _running || widget.busy
                          ? null
                          : _publishAllOnly,
                      icon: const Icon(Icons.publish_rounded),
                      label: const Text('Publicar ahora'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _running || widget.busy ? null : _runFullQuickFlow,
                  icon: const Icon(Icons.flash_on_rounded),
                  label: const Text('Ejecutar flujo rápido completo'),
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status)),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _EstadoVideoScreen extends StatefulWidget {
  const _EstadoVideoScreen({
    required this.stories,
    required this.busy,
    required this.onApprove,
    required this.onRegenerateCopyFromDesign,
    required this.onEdit,
    required this.onUploadVideo,
  });

  final List<MarketingStory> stories;
  final bool busy;
  final Future<void> Function(
    String storyId,
    List<MarketingPublishTarget> publishTargets,
  )
  onApprove;
  final Future<void> Function(String storyId) onRegenerateCopyFromDesign;
  final Future<void> Function(MarketingStory story, _EditStoryPayload payload)
  onEdit;
  final Future<String?> Function(BuildContext context)? onUploadVideo;

  @override
  State<_EstadoVideoScreen> createState() => _EstadoVideoScreenState();
}

class _EstadoVideoScreenState extends State<_EstadoVideoScreen> {
  static const _defaultTargets = <MarketingPublishTarget>{
    MarketingPublishTarget.facebookPost,
    MarketingPublishTarget.instagramPost,
    MarketingPublishTarget.instagramStory,
  };

  String? _selectedStoryId;
  bool _running = false;
  String _status = '';
  late Set<MarketingPublishTarget> _selectedPublishTargets;

  @override
  void initState() {
    super.initState();
    if (widget.stories.isNotEmpty) {
      _selectedStoryId = widget.stories.first.id;
    }
    _selectedPublishTargets = {..._defaultTargets};
  }

  MarketingStory? get _selectedStory {
    final id = (_selectedStoryId ?? '').trim();
    if (id.isEmpty) return null;
    for (final item in widget.stories) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<String?> _uploadAndAssignVideo(MarketingStory story) async {
    if (widget.onUploadVideo == null) {
      throw Exception('No está disponible la subida de video en este modo.');
    }
    setState(() => _status = 'Subiendo video...');
    final uploadedUrl = await widget.onUploadVideo!(context);
    if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
      return null;
    }

    setState(() => _status = 'Asignando video al estado...');
    await widget.onEdit(
      story,
      _EditStoryPayload(
        title: story.title,
        shortText: story.shortText,
        longText: story.longText,
        hashtags: List<String>.from(story.hashtags),
        imagePrompt: story.imagePrompt,
        imageUrl: uploadedUrl.trim(),
      ),
    );

    setState(() => _status = 'Analizando video y generando copy...');
    await widget.onRegenerateCopyFromDesign(story.id);

    return uploadedUrl.trim();
  }

  Future<void> _uploadVideoOnly() async {
    final story = _selectedStory;
    if (story == null || _running || widget.busy) return;
    setState(() {
      _running = true;
      _status = 'Preparando carga de video...';
    });
    try {
      final uploaded = await _uploadAndAssignVideo(story);
      if (!mounted) return;
      if (uploaded == null || uploaded.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se seleccionó video.')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Video asignado correctamente al estado.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _publishVideoOnly() async {
    final story = _selectedStory;
    if (story == null || _running || widget.busy) return;
    if (_selectedPublishTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un canal para publicar.'),
        ),
      );
      return;
    }
    setState(() {
      _running = true;
      _status = 'Publicando video en canales seleccionados...';
    });
    try {
      await widget.onApprove(story.id, _selectedPublishTargets.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Publicación de video enviada correctamente.'),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _runVideoFlow() async {
    final story = _selectedStory;
    if (story == null || _running || widget.busy) return;
    if (_selectedPublishTargets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un canal para publicar.'),
        ),
      );
      return;
    }

    setState(() {
      _running = true;
      _status = 'Iniciando flujo de video...';
    });
    try {
      final uploaded = await _uploadAndAssignVideo(story);
      if (!mounted) return;
      if (uploaded == null || uploaded.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se subió video. Flujo cancelado.')),
        );
        return;
      }

      setState(() => _status = 'Publicando video en canales seleccionados...');
      await widget.onApprove(story.id, _selectedPublishTargets.toList());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Flujo de video completado: video publicado en canales seleccionados.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${error.message}')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _selectedStory;

    return Scaffold(
      appBar: AppBar(title: const Text('Estado video')),
      body: story == null
          ? const Center(child: Text('No hay estados disponibles para hoy.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Flujo video: subir video vertical y publicar en Story/Post de redes seleccionadas.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedStoryId,
                  decoration: const InputDecoration(
                    labelText: 'Selecciona el estado',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.stories
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(_storyTypeLabel(item.type)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _running || widget.busy
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _selectedStoryId = value);
                        },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        story.title.trim().isEmpty
                            ? _storyTypeLabel(story.type)
                            : story.title.trim(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Copy actual para publicación:',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        story.shortText.trim().isEmpty
                            ? 'Sin texto principal'
                            : story.shortText.trim(),
                      ),
                      if (story.hashtags.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          story.hashtags
                              .map((tag) => tag.startsWith('#') ? tag : '#$tag')
                              .join(' '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Media actual:',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _resolveFinalImageUrl(story).trim().isEmpty
                            ? 'Sin media asignada'
                            : _resolveFinalImageUrl(story).trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      if (_resolveFinalImageUrl(story).trim().isNotEmpty)
                        SizedBox(
                          height: 280,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 9 / 16,
                              child: _StoryMediaView(
                                url: _resolveFinalImageUrl(story).trim(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Canales de publicación',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Facebook Story'),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.facebookStory,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.facebookStory,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.facebookStory,
                                    );
                                  }
                                });
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Instagram Story'),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.instagramStory,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.instagramStory,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.instagramStory,
                                    );
                                  }
                                });
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Facebook Post'),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.facebookPost,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.facebookPost,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.facebookPost,
                                    );
                                  }
                                });
                              },
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Instagram Post'),
                        value: _selectedPublishTargets.contains(
                          MarketingPublishTarget.instagramPost,
                        ),
                        onChanged: _running || widget.busy
                            ? null
                            : (value) {
                                setState(() {
                                  if (value == true) {
                                    _selectedPublishTargets.add(
                                      MarketingPublishTarget.instagramPost,
                                    );
                                  } else {
                                    _selectedPublishTargets.remove(
                                      MarketingPublishTarget.instagramPost,
                                    );
                                  }
                                });
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _running || widget.busy
                          ? null
                          : _uploadVideoOnly,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Subir video'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _running || widget.busy
                          ? null
                          : _publishVideoOnly,
                      icon: const Icon(Icons.publish_rounded),
                      label: const Text('Publicar video'),
                    ),
                    FilledButton.icon(
                      onPressed: _running || widget.busy ? null : _runVideoFlow,
                      icon: const Icon(Icons.smart_display_rounded),
                      label: const Text('Subir y publicar'),
                    ),
                  ],
                ),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status)),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _StoryCard extends StatefulWidget {
  const _StoryCard({
    required this.story,
    required this.phase,
    required this.usedResearch,
    required this.busy,
    required this.imageBusy,
    required this.onApprove,
    required this.onReject,
    required this.onRegenerate,
    required this.onRegenerateImage,
    required this.onConfirmBaseImage,
    required this.onGenerateDesign,
    required this.onChangeBaseImage,
    required this.onEdit,
    required this.onRegenerateCopyFromDesign,
    required this.onRetryPublish,
    required this.mediaAssets,
    this.onUploadFinalDesign,
    this.compactActions = false,
  });

  final MarketingStory story;
  final _EstadosPhase phase;
  final MarketingResearchDetail? usedResearch;
  final bool busy;
  final bool imageBusy;
  final Future<void> Function(List<MarketingPublishTarget> publishTargets)?
  onApprove;
  final Future<void> Function()? onReject;
  final Future<void> Function() onRegenerate;
  final Future<void> Function() onRegenerateImage;
  final Future<void> Function() onConfirmBaseImage;
  final Future<void> Function() onGenerateDesign;
  final Future<void> Function() onChangeBaseImage;
  final Future<void> Function() onEdit;
  final Future<void> Function() onRegenerateCopyFromDesign;
  final Future<void> Function() onRetryPublish;
  final Future<void> Function(BuildContext context)? onUploadFinalDesign;
  final List<MarketingMediaAsset> mediaAssets;
  final bool compactActions;

  @override
  State<_StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<_StoryCard> {
  late Set<MarketingPublishTarget> _selectedPublishTargets;

  @override
  void initState() {
    super.initState();
    _selectedPublishTargets = _defaultPublishTargets(widget.story);
  }

  @override
  void didUpdateWidget(covariant _StoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.story.id != widget.story.id) {
      _selectedPublishTargets = _defaultPublishTargets(widget.story);
    }
  }

  Set<MarketingPublishTarget> _defaultPublishTargets(MarketingStory story) {
    if (story.publishTargets.isNotEmpty) {
      return story.publishTargets.toSet();
    }

    final published = {
      ...story.publishedChannels,
      if ((story.facebookStoryId ?? '').trim().isNotEmpty)
        MarketingPublishTarget.facebookStory,
      if ((story.instagramStoryId ?? '').trim().isNotEmpty)
        MarketingPublishTarget.instagramStory,
      if ((story.facebookPostId ?? '').trim().isNotEmpty)
        MarketingPublishTarget.facebookPost,
      if ((story.instagramPostId ?? '').trim().isNotEmpty)
        MarketingPublishTarget.instagramPost,
    };
    final hasAnyPublished =
        published.isNotEmpty ||
        (story.facebookPostId ?? '').trim().isNotEmpty ||
        (story.facebookStoryId ?? '').trim().isNotEmpty ||
        (story.instagramPostId ?? '').trim().isNotEmpty ||
        (story.instagramStoryId ?? '').trim().isNotEmpty;

    if (hasAnyPublished) {
      return {
        if (!published.contains(MarketingPublishTarget.facebookStory))
          MarketingPublishTarget.facebookStory,
        if (!published.contains(MarketingPublishTarget.instagramStory))
          MarketingPublishTarget.instagramStory,
        if (!published.contains(MarketingPublishTarget.facebookPost))
          MarketingPublishTarget.facebookPost,
        if (!published.contains(MarketingPublishTarget.instagramPost))
          MarketingPublishTarget.instagramPost,
      };
    }

    return {
      MarketingPublishTarget.facebookStory,
      MarketingPublishTarget.instagramStory,
    };
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final validation = validateStoryProgress(story);
    final baseImage = _resolveBaseImageUrl(story);
    final designUploadedImageUrl = _resolveFinalImage(story);
    final phaseIndex = widget.phase.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _MetaChip(label: 'Tipo', value: _storyTypeShort(story.type)),
            const SizedBox(width: 8),
            _StatusPill(status: story.status),
            const SizedBox(width: 8),
            _PublishStatusPill(
              status: story.publishStatus,
              facebookPostId: story.facebookPostId,
              instagramPostId: story.instagramPostId,
              facebookStoryId: story.facebookStoryId,
              instagramStoryId: story.instagramStoryId,
              publishedChannels: story.publishedChannels,
              publishTargets: story.publishTargets,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          story.title.trim().isEmpty ? 'Sin titular' : story.title.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        if (phaseIndex == 0)
          _buildPhase1(context, story, validation, baseImage)
        else if (phaseIndex == 1)
          _buildPhase2(context, story, validation, designUploadedImageUrl)
        else
          _buildPhase3(context, story, validation, designUploadedImageUrl),
      ],
    );
  }

  Widget _buildPhase1(
    BuildContext context,
    MarketingStory story,
    StoryProgressValidation validation,
    String baseImage,
  ) {
    final prompt = story.imagePrompt.trim();
    final hasImage = baseImage.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 56,
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: Image.network(
                        baseImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _BrokenImagePlaceholder(),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: 56,
                  height: 100,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.image_outlined,
                    color: scheme.outline,
                    size: 22,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fase 1: Crear diseño',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasImage
                          ? 'Imagen recomendada por IA'
                          : 'Seleccionando imagen...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: hasImage
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                    if (story.usedResearchAngle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        story.usedResearchAngle.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          prompt.isEmpty
                              ? Icons.hourglass_empty_rounded
                              : Icons.check_circle_rounded,
                          size: 12,
                          color: prompt.isEmpty
                              ? scheme.outline
                              : const Color(0xFF15803D),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          prompt.isEmpty
                              ? 'Generando prompt...'
                              : 'Prompt listo',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: prompt.isEmpty
                                    ? scheme.outline
                                    : const Color(0xFF15803D),
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: (prompt.isEmpty || !hasImage)
                    ? null
                    : () async {
                        final research =
                            story.usedResearchAngle.trim().isNotEmpty
                            ? story.usedResearchAngle
                            : 'Producto/servicio premium de FULLTECH';
                        final objective = story.usedOffer.trim().isNotEmpty
                            ? story.usedOffer
                            : 'Convertir visitantes en clientes';

                        final fullPrompt =
                            '''REFERENCE IMAGE URL:
$baseImage

TASK:
Create a premium vertical 9:16 social media advertisement for FULLTECH SRL in Higüey, Dominican Republic.

IMPORTANT:
Do NOT change the product shown in the reference image.
Do NOT replace the product.
Do NOT redesign the product.
Do NOT alter the product shape, structure, brand, proportions or identity.

The exact product from the reference image must remain identical and recognizable.

ONLY improve:
- lighting
- background
- commercial composition
- cinematic environment
- premium advertising look
- typography areas
- shadows
- reflections
- visual depth
- atmosphere

STYLE:
Modern premium advertising.
Professional commercial photography.
Luxury lighting.
Clean composition.
Strong focal hierarchy.
Dominican market optimized.

Include:
- realistic environment
- elegant gradients
- modern composition
- premium color grading
- social-media-ready design

FORMAT:
Vertical 9:16
Ultra high quality
Modern advertising style

PRODUCT CONTEXT:
$research

COMMERCIAL GOAL:
$objective''';

                        await Clipboard.setData(
                          ClipboardData(text: fullPrompt),
                        );
                        developer.log(
                          '[publicidad-ui] Prompt copiado con URL: $baseImage',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                '✓ Prompt copiado con imagen. Úsalo en ChatGPT.',
                              ),
                              duration: Duration(seconds: 3),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copiar prompt'),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : () => _openImagePicker(context),
                icon: const Icon(Icons.image_search_rounded, size: 16),
                label: const Text('Cambiar imagen'),
              ),
              if (hasImage)
                OutlinedButton.icon(
                  onPressed: () =>
                      _openFullscreenPreview(context, story, baseImage, ''),
                  icon: const Icon(Icons.visibility_rounded, size: 16),
                  label: const Text('Ver imagen'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhase2(
    BuildContext context,
    MarketingStory story,
    StoryProgressValidation validation,
    String designUploadedUrl,
  ) {
    final headline = story.title.trim();
    final copy = story.shortText.trim();
    final cta = story.usedCTA.trim();
    final hashtags = story.hashtags;
    final hasDesign = designUploadedUrl.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fase 2: Diseño final + copy',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (!hasDesign) ...[
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.upload_file_rounded,
                    size: 36,
                    color: scheme.outline,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sube el diseño generado en ChatGPT',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: widget.busy
                        ? null
                        : () => _uploadDesignImage(context),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Subir diseño final'),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 90,
                    child: AspectRatio(
                      aspectRatio: 9 / 16,
                      child: _StoryImageView(url: designUploadedUrl),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (headline.isNotEmpty)
                        _InfoLine(label: 'Headline', value: headline),
                      if (copy.isNotEmpty)
                        _InfoLine(label: 'Copy', value: copy),
                      if (cta.isNotEmpty) _InfoLine(label: 'CTA', value: cta),
                      if (hashtags.isNotEmpty)
                        _InfoLine(label: 'Tags', value: hashtags.join(' ')),
                      if (headline.isEmpty && copy.isEmpty && cta.isEmpty)
                        Text(
                          'Generando copy...',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: widget.busy
                      ? null
                      : widget.onRegenerateCopyFromDesign,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Regenerar copy'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => _uploadDesignImage(context),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('Cambiar diseño'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.busy ? null : widget.onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Editar'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openFullscreenPreview(
                    context,
                    story,
                    designUploadedUrl,
                    '',
                  ),
                  icon: const Icon(Icons.open_in_full_rounded, size: 16),
                  label: const Text('Ver completo'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhase3(
    BuildContext context,
    MarketingStory story,
    StoryProgressValidation validation,
    String designUploadedUrl,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final publishDetails = story.publishErrorDetails;
    final failedChannel = '${publishDetails['channel'] ?? ''}'
        .trim()
        .toLowerCase();
    final publishedChannels = story.publishedChannels.toSet();
    final requestedChannels = _selectedPublishTargets;
    final facebookStoryStatusValue = (story.facebookStoryStatus ?? '')
        .trim()
        .toUpperCase();
    final instagramStoryStatusValue = (story.instagramStoryStatus ?? '')
        .trim()
        .toUpperCase();
    final facebookPostStatusValue = (story.facebookPostStatus ?? '')
        .trim()
        .toUpperCase();
    final instagramPostStatusValue = (story.instagramPostStatus ?? '')
        .trim()
        .toUpperCase();
    final hasFacebookStoryPublished =
        publishedChannels.contains(MarketingPublishTarget.facebookStory) ||
        ((story.facebookStoryId ?? '').trim().isNotEmpty &&
            facebookStoryStatusValue != 'ERROR' &&
            facebookStoryStatusValue != 'UNSUPPORTED');
    final hasFacebookPostPublished =
        publishedChannels.contains(MarketingPublishTarget.facebookPost) ||
        ((story.facebookPostId ?? '').trim().isNotEmpty &&
            facebookPostStatusValue != 'ERROR');
    final hasFacebookPublished =
        hasFacebookStoryPublished || hasFacebookPostPublished;
    final hasInstagramPostPublished =
        publishedChannels.contains(MarketingPublishTarget.instagramPost) ||
        ((story.instagramPostId ?? '').trim().isNotEmpty &&
            instagramPostStatusValue != 'ERROR');
    final hasInstagramStoryPublished =
        publishedChannels.contains(MarketingPublishTarget.instagramStory) ||
        ((story.instagramStoryId ?? '').trim().isNotEmpty &&
            instagramStoryStatusValue != 'ERROR' &&
            instagramStoryStatusValue != 'UNKNOWN_VERIFY');
    final hasInstagramPublished =
        hasInstagramPostPublished || hasInstagramStoryPublished;
    final anyPublished = hasFacebookPublished || hasInstagramPublished;
    final requestedInstagram =
        requestedChannels.contains(MarketingPublishTarget.instagramPost) ||
        requestedChannels.contains(MarketingPublishTarget.instagramStory);
    final hasPublishError =
        !anyPublished &&
        (story.publishStatus == MarketingPublishStatus.error ||
            story.publishStatus == MarketingPublishStatus.partial);
    final showPartialInfo =
        !hasPublishError &&
        (story.publishStatus == MarketingPublishStatus.partial ||
            (hasFacebookStoryPublished &&
                requestedChannels.contains(
                  MarketingPublishTarget.instagramStory,
                ) &&
                !hasInstagramStoryPublished) ||
            (hasFacebookPublished &&
                requestedInstagram &&
                !hasInstagramPublished));
    final retryLabel = failedChannel == 'instagram'
        ? 'Reintentar Instagram'
        : failedChannel == 'facebook'
        ? 'Reintentar Facebook'
        : 'Reintentar publicación';
    final selectedTargets = _selectedPublishTargets.toList(growable: false);
    final showFacebookStoryChannelError =
        facebookStoryStatusValue == 'ERROR' ||
        facebookStoryStatusValue == 'UNSUPPORTED';
    final showInstagramStoryUnknownVerify =
        instagramStoryStatusValue == 'UNKNOWN_VERIFY';
    final instagramStoryDetails = _technicalChannelResult(
      story,
      MarketingPublishTarget.instagramStory,
    );
    final instagramStoryPermalink = _technicalValue(
      instagramStoryDetails,
      'permalink',
    );
    final facebookStoryDetails = _technicalChannelResult(
      story,
      MarketingPublishTarget.facebookStory,
    );
    final facebookStoryPhotoId = _technicalValue(
      facebookStoryDetails,
      'photoId',
    );
    final hasTechnicalDetails = story.publishErrorDetails.isNotEmpty;
    final hasDesign = designUploadedUrl.isNotEmpty;
    final alreadyPublishedMessages = <String>[
      if (_selectedPublishTargets.contains(
            MarketingPublishTarget.facebookStory,
          ) &&
          (story.facebookStoryId ?? '').trim().isNotEmpty)
        'Facebook Story ya fue publicada. No se volverá a enviar automáticamente.',
      if (_selectedPublishTargets.contains(
            MarketingPublishTarget.instagramStory,
          ) &&
          (story.instagramStoryId ?? '').trim().isNotEmpty)
        'Instagram Story ya fue publicada. No se volverá a enviar automáticamente.',
      if (_selectedPublishTargets.contains(
            MarketingPublishTarget.facebookPost,
          ) &&
          (story.facebookPostId ?? '').trim().isNotEmpty)
        'Facebook Post ya fue publicado. No se volverá a enviar automáticamente.',
      if (_selectedPublishTargets.contains(
            MarketingPublishTarget.instagramPost,
          ) &&
          (story.instagramPostId ?? '').trim().isNotEmpty)
        'Instagram Post ya fue publicado. No se volverá a enviar automáticamente.',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fase 3: Publicar',
            style: textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 430;
              final previewWidth = wide ? 130.0 : 112.0;
              final preview = ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: previewWidth,
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: hasDesign
                        ? _StoryImageView(url: designUploadedUrl)
                        : Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: scheme.outline,
                              size: 28,
                            ),
                          ),
                  ),
                ),
              );

              final summary = Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Checklist previo',
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final item in validation.checklist.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                item.value
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked,
                                color: item.value
                                    ? const Color(0xFF15803D)
                                    : const Color(0xFFB45309),
                                size: 14,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.key,
                                style: textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (story.shortText.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _InfoLine(
                        label: 'Copy',
                        value: story.shortText.trim(),
                        maxLines: 3,
                      ),
                    ],
                    if (story.usedCTA.trim().isNotEmpty)
                      _InfoLine(label: 'CTA', value: story.usedCTA.trim()),
                  ],
                ),
              );

              if (!wide) {
                return Column(
                  children: [
                    Center(child: preview),
                    const SizedBox(height: 10),
                    summary,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  preview,
                  const SizedBox(width: 12),
                  Expanded(child: summary),
                ],
              );
            },
          ),
          if (story.status == MarketingStoryStatus.approved &&
              hasFacebookPublished) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFDFF7E8),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF49A36D)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasFacebookStoryPublished
                        ? 'Facebook Story publicado correctamente'
                        : 'Publicado en Facebook correctamente',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0E5F33),
                    ),
                  ),
                  if ((story.facebookPostId ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID Facebook Post: ${story.facebookPostId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if ((story.facebookStoryId ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID Facebook Story: ${story.facebookStoryId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if ((facebookStoryPhotoId ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID foto base: $facebookStoryPhotoId',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (story.status == MarketingStoryStatus.approved &&
              hasInstagramPublished) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF4A90E2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Publicado en Instagram correctamente',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0D47A1),
                    ),
                  ),
                  if ((story.instagramPostId ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID Instagram Post: ${story.instagramPostId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if ((story.instagramStoryId ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID Instagram Story: ${story.instagramStoryId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      instagramStoryPermalink != null
                          ? 'Meta devolvió enlace para esta Story.'
                          : 'Instagram Story enviada a Meta. Puede tardar unos segundos en aparecer.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (instagramStoryPermalink != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _openExternalUrl(context, instagramStoryPermalink),
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('Ver en Instagram'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (showInstagramStoryUnknownVerify) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2A63A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Instagram Story con verificación incierta',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF8A5A00),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Meta devolvió un resultado que no confirma una Story real. Revisa los detalles técnicos antes de asumir que quedó visible.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          if (showPartialInfo) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2A63A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasInstagramStoryPublished &&
                            requestedChannels.contains(
                              MarketingPublishTarget.facebookStory,
                            ) &&
                            !hasFacebookStoryPublished
                        ? 'Instagram Story publicada correctamente. Facebook Story no se pudo completar.'
                        : hasFacebookPublished &&
                              requestedInstagram &&
                              !hasInstagramPublished
                        ? 'Publicado en Facebook, pendiente/error en Instagram'
                        : 'Publicado parcialmente',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF8A5A00),
                    ),
                  ),
                  if ((story.instagramPostId ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID Instagram Post: ${story.instagramPostId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if ((story.instagramStoryId ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'ID Instagram Story: ${story.instagramStoryId}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (showFacebookStoryChannelError) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: facebookStoryStatusValue == 'UNSUPPORTED'
                    ? const Color(0xFFFFF7E6)
                    : const Color(0xFFFFEAEA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: facebookStoryStatusValue == 'UNSUPPORTED'
                      ? const Color(0xFFE2A63A)
                      : const Color(0xFFE57373),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    facebookStoryStatusValue == 'UNSUPPORTED'
                        ? 'Facebook Story no soportado'
                        : 'Error en Facebook Story',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: facebookStoryStatusValue == 'UNSUPPORTED'
                          ? const Color(0xFF8A5A00)
                          : const Color(0xFF8E1C1C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (story.facebookStoryError ??
                            'Meta no devolvió detalle para Facebook Story.')
                        .trim(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          if (hasPublishError) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: story.publishStatus == MarketingPublishStatus.partial
                    ? const Color(0xFFFFF7E6)
                    : const Color(0xFFFFEAEA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: story.publishStatus == MarketingPublishStatus.partial
                      ? const Color(0xFFE2A63A)
                      : const Color(0xFFE57373),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    story.publishStatus == MarketingPublishStatus.partial
                        ? 'Publicado parcialmente'
                        : 'Error al publicar',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color:
                          story.publishStatus == MarketingPublishStatus.partial
                          ? const Color(0xFF8A5A00)
                          : const Color(0xFF8E1C1C),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (story.publishError ?? 'No se recibió detalle de error.')
                        .trim(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _openPublishErrorDetail(context, story),
                      icon: const Icon(Icons.info_outline_rounded, size: 16),
                      label: const Text('Ver detalles técnicos'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Canales de publicación',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                _buildPublishTargetCheckbox(
                  context,
                  target: MarketingPublishTarget.facebookStory,
                  label: 'Facebook Story',
                  subtitle: 'Publica como historia en Facebook Page',
                ),
                _buildPublishTargetCheckbox(
                  context,
                  target: MarketingPublishTarget.instagramStory,
                  label: 'Instagram Story',
                  subtitle: 'Publica como historia en Instagram Business',
                ),
                _buildPublishTargetCheckbox(
                  context,
                  target: MarketingPublishTarget.facebookPost,
                  label: 'Facebook Post',
                  subtitle: 'Publica en la Facebook Page',
                ),
                _buildPublishTargetCheckbox(
                  context,
                  target: MarketingPublishTarget.instagramPost,
                  label: 'Instagram Post',
                  subtitle: 'Publica en el feed del Instagram Business',
                ),
                if (alreadyPublishedMessages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final message in alreadyPublishedMessages)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF8A5A00),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (hasTechnicalDetails && !hasPublishError) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _openPublishErrorDetail(context, story),
                icon: const Icon(Icons.analytics_outlined, size: 16),
                label: const Text('Ver detalles técnicos'),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed:
                    widget.busy ||
                        !validation.canApprove ||
                        widget.onApprove == null ||
                        selectedTargets.isEmpty
                    ? null
                    : () => widget.onApprove!(selectedTargets),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.publish_rounded, size: 16),
                label: const Text('Publicar'),
              ),
              if ((story.publishStatus == MarketingPublishStatus.partial ||
                      story.publishStatus == MarketingPublishStatus.error) &&
                  story.publishStatus != MarketingPublishStatus.published)
                FilledButton.tonalIcon(
                  onPressed: widget.busy ? null : widget.onRetryPublish,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text(retryLabel),
                ),
              OutlinedButton(
                onPressed: widget.busy || widget.onReject == null
                    ? null
                    : widget.onReject,
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: const Text('Rechazar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPublishTargetCheckbox(
    BuildContext context, {
    required MarketingPublishTarget target,
    required String label,
    required String subtitle,
  }) {
    return CheckboxListTile(
      value: _selectedPublishTargets.contains(target),
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(label),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      onChanged: (value) {
        setState(() {
          if (value == true) {
            _selectedPublishTargets.add(target);
          } else {
            _selectedPublishTargets.remove(target);
          }
        });
      },
    );
  }

  Future<void> _openPublishErrorDetail(
    BuildContext context,
    MarketingStory story,
  ) async {
    final details = story.publishErrorDetails;
    final rawChannelErrors = details['channelErrors'];
    final firstChannelError =
        rawChannelErrors is List &&
            rawChannelErrors.isNotEmpty &&
            rawChannelErrors.first is Map
        ? (rawChannelErrors.first as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final fallbackChannel = '${firstChannelError['channel'] ?? ''}'.trim();
    final fallbackStage = '${firstChannelError['stage'] ?? ''}'.trim();
    final fallbackMessage = '${firstChannelError['message'] ?? ''}'.trim();
    final fallbackCode = '${firstChannelError['code'] ?? ''}'.trim();
    final fallbackSubcode = '${firstChannelError['subcode'] ?? ''}'.trim();
    final fallbackFbtraceId =
        '${firstChannelError['fbtraceId'] ?? firstChannelError['fbtrace_id'] ?? ''}'
            .trim();
    final channel = '${details['channel'] ?? ''}'.trim();
    final stage = '${details['stage'] ?? ''}'.trim();
    final message = '${details['message'] ?? story.publishError ?? ''}'.trim();
    final code = story.publishErrorCode ?? '${details['code'] ?? ''}'.trim();
    final subcode = '${details['subcode'] ?? ''}'.trim();
    final fbtraceId = '${details['fbtraceId'] ?? details['fbtrace_id'] ?? ''}'
        .trim();
    final happenedAt = '${details['happenedAt'] ?? ''}'.trim();
    final technicalJson = _prettyJson(details);
    final resolvedChannel = channel.isEmpty || channel == 'unknown'
        ? fallbackChannel
        : channel;
    final resolvedStage = stage.isEmpty || stage == 'post-publish-check'
        ? fallbackStage
        : stage;
    final resolvedMessage =
        message.isEmpty || message == 'An unknown error has occurred.'
        ? (fallbackMessage.isEmpty ? message : fallbackMessage)
        : message;
    final resolvedCode = code.isEmpty ? fallbackCode : code;
    final resolvedSubcode = subcode.isEmpty ? fallbackSubcode : subcode;
    final resolvedFbtraceId = fbtraceId.isEmpty ? fallbackFbtraceId : fbtraceId;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detalles técnicos Meta'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(
                  label: 'Canal fallido',
                  value: resolvedChannel.isEmpty ? '-' : resolvedChannel,
                ),
                _InfoLine(
                  label: 'Etapa',
                  value: resolvedStage.isEmpty ? '-' : resolvedStage,
                ),
                _InfoLine(
                  label: 'Mensaje',
                  value: resolvedMessage.isEmpty ? '-' : resolvedMessage,
                  maxLines: 5,
                ),
                _InfoLine(
                  label: 'Código Meta',
                  value: resolvedCode.isEmpty ? '-' : resolvedCode,
                ),
                _InfoLine(
                  label: 'Subcódigo',
                  value: resolvedSubcode.isEmpty ? '-' : resolvedSubcode,
                ),
                _InfoLine(
                  label: 'fbtrace_id',
                  value: resolvedFbtraceId.isEmpty ? '-' : resolvedFbtraceId,
                ),
                _InfoLine(
                  label: 'Fecha/hora',
                  value: happenedAt.isEmpty
                      ? _formatDateTime(story.updatedAt)
                      : happenedAt,
                ),
                const SizedBox(height: 12),
                Text(
                  'Rastro técnico',
                  style: Theme.of(dialogContext).textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    technicalJson,
                    style: Theme.of(
                      dialogContext,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            },
            child: const Text('Cerrar'),
          ),
          FilledButton.icon(
            onPressed: widget.busy
                ? null
                : () async {
                    if (Navigator.of(dialogContext).canPop()) {
                      Navigator.of(dialogContext).pop();
                    }
                    if (!mounted) return;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      unawaited(widget.onRetryPublish());
                    });
                  },
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  void _openImagePicker(BuildContext context) {
    widget.onChangeBaseImage();
  }

  Map<String, dynamic> _technicalChannelResult(
    MarketingStory story,
    MarketingPublishTarget target,
  ) {
    final rawResults = story.publishErrorDetails['channelResults'];
    if (rawResults is! Map) return const <String, dynamic>{};
    final raw = rawResults[publishTargetApiValue(target)];
    if (raw is! Map) return const <String, dynamic>{};
    return raw.cast<String, dynamic>();
  }

  String? _technicalValue(Map<String, dynamic> raw, String key) {
    final value = '${raw[key] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }

  String _prettyJson(Map<String, dynamic> value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }

  Future<void> _openExternalUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    await safeOpenUrl(
      context,
      uri,
      copiedMessage: 'No se pudo abrir el enlace. URL copiada.',
    );
  }

  Future<String?> _openFilePickerAndUpload(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📤 Seleccionando archivo...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al subir: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  void _uploadDesignImage(BuildContext context) {
    if (widget.onUploadFinalDesign != null) {
      widget.onUploadFinalDesign!(context);
    } else {
      widget.onEdit();
    }
  }

  void _openFullscreenPreview(
    BuildContext context,
    MarketingStory story,
    String imageUrl,
    String baseImage,
  ) {
    if (imageUrl.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Vista previa'),
          content: const Text('Sin imagen disponible.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: SizedBox(
          width: 500,
          height: 900,
          child: _StoryFullscreenPreview(story: story, imageUrl: imageUrl),
        ),
      ),
    );
  }

  void _openStoryDetails(
    BuildContext context,
    MarketingStory story,
    MarketingResearchDetail? usedResearch,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Detalles del anuncio'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoLine(label: 'ID', value: story.id),
                _InfoLine(label: 'Tipo', value: _storyTypeLabel(story.type)),
                _InfoLine(label: 'Estado', value: story.status.toString()),
                if (usedResearch != null) const SizedBox(height: 8),
                if (usedResearch != null)
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.science_rounded),
                    label: const Text('Ver investigación usada'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _resolveFinalImage(MarketingStory story) {
    return _resolveFinalImageUrl(story);
  }
}

String _resolveStoryCopy(
  MarketingStory story, {
  required List<String> keys,
  String fallback = '-',
}) {
  final metadata = story.imageGenerationMetadata;

  String fromMap(Map<String, dynamic> map, String key) {
    final value = '${map[key] ?? ''}'.trim();
    return value;
  }

  for (final key in keys) {
    final value = fromMap(metadata, key);
    if (value.isNotEmpty) return value;
  }

  final copiesRaw = metadata['copies'];
  if (copiesRaw is Map) {
    final copies = copiesRaw.cast<String, dynamic>();
    for (final key in keys) {
      final value = '${copies[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
  }

  if (keys.any(
    (key) =>
        key.toLowerCase().contains('facebook') ||
        key.toLowerCase().contains('instagram') ||
        key.toLowerCase().contains('marketplace'),
  )) {
    final short = story.shortText.trim();
    if (short.isNotEmpty) return short;
  }

  if (fallback.isNotEmpty) return fallback;
  return '-';
}

bool _isImageStatusLoading(MarketingImageStatus status) {
  return status == MarketingImageStatus.queued ||
      status == MarketingImageStatus.processing;
}

class StoryProgressValidation {
  const StoryProgressValidation({
    required this.missingBaseImage,
    required this.missingImageConfirmation,
    required this.missingDesign,
    required this.missingCopy,
    required this.missingCTA,
    required this.canGenerateDesign,
    required this.canGenerateCopy,
    required this.canApprove,
    required this.missingResearch,
    required this.checklist,
  });

  final bool missingBaseImage;
  final bool missingImageConfirmation;
  final bool missingDesign;
  final bool missingCopy;
  final bool missingCTA;
  final bool canGenerateDesign;
  final bool canGenerateCopy;
  final bool canApprove;
  final bool missingResearch;
  final Map<String, bool> checklist;

  List<String> get missingForApproval {
    final missing = <String>[];
    if (missingBaseImage) missing.add('imagen base');
    if (missingDesign) missing.add('diseño generado');
    if (missingCopy) missing.add('copy generado');
    if (missingCTA) missing.add('CTA');
    if (missingResearch) missing.add('investigación usada');
    return missing;
  }

  String get currentPhaseLabel {
    if (canApprove) return 'Fase 3: Publicar';
    if (!missingDesign) return 'Fase 2: Copys y anuncio';
    return 'Fase 1: Crear diseño';
  }

  String get nextStepLabel {
    if (missingBaseImage) return 'Seleccionar imagen de Galería de contenido';
    if (missingDesign) return 'Generar diseño 9:16';
    if (missingCopy || missingCTA) return 'Generar copys del anuncio';
    if (missingResearch) return 'Vincular investigación aprobada';
    return 'Publicar';
  }
}

StoryProgressValidation validateStoryProgress(MarketingStory story) {
  // Fase 1: Imagen base + prompt
  final hasBaseImage = _resolveBaseImageUrl(story).isNotEmpty;
  final hasPrompt = story.imagePrompt.trim().isNotEmpty;
  final phase1Complete = hasBaseImage && hasPrompt;

  // Fase 2: Diseño generado o subido + copies
  final hasGeneratedOrUploadedDesign = _resolveFinalImageUrl(story).isNotEmpty;
  final headline = story.title.trim();
  final copy = story.shortText.trim();
  final cta = story.usedCTA.trim();
  final hasCopies = headline.isNotEmpty || copy.isNotEmpty || cta.isNotEmpty;
  final phase2Complete = hasGeneratedOrUploadedDesign && hasCopies;

  // Fase 3: Aprobado
  final isApproved = story.status == MarketingStoryStatus.approved;

  final canApprove = phase1Complete && phase2Complete;

  return StoryProgressValidation(
    missingBaseImage: !hasBaseImage,
    missingImageConfirmation: false,
    missingDesign: !hasGeneratedOrUploadedDesign,
    missingCopy: !hasCopies,
    missingCTA: cta.isEmpty,
    canGenerateDesign: phase1Complete,
    canGenerateCopy: phase2Complete,
    canApprove: canApprove,
    missingResearch: false,
    checklist: {
      'Imagen base seleccionada': hasBaseImage,
      'Prompt generado': hasPrompt,
      'Diseño generado/subido': hasGeneratedOrUploadedDesign,
      'Copys generados': hasCopies,
      'Aprobado': isApproved,
    },
  );
}

String _storyImageError(MarketingStory story) {
  final metadata = story.imageGenerationMetadata;
  if (metadata.isEmpty) return '';
  const keys = ['lastError', 'reason', 'error', 'retryReason', 'providerError'];
  for (final key in keys) {
    final raw = '${metadata[key] ?? ''}'.trim();
    if (raw.isNotEmpty) return _compactImageError(raw);
  }
  return '';
}

String _compactImageError(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('billing_hard_limit_reached') ||
      lower.contains('billing hard limit has been reached')) {
    return 'Límite de facturación OpenAI agotado. Configura Stability AI (STABILITY_API_KEY).';
  }
  if (lower.contains('stability_api_key') ||
      lower.contains('stability ai') ||
      (lower.contains('no hay proveedor') && lower.contains('configurado'))) {
    return 'No hay proveedor de imágenes configurado. Agrega STABILITY_API_KEY o OPENAI_API_KEY.';
  }
  if (lower.contains('openai') && lower.contains('api key')) {
    return 'El proveedor de imagen no esta configurado correctamente.';
  }
  if (raw.length > 220) {
    return '${raw.substring(0, 220).trim()}...';
  }
  return raw;
}

class _StoryImageView extends StatelessWidget {
  const _StoryImageView({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:image/') && url.contains(';base64,')) {
      try {
        final payload = url.split(';base64,').last;
        return _StoryImageCanvas(
          child: Image.memory(
            base64Decode(payload),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
          ),
        );
      } catch (_) {
        return const _BrokenImagePlaceholder();
      }
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return _StoryImageCanvas(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
        ),
      );
    }

    return const _BrokenImagePlaceholder();
  }
}

class _StoryImageCanvas extends StatelessWidget {
  const _StoryImageCanvas({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF08111F), Color(0xFF14253F)],
        ),
      ),
      child: Center(
        child: Padding(padding: const EdgeInsets.all(10), child: child),
      ),
    );
  }
}

class _StoryMediaView extends StatelessWidget {
  const _StoryMediaView({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (_isVideoMediaUrl(url)) {
      return _StoryVideoView(url: url);
    }
    return _StoryImageView(url: url);
  }
}

class _StoryVideoView extends StatefulWidget {
  const _StoryVideoView({required this.url});

  final String url;

  @override
  State<_StoryVideoView> createState() => _StoryVideoViewState();
}

class _StoryVideoViewState extends State<_StoryVideoView> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;

  @override
  void initState() {
    super.initState();
    _initController(widget.url);
  }

  @override
  void didUpdateWidget(covariant _StoryVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _disposeController();
      _initController(widget.url);
    }
  }

  void _initController(String rawUrl) {
    final source = rawUrl.trim();
    if (source.isEmpty ||
        !(source.startsWith('http://') || source.startsWith('https://'))) {
      return;
    }
    final controller = VideoPlayerController.networkUrl(Uri.parse(source));
    _controller = controller;
    _initializeFuture = controller.initialize().then((_) {
      if (!mounted) return;
      controller
        ..setLooping(true)
        ..setVolume(0)
        ..play();
      setState(() {});
    });
  }

  void _disposeController() {
    final current = _controller;
    _controller = null;
    _initializeFuture = null;
    current?.dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final future = _initializeFuture;
    if (controller == null || future == null) {
      return const _BrokenImagePlaceholder();
    }

    return _StoryImageCanvas(
      child: FutureBuilder<void>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              controller.value.isInitialized) {
            return Stack(
              fit: StackFit.expand,
              children: [
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
                const Positioned(
                  right: 8,
                  top: 8,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
              ],
            );
          }
          if (snapshot.hasError) {
            return const _BrokenImagePlaceholder();
          }
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
      ),
    );
  }
}

class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1B2A), Color(0xFF1a2744)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x2200B4D8),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0x9900B4D8),
              size: 36,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Imagen pendiente',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Genera imagen para activar',
            style: TextStyle(color: Color(0xFF475569), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _DesignNotReadyPlaceholder extends StatelessWidget {
  const _DesignNotReadyPlaceholder({this.isLoading = false});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1B2A), Color(0xFF0f2232)],
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLoading
                ? Icons.hourglass_top_rounded
                : Icons.image_not_supported_outlined,
            color: const Color(0x8800B4D8),
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            isLoading
                ? 'Generando dise\u00f1o...'
                : 'A\u00fan no hay dise\u00f1o final',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final text = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: text),
          ],
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ResearchSummaryTab extends StatelessWidget {
  const _ResearchSummaryTab({
    required this.dashboard,
    required this.latestResearch,
    required this.researchHistory,
    required this.learningStats,
    required this.busy,
    required this.onForceResearch,
  });

  final MarketingDashboard? dashboard;
  final MarketingResearchDetail? latestResearch;
  final List<MarketingResearchDetail> researchHistory;
  final MarketingLearningStats? learningStats;
  final bool busy;
  final Future<void> Function() onForceResearch;

  @override
  Widget build(BuildContext context) {
    final research = latestResearch;
    if (research == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No hay investigación todavía. El sistema la generará automáticamente o puedes forzarla manualmente.',
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: busy ? null : onForceResearch,
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('Generar investigación manual'),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cerebro comercial de Publicidad',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Solo insights de venta local para publicar mejor y vender mas rapido.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: researchHistory.isEmpty
                    ? null
                    : () {
                        showDialog<void>(
                          context: context,
                          builder: (_) =>
                              _ResearchHistoryDialog(items: researchHistory),
                        );
                      },
                icon: const Icon(Icons.history_rounded),
                label: const Text('Ver historial de investigaciones'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onForceResearch,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Actualizar inteligencia'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: 'Estado', value: research.status),
              _MetaChip(
                label: 'Fecha investigación',
                value: _formatDate(research.date),
              ),
              _MetaChip(
                label: 'Fuente usada',
                value: research.dataSources.isEmpty
                    ? '-'
                    : research.dataSources.take(3).join(', '),
              ),
              _MetaChip(
                label: 'Confianza',
                value:
                    '${(research.confidenceScore * 100).toStringAsFixed(0)}%',
              ),
              _MetaChip(
                label: 'Tema investigado',
                value: research.mainFocus.isEmpty ? '-' : research.mainFocus,
              ),
              _MetaChip(
                label: 'Frecuencia',
                value: 'Cada ${dashboard?.researchFrequencyDays ?? 7} días',
              ),
              _MetaChip(
                label: 'Próxima auto',
                value: _formatDateTime(dashboard?.nextAutoResearch),
              ),
              _MetaChip(
                label: 'Radio servicio',
                value: '${dashboard?.serviceRadiusKm ?? 25} km',
              ),
              _MetaChip(
                label: 'Zona',
                value: dashboard?.serviceZone ?? 'Higüey, La Altagracia',
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 980;
              final cardWidth = twoCols
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _ResearchBlockCard(
                      title: 'Que mas esta funcionando',
                      icon: Icons.local_fire_department_rounded,
                      items: _extractBulletItems(
                        research.marketSummary,
                        fallback: research.doMoreOfThis,
                        max: 6,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ResearchBlockCard(
                      title: 'Quienes estan comprando',
                      icon: Icons.groups_rounded,
                      items: _extractAudienceItems(research),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ResearchBlockCard(
                      title: 'Objeciones mas comunes',
                      icon: Icons.report_problem_rounded,
                      items: _extractObjectionItems(research),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ResearchBlockCard(
                      title: 'Ofertas que mas responden',
                      icon: Icons.sell_rounded,
                      items: _extractBulletItems(
                        research.commonOffers,
                        fallback: research.recommendedOffers,
                        max: 6,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ResearchBlockCard(
                      title: 'Contenido que mas llama',
                      icon: Icons.play_circle_fill_rounded,
                      items: _extractBulletItems(
                        research.contentOpportunities,
                        fallback: research.recommendedContentTypes,
                        max: 6,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _ResearchBlockCard(
                      title: 'Angulos de venta recomendados',
                      icon: Icons.ads_click_rounded,
                      items: research.strongAngles.isEmpty
                          ? const ['Sin angulos detectados aun.']
                          : research.strongAngles
                                .take(6)
                                .toList(growable: false),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _TodayContentSection(research: research),
          const SizedBox(height: 12),
          Text(
            'Memorias/aprendizajes activos',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (learningStats == null || learningStats!.topInsights.isEmpty)
            const Text('No hay memorias activas todavía.')
          else
            Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaChip(
                      label: 'Activas',
                      value: '${learningStats!.activeCount}',
                    ),
                    _MetaChip(
                      label: 'Descartadas',
                      value: '${learningStats!.discardedCount}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final insight in learningStats!.topInsights)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '- [${insight.category}] ${insight.insight} (score ${insight.score.toStringAsFixed(2)})',
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ResearchBlockCard extends StatelessWidget {
  const _ResearchBlockCard({
    required this.title,
    required this.icon,
    required this.items,
  });

  final String title;
  final IconData icon;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in items.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• ${item.trim()}'),
            ),
        ],
      ),
    );
  }
}

class _TodayContentSection extends StatelessWidget {
  const _TodayContentSection({required this.research});

  final MarketingResearchDetail research;

  @override
  Widget build(BuildContext context) {
    final statusText = _firstNonEmpty(
      research.recommendedHooks,
      fallback:
          'Protege tu negocio desde tu celular. Instalacion rapida en Higuey. Escribenos ahora.',
    );
    final videoIdea = _firstNonEmpty(
      _extractBulletItems(
        research.contentOpportunities,
        fallback: research.recommendedContentTypes,
        max: 10,
      ),
      fallback:
          'Tecnico instalando, camara funcionando, vista en celular y cliente validando grabacion.',
    );
    final cta = _firstNonEmpty(
      research.recommendedCTAs,
      fallback: 'Escribenos por WhatsApp ahora',
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFECFEF3),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contenido recomendado hoy',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF166534),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Estado recomendado',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('"$statusText"'),
          const SizedBox(height: 10),
          Text(
            'Idea de video',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('• $videoIdea'),
          const SizedBox(height: 10),
          Text(
            'CTA recomendado: $cta',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF14532D),
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _extractBulletItems(
  String value, {
  List<String> fallback = const [],
  int max = 6,
}) {
  final normalized = value
      .replaceAll('\r', '\n')
      .replaceAll('|', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.replaceFirst(RegExp(r'^[\-•\*\d\.\)\s]+'), '').trim())
      .where((line) => line.length > 3)
      .where((line) => !RegExp(r'^[A-Z0-9\s:]{6,}$').hasMatch(line))
      .toList(growable: false);

  final selected = normalized.take(max).toList(growable: false);
  if (selected.isNotEmpty) return selected;
  if (fallback.isNotEmpty) {
    return fallback
        .take(max)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const ['Sin evidencia suficiente en esta corrida.'];
}

List<String> _extractAudienceItems(MarketingResearchDetail research) {
  final fromSummary = _extractBulletItems(research.marketSummary, max: 8);
  final audience = fromSummary
      .where(
        (line) =>
            line.toLowerCase().contains('negocio') ||
            line.toLowerCase().contains('residenc') ||
            line.toLowerCase().contains('tienda') ||
            line.toLowerCase().contains('colmado') ||
            line.toLowerCase().contains('farmacia'),
      )
      .take(6)
      .toList(growable: false);
  if (audience.isNotEmpty) return audience;
  return const [
    'Colmados y tiendas pequenas',
    'Farmacias y repuestos',
    'Negocios con caja y flujo de clientes',
    'Residencias nuevas',
  ];
}

List<String> _extractObjectionItems(MarketingResearchDetail research) {
  final candidates = [
    ..._extractBulletItems(research.competitorPublishingPatterns, max: 10),
    ...research.weakAngles,
  ];
  final filtered = candidates
      .where(
        (item) =>
            item.toLowerCase().contains('garantia') ||
            item.toLowerCase().contains('instalacion') ||
            item.toLowerCase().contains('precio') ||
            item.toLowerCase().contains('celular') ||
            item.toLowerCase().contains('pago') ||
            item.toLowerCase().contains('cuota'),
      )
      .take(6)
      .toList(growable: false);

  if (filtered.isNotEmpty) return filtered;
  return const [
    'Tiene garantia?',
    'Incluye instalacion?',
    'Funciona desde el celular?',
    'Hay facilidades de pago?',
  ];
}

String _firstNonEmpty(List<String> items, {required String fallback}) {
  for (final item in items) {
    final trimmed = item.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return fallback;
}

class _ResearchHistoryDialog extends StatelessWidget {
  const _ResearchHistoryDialog({required this.items});

  final List<MarketingResearchDetail> items;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Historial de investigaciones'),
      content: SizedBox(
        width: 760,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final item = items[index];
            return ListTile(
              title: Text(
                item.mainFocus.isEmpty
                    ? 'Investigación sin tema'
                    : item.mainFocus,
              ),
              subtitle: Text(
                '${_formatDate(item.date)} · ${item.status} · ${(item.confidenceScore * 100).toStringAsFixed(0)}%',
              ),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => _ResearchDetailDialog(research: item),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ResearchDetailDialog extends StatelessWidget {
  const _ResearchDetailDialog({required this.research});

  final MarketingResearchDetail research;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Detalle comercial de investigación'),
      content: SizedBox(
        width: 840,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaChip(
                    label: 'Fecha',
                    value: _formatDateTime(research.createdAt ?? research.date),
                  ),
                  _MetaChip(label: 'Estado', value: research.status),
                  _MetaChip(
                    label: 'Confianza',
                    value:
                        '${(research.confidenceScore * 100).toStringAsFixed(0)}%',
                  ),
                  _MetaChip(
                    label: 'Tema',
                    value: research.mainFocus.trim().isEmpty
                        ? '-'
                        : research.mainFocus,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ResearchBlockCard(
                title: 'Insights rapidos de mercado',
                icon: Icons.insights_rounded,
                items: _extractBulletItems(research.marketSummary, max: 8),
              ),
              const SizedBox(height: 8),
              _ResearchBlockCard(
                title: 'Competidores y objeciones',
                icon: Icons.track_changes_rounded,
                items: _extractObjectionItems(research),
              ),
              const SizedBox(height: 8),
              _ResearchBlockCard(
                title: 'Ofertas y CTA recomendados',
                icon: Icons.campaign_rounded,
                items: [
                  ...research.recommendedOffers.take(4),
                  ...research.recommendedCTAs.take(3),
                ],
              ),
              const SizedBox(height: 8),
              _ResearchBlockCard(
                title: 'Contenido listo para publicar',
                icon: Icons.auto_awesome_rounded,
                items: [
                  ...research.recommendedHooks.take(3),
                  ...research.recommendedContentTypes.take(3),
                ],
              ),
              const SizedBox(height: 8),
              _ResearchBlockCard(
                title: 'Fuentes resumidas',
                icon: Icons.public_rounded,
                items: research.dataSources.isEmpty
                    ? const ['Sin fuentes registradas.']
                    : research.dataSources.take(6).toList(growable: false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _GalleryTab extends ConsumerStatefulWidget {
  const _GalleryTab({
    required this.assets,
    required this.publishedAssets,
    required this.busy,
    required this.onCreateAssets,
    required this.onToggleActive,
    required this.onToggleFeatured,
    required this.onUpdateMeta,
    required this.onDelete,
  });

  final List<MarketingMediaAsset> assets;
  final List<MarketingPublishedAsset> publishedAssets;
  final bool busy;
  final Future<void> Function(List<MarketingMediaAssetDraft> drafts)
  onCreateAssets;
  final Future<void> Function(MarketingMediaAsset asset) onToggleActive;
  final Future<void> Function(MarketingMediaAsset asset) onToggleFeatured;
  final Future<void> Function(
    MarketingMediaAsset asset, {
    required String category,
    required String relatedService,
    required String tagsCsv,
    required String description,
  })
  onUpdateMeta;
  final Future<void> Function(MarketingMediaAsset asset) onDelete;

  @override
  ConsumerState<_GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends ConsumerState<_GalleryTab> {
  String _filterCategory = 'Todos';
  String _segment = 'ALL';
  bool _showImporter = false;
  String _importMode = 'PRODUCTS';
  String _productSearch = '';
  Set<String> _selectedProductIds = <String>{};
  Future<List<ProductModel>>? _catalogFuture;
  late final TextEditingController _manualUrl;
  late final TextEditingController _manualName;
  late final TextEditingController _manualService;
  late final TextEditingController _manualDescription;
  late final TextEditingController _manualTags;
  String _manualCategory = 'Cámaras de seguridad';

  static const _categories = [
    'Motores de portones',
    'Cámaras de seguridad',
    'Cercos eléctricos',
    'Intercoms',
    'Alarmas',
    'POS',
    'Instalaciones reales',
    'Equipo técnico',
    'Tienda física',
    'Clientes / trabajos realizados',
    'Tecnología general',
  ];

  @override
  void initState() {
    super.initState();
    _manualUrl = TextEditingController();
    _manualName = TextEditingController();
    _manualService = TextEditingController();
    _manualDescription = TextEditingController();
    _manualTags = TextEditingController(
      text: 'explorador-archivo, galeria-publicidad',
    );
  }

  @override
  void dispose() {
    _manualUrl.dispose();
    _manualName.dispose();
    _manualService.dispose();
    _manualDescription.dispose();
    _manualTags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categoryFiltered = _filterCategory == 'Todos'
        ? widget.assets
        : widget.assets
              .where((item) => item.category == _filterCategory)
              .toList(growable: false);

    final visible = categoryFiltered
        .where((item) {
          if (_segment == 'ALL') return true;
          if (_segment == 'ACTIVE') return item.isActive;
          if (_segment == 'INACTIVE') return !item.isActive;
          if (_segment == 'FEATURED') return item.isFeatured;
          if (_segment == 'GENERATED') return _isGenerated(item);
          if (_segment == 'MANUAL') return !_isGenerated(item);
          if (_segment == 'SELECTED_MANUAL') {
            return !_isGenerated(item) && item.useCount > 0;
          }
          return true;
        })
        .toList(growable: false);

    final published = widget.publishedAssets;
    final total = widget.assets.length;
    final active = widget.assets.where((item) => item.isActive).length;
    final generated = widget.assets.where(_isGenerated).length;
    final withoutImage = widget.assets
        .where((item) => _resolveAssetPreviewUrl(item).isEmpty)
        .length;

    final galleryContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final dropdownWidth = constraints.maxWidth < 480
                ? constraints.maxWidth
                : 280.0;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: dropdownWidth,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _filterCategory,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                    items: ['Todos', ..._categories]
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(e, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (v) =>
                        setState(() => _filterCategory = v ?? 'Todos'),
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.busy ? null : () => _openImporter('MANUAL'),
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: const Text('Agregar imagen'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.busy
                      ? null
                      : () => _openImporter('PRODUCTS'),
                  icon: const Icon(Icons.inventory_2_rounded),
                  label: const Text('Agregar desde productos'),
                ),
                if (_showImporter)
                  TextButton.icon(
                    onPressed: widget.busy ? null : _closeImporter,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cerrar panel'),
                  ),
                _MetaChip(label: 'Disponibles', value: '${visible.length}'),
                _MetaChip(label: 'Publicadas', value: '${published.length}'),
                _MetaChip(label: 'Total', value: '$total'),
                _MetaChip(label: 'Activas', value: '$active'),
                _MetaChip(label: 'Generadas', value: '$generated'),
                _MetaChip(label: 'Sin preview', value: '$withoutImage'),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _segmentButton('ALL', 'Todas'),
            _segmentButton('ACTIVE', 'Activas'),
            _segmentButton('INACTIVE', 'Inactivas'),
            _segmentButton('FEATURED', 'Destacadas'),
            _segmentButton('GENERATED', 'Generadas'),
            _segmentButton('MANUAL', 'Manuales'),
            _segmentButton('SELECTED_MANUAL', 'Seleccionadas manual'),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Imágenes disponibles para publicidad',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'La IA usa esta galería como fuente de imágenes base. Aquí puedes subir imágenes manuales o importar productos de la empresa.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const _EmptyState(text: 'No hay imágenes en la galería publicitaria.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in visible)
                SizedBox(
                  width: 260,
                  child: _GalleryAssetCard(
                    asset: item,
                    busy: widget.busy,
                    onToggleActive: () => widget.onToggleActive(item),
                    onToggleFeatured: () => widget.onToggleFeatured(item),
                    onEditMeta: () async {
                      final payload = await showDialog<_EditAssetMetaPayload>(
                        context: context,
                        builder: (_) => _EditAssetMetaDialog(asset: item),
                      );
                      if (payload == null) return;
                      await widget.onUpdateMeta(
                        item,
                        category: payload.category,
                        relatedService: payload.relatedService,
                        tagsCsv: payload.tagsCsv,
                        description: payload.description,
                      );
                    },
                    onDelete: () => widget.onDelete(item),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 14),
        Text(
          'Imágenes publicadas',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (published.isEmpty)
          const _EmptyState(
            text: 'Aún no hay anuncios aprobados para publicar en esta lista.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in published)
                SizedBox(width: 280, child: _PublishedAssetCard(item: item)),
            ],
          ),
      ],
    );

    if (!_showImporter) {
      return galleryContent;
    }

    final importer = _GalleryImporterPanel(
      title: _importMode == 'MANUAL'
          ? 'Agregar imagen manual'
          : 'Agregar productos a la galería',
      child: _importMode == 'MANUAL'
          ? _buildManualImporter(context)
          : _buildProductsImporter(context),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 1180;
        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: galleryContent),
              const SizedBox(width: 16),
              SizedBox(width: 380, child: importer),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [galleryContent, const SizedBox(height: 12), importer],
        );
      },
    );
  }

  void _openImporter(String mode) {
    setState(() {
      _showImporter = true;
      _importMode = mode;
    });
    if (mode == 'PRODUCTS') {
      _catalogFuture ??= ref
          .read(catalogRepositoryProvider)
          .fetchProducts(silent: true);
    }
  }

  void _closeImporter() {
    setState(() {
      _showImporter = false;
      _selectedProductIds = <String>{};
    });
  }

  Widget _buildManualImporter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _manualUrl,
          decoration: const InputDecoration(
            labelText: 'URL de imagen',
            hintText: 'https://.../imagen.jpg',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _manualName,
          decoration: const InputDecoration(
            labelText: 'Nombre de archivo',
            hintText: 'camara-bullet-hikvision.jpg',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _manualCategory,
          decoration: const InputDecoration(
            labelText: 'Categoría',
            isDense: true,
          ),
          items: _categories
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(growable: false),
          onChanged: widget.busy
              ? null
              : (value) =>
                    setState(() => _manualCategory = value ?? _manualCategory),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _manualService,
          decoration: const InputDecoration(
            labelText: 'Servicio o producto relacionado',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _manualTags,
          decoration: const InputDecoration(
            labelText: 'Tags',
            hintText: 'producto, galeria-publicidad',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _manualDescription,
          minLines: 3,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.busy ? null : _createManualAsset,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar en galería'),
          ),
        ),
      ],
    );
  }

  Widget _buildProductsImporter(BuildContext context) {
    _catalogFuture ??= ref
        .read(catalogRepositoryProvider)
        .fetchProducts(silent: true);

    return FutureBuilder<List<ProductModel>>(
      future: _catalogFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('No se pudo cargar la lista de productos.'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _catalogFuture = ref
                        .read(catalogRepositoryProvider)
                        .fetchProducts(silent: true);
                  });
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Reintentar'),
              ),
            ],
          );
        }

        final importedUrls = _importedUrls();
        final products =
            (snapshot.data ?? const <ProductModel>[])
                .where(
                  (product) =>
                      product.activo && _productImageUrl(product).isNotEmpty,
                )
                .where((product) {
                  final query = _productSearch.trim().toLowerCase();
                  if (query.isEmpty) return true;
                  final haystack = [
                    product.nombre,
                    product.codigo ?? '',
                    product.categoria ?? '',
                  ].join(' ').toLowerCase();
                  return haystack.contains(query);
                })
                .toList(growable: false)
              ..sort((a, b) {
                final aImported = importedUrls.contains(_productImageUrl(a));
                final bImported = importedUrls.contains(_productImageUrl(b));
                if (aImported != bImported) return aImported ? 1 : -1;
                return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
              });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: (value) => setState(() => _productSearch = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Buscar producto',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetaChip(label: 'Con foto', value: '${products.length}'),
                _MetaChip(
                  label: 'Seleccionados',
                  value: '${_selectedProductIds.length}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 520,
              child: products.isEmpty
                  ? const _EmptyState(
                      text: 'No hay productos con imagen para importar.',
                    )
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final imageUrl = _productImageUrl(product);
                        final imported = importedUrls.contains(imageUrl);
                        final selected = _selectedProductIds.contains(
                          product.id,
                        );
                        return InkWell(
                          onTap: imported || widget.busy
                              ? null
                              : () => setState(() {
                                  if (selected) {
                                    _selectedProductIds.remove(product.id);
                                  } else {
                                    _selectedProductIds.add(product.id);
                                  }
                                }),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 74,
                                    height: 74,
                                    child: Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const _BrokenImagePlaceholder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.nombre,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _MetaChip(
                                            label: 'Galería',
                                            value: imported
                                                ? 'Ya agregado'
                                                : 'Disponible',
                                          ),
                                          _MetaChip(
                                            label: 'Categoría',
                                            value: _productCategory(product),
                                          ),
                                          _MetaChip(
                                            label: 'Código',
                                            value:
                                                (product.codigo ?? '')
                                                    .trim()
                                                    .isEmpty
                                                ? '-'
                                                : product.codigo!.trim(),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Checkbox(
                                  value: imported ? true : selected,
                                  onChanged: imported || widget.busy
                                      ? null
                                      : (_) => setState(() {
                                          if (selected) {
                                            _selectedProductIds.remove(
                                              product.id,
                                            );
                                          } else {
                                            _selectedProductIds.add(product.id);
                                          }
                                        }),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.busy || _selectedProductIds.isEmpty
                    ? null
                    : () => _importSelectedProducts(products),
                icon: const Icon(Icons.playlist_add_check_circle_rounded),
                label: const Text('Agregar seleccionados a la galería'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createManualAsset() async {
    final url = _manualUrl.text.trim();
    final fileName = _manualName.text.trim();
    if (url.isEmpty || fileName.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Debes indicar URL y nombre de archivo.')),
      );
      return;
    }
    await widget.onCreateAssets([
      MarketingMediaAssetDraft(
        fileUrl: url,
        fileName: fileName,
        category: _manualCategory,
        relatedService: _manualService.text.trim(),
        description: _manualDescription.text.trim(),
        tags: _manualTags.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false),
      ),
    ]);
    if (!mounted) return;
    _manualUrl.clear();
    _manualName.clear();
    _manualService.clear();
    _manualDescription.clear();
    _manualTags.text = 'explorador-archivo, galeria-publicidad';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('Imagen agregada a la galería publicitaria.'),
      ),
    );
  }

  Future<void> _importSelectedProducts(List<ProductModel> products) async {
    final importedUrls = _importedUrls();
    final drafts = products
        .where((product) => _selectedProductIds.contains(product.id))
        .map((product) {
          final imageUrl = _productImageUrl(product);
          if (imageUrl.isEmpty || importedUrls.contains(imageUrl)) {
            return null;
          }
          final descriptionParts = <String>[
            if ((product.descripcion ?? '').trim().isNotEmpty)
              product.descripcion!.trim(),
            if ((product.codigo ?? '').trim().isNotEmpty)
              'Codigo: ${product.codigo!.trim()}',
          ];
          return MarketingMediaAssetDraft(
            fileUrl: imageUrl,
            fileName: _productFileName(product),
            category: _productCategory(product),
            relatedService: product.nombre.trim(),
            description: descriptionParts.join(' · '),
            tags: _productTags(product),
          );
        })
        .whereType<MarketingMediaAssetDraft>()
        .toList(growable: false);

    if (drafts.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No hay productos nuevos para importar.')),
      );
      return;
    }
    await widget.onCreateAssets(drafts);
    if (!mounted) return;
    setState(() => _selectedProductIds = <String>{});
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text('${drafts.length} producto(s) agregados a la galería.'),
      ),
    );
  }

  Set<String> _importedUrls() {
    return widget.assets
        .map((asset) => asset.fileUrl.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String _productImageUrl(ProductModel product) {
    return (product.displayFotoUrl ?? product.fotoUrl ?? '').trim();
  }

  String _productCategory(ProductModel product) {
    final name = product.nombre.toLowerCase();
    if (name.contains('motor') ||
        name.contains('porton') ||
        name.contains('portón')) {
      return 'Motores de portones';
    }
    if (name.contains('camara') ||
        name.contains('cámara') ||
        name.contains('dvr') ||
        name.contains('nvr') ||
        name.contains('cctv') ||
        name.contains('domo') ||
        name.contains('bullet') ||
        name.contains('bala')) {
      return 'Cámaras de seguridad';
    }
    if (name.contains('cerco') || name.contains('electrico')) {
      return 'Cercos eléctricos';
    }
    if (name.contains('intercom') ||
        name.contains('videoportero') ||
        name.contains('portero')) {
      return 'Intercoms';
    }
    if (name.contains('alarma')) {
      return 'Alarmas';
    }
    if (name.contains('pos') ||
        name.contains('impresora') ||
        name.contains('scanner')) {
      return 'POS';
    }
    return 'Tecnología general';
  }

  List<String> _productTags(ProductModel product) {
    final tags = <String>{
      'producto',
      'catalogo',
      'imagen-producto',
      'galeria-publicidad',
      _productCategory(product).toLowerCase(),
    };
    final code = (product.codigo ?? '').trim();
    if (code.isNotEmpty) {
      tags.add(code.toLowerCase());
    }
    return tags.toList(growable: false);
  }

  String _productFileName(ProductModel product) {
    final imageUrl = _productImageUrl(product);
    var extension = '.jpg';
    final parsed = Uri.tryParse(imageUrl);
    if (parsed != null) {
      final path = parsed.path.toLowerCase();
      final dot = path.lastIndexOf('.');
      if (dot >= 0) {
        extension = path.substring(dot);
      }
    }
    final safeName = product.nombre
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final base = safeName.isEmpty ? 'producto-${product.id}' : safeName;
    return '$base$extension';
  }

  bool _isGenerated(MarketingMediaAsset asset) {
    final sourceType = (asset.sourceType ?? '').toUpperCase();
    if (sourceType == 'GENERATED_AI') return true;
    final url = asset.fileUrl.toLowerCase();
    final name = asset.fileName.toLowerCase();
    final tags = asset.tags.map((item) => item.toLowerCase());
    return url.contains('/marketing/generated/') ||
        name.startsWith('ai-') ||
        tags.any(
          (item) =>
              item == 'ia' ||
              item == 'ai' ||
              item == 'generada' ||
              item == 'generated',
        );
  }

  String _resolveAssetPreviewUrl(MarketingMediaAsset asset) {
    final file = _safeImageUrl(asset.fileUrl);
    if (file.isNotEmpty) return file;
    return _safeImageUrl(asset.thumbnailUrl);
  }

  Widget _segmentButton(String value, String label) {
    final selected = _segment == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => setState(() => _segment = value),
    );
  }
}

class _GalleryImporterPanel extends StatelessWidget {
  const _GalleryImporterPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Todo lo que agregues aquí entra a la galería y queda disponible para que la IA lo use en Publicidad.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PublishedAssetCard extends StatelessWidget {
  const _PublishedAssetCard({required this.item});

  final MarketingPublishedAsset item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _resolveImageUrl(item);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: imageUrl.isEmpty
                  ? const _BrokenImagePlaceholder()
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _BrokenImagePlaceholder(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaChip(
                label: 'Tipo',
                value: _storyTypeLabelFromCode(item.storyType),
              ),
              _MetaChip(label: 'Estado', value: item.status),
              _MetaChip(
                label: 'Aprobado',
                value: _formatDateTime(item.approvedAt),
              ),
              _MetaChip(
                label: 'CTA',
                value: item.cta.trim().isEmpty ? '-' : item.cta.trim(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showStoryPreview(context, item),
            icon: const Icon(Icons.open_in_full_rounded),
            label: const Text('Ver anuncio'),
          ),
        ],
      ),
    );
  }

  String _resolveImageUrl(MarketingPublishedAsset item) {
    final generated = _safeImageUrl(item.generatedImageUrl);
    if (generated.isNotEmpty) return generated;
    final storyImage = _safeImageUrl(item.imageUrl);
    if (storyImage.isNotEmpty) return storyImage;
    final fromAsset = _safeImageUrl(item.mediaAsset?.fileUrl);
    if (fromAsset.isNotEmpty) return fromAsset;
    final thumb = _safeImageUrl(item.mediaAsset?.thumbnailUrl);
    if (thumb.isNotEmpty) return thumb;
    return '';
  }

  String _storyTypeLabelFromCode(String rawType) {
    switch (rawType.toUpperCase()) {
      case 'SALES':
        return 'Venta';
      case 'TRUST':
        return 'Confianza';
      case 'EDUCATIONAL':
        return 'Educativo';
      default:
        return rawType.trim().isEmpty ? 'General' : rawType.trim();
    }
  }

  void _showStoryPreview(BuildContext context, MarketingPublishedAsset item) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Anuncio publicado'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 9 / 16,
                child: _resolveImageUrl(item).isEmpty
                    ? const _BrokenImagePlaceholder()
                    : Image.network(
                        _resolveImageUrl(item),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _BrokenImagePlaceholder(),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                item.headline,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(item.shortText),
              const SizedBox(height: 6),
              Text(item.cta),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}

class _GalleryAssetCard extends StatelessWidget {
  const _GalleryAssetCard({
    required this.asset,
    required this.busy,
    required this.onToggleActive,
    required this.onToggleFeatured,
    required this.onEditMeta,
    required this.onDelete,
  });

  final MarketingMediaAsset asset;
  final bool busy;
  final Future<void> Function() onToggleActive;
  final Future<void> Function() onToggleFeatured;
  final Future<void> Function() onEditMeta;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final previewUrl = _safeImageUrl(asset.fileUrl).isNotEmpty
        ? _safeImageUrl(asset.fileUrl)
        : _safeImageUrl(asset.thumbnailUrl);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: previewUrl.isEmpty
                  ? const _BrokenImagePlaceholder()
                  : Image.network(
                      previewUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const _BrokenImagePlaceholder(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            asset.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MetaChip(label: 'Categoría', value: asset.category),
              _MetaChip(
                label: 'Estado',
                value: asset.isActive ? 'Activa' : 'Inactiva',
              ),
              _MetaChip(
                label: 'Origen',
                value: (asset.sourceType ?? 'MANUAL_UPLOAD') == 'GENERATED_AI'
                    ? 'IA'
                    : 'Manual',
              ),
              _MetaChip(label: 'Servicio', value: asset.relatedService ?? '-'),
              _MetaChip(
                label: 'Tags',
                value: asset.tags.isEmpty ? '-' : asset.tags.join(', '),
              ),
              _MetaChip(label: 'Uso', value: '${asset.useCount}'),
              _MetaChip(
                label: 'Último uso',
                value: _formatDateTime(asset.lastUsedAt),
              ),
              _MetaChip(
                label: 'Usada en anuncio',
                value: asset.latestStoryTitle ?? '-',
              ),
              _MetaChip(
                label: 'Tipo anuncio',
                value: asset.latestStoryType ?? '-',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton(
                onPressed: busy ? null : onToggleActive,
                child: Text(asset.isActive ? 'Desactivar' : 'Activar'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onToggleFeatured,
                child: Text(asset.isFeatured ? 'Quitar destacada' : 'Destacar'),
              ),
              OutlinedButton(
                onPressed: busy ? null : onEditMeta,
                child: const Text('Editar metadata'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Eliminar imagen'),
                            content: const Text(
                              'Solo se eliminará si no está en uso por anuncios históricos.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          WidgetsBinding.instance.addPostFrameCallback((
                            _,
                          ) async {
                            if (!context.mounted) return;
                            await onDelete();
                          });
                        }
                      },
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditAssetMetaPayload {
  const _EditAssetMetaPayload({
    required this.category,
    required this.relatedService,
    required this.tagsCsv,
    required this.description,
  });

  final String category;
  final String relatedService;
  final String tagsCsv;
  final String description;
}

class _EditAssetMetaDialog extends StatefulWidget {
  const _EditAssetMetaDialog({required this.asset});

  final MarketingMediaAsset asset;

  @override
  State<_EditAssetMetaDialog> createState() => _EditAssetMetaDialogState();
}

class _EditAssetMetaDialogState extends State<_EditAssetMetaDialog> {
  late final TextEditingController _category;
  late final TextEditingController _relatedService;
  late final TextEditingController _tags;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    _category = TextEditingController(text: widget.asset.category);
    _relatedService = TextEditingController(
      text: widget.asset.relatedService ?? '',
    );
    _tags = TextEditingController(text: widget.asset.tags.join(', '));
    _description = TextEditingController(text: widget.asset.description ?? '');
  }

  @override
  void dispose() {
    _category.dispose();
    _relatedService.dispose();
    _tags.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar metadata de imagen'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _category,
              decoration: const InputDecoration(labelText: 'Categoría'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _relatedService,
              decoration: const InputDecoration(
                labelText: 'Servicio relacionado',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tags,
              decoration: const InputDecoration(
                labelText: 'Tags (coma separada)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descripción'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _EditAssetMetaPayload(
              category: _category.text.trim(),
              relatedService: _relatedService.text.trim(),
              tagsCsv: _tags.text.trim(),
              description: _description.text.trim(),
            ),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _PickMediaAssetDialog extends StatefulWidget {
  const _PickMediaAssetDialog({required this.assets, this.selectedId});

  final List<MarketingMediaAsset> assets;
  final String? selectedId;

  @override
  State<_PickMediaAssetDialog> createState() => _PickMediaAssetDialogState();
}

class _PickMediaAssetDialogState extends State<_PickMediaAssetDialog> {
  late String? _selectedId;
  String _search = '';
  String? _category;
  String _originFilter = 'ALL';
  String _stateFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  Widget build(BuildContext context) {
    final galleryAssets = widget.assets
        .where((item) => item.fileUrl.trim().isNotEmpty)
        .toList(growable: false);
    final categories =
        galleryAssets
            .map((item) => item.category.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final search = _search.trim().toLowerCase();
    final visible = galleryAssets
        .where((item) {
          if (_category != null && item.category != _category) return false;
          if (_originFilter != 'ALL' && _originKey(item) != _originFilter) {
            return false;
          }
          if (_stateFilter == 'PUBLISHED' && !_isPublishedState(item)) {
            return false;
          }
          if (search.isEmpty) return true;
          return item.fileName.toLowerCase().contains(search) ||
              item.category.toLowerCase().contains(search) ||
              (item.relatedService ?? '').toLowerCase().contains(search) ||
              item.tags.any((tag) => tag.toLowerCase().contains(search));
        })
        .toList(growable: false);

    MarketingMediaAsset? selected;
    for (final item in visible) {
      if (item.id == _selectedId) {
        selected = item;
        break;
      }
    }
    if (selected == null) {
      for (final item in galleryAssets) {
        if (item.id == _selectedId) {
          selected = item;
          break;
        }
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: SizedBox(
        width: 1100,
        height: 760,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Seleccionar desde Galería de contenido',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Para este flujo solo se permite seleccionar imágenes de esta galería de contenido.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre, categoría, servicio o tag',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('Todas'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null),
                    ),
                    const SizedBox(width: 8),
                    for (final category in categories) ...[
                      ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('Todo estado'),
                      selected: _stateFilter == 'ALL',
                      onSelected: (_) => setState(() => _stateFilter = 'ALL'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Publicado'),
                      selected: _stateFilter == 'PUBLISHED',
                      onSelected: (_) =>
                          setState(() => _stateFilter = 'PUBLISHED'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('Todos los orígenes'),
                      selected: _originFilter == 'ALL',
                      onSelected: (_) => setState(() => _originFilter = 'ALL'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Imagen de productos'),
                      selected: _originFilter == 'PRODUCT_IMAGE',
                      onSelected: (_) =>
                          setState(() => _originFilter = 'PRODUCT_IMAGE'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Imagen de galería'),
                      selected: _originFilter == 'GALLERY_IMAGE',
                      onSelected: (_) =>
                          setState(() => _originFilter = 'GALLERY_IMAGE'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Explorador de archivo'),
                      selected: _originFilter == 'FILE_EXPLORER',
                      onSelected: (_) =>
                          setState(() => _originFilter = 'FILE_EXPLORER'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: visible.isEmpty
                          ? const Center(
                              child: Text(
                                'No hay contenido autorizado en Galería de contenido. Agrega imágenes desde Publicidad > Galería de contenido.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10,
                                    childAspectRatio: 0.78,
                                  ),
                              itemCount: visible.length,
                              itemBuilder: (context, index) {
                                final item = visible[index];
                                final isSelected = item.id == _selectedId;
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () =>
                                      setState(() => _selectedId = item.id),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.outlineVariant,
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(11),
                                                ),
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: _buildAssetPreview(
                                                item,
                                                BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8),
                                          child: Text(
                                            item.relatedService
                                                        ?.trim()
                                                        .isNotEmpty ==
                                                    true
                                                ? item.relatedService!.trim()
                                                : item.fileName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: selected == null
                            ? const Center(
                                child: Text(
                                  'Selecciona una imagen para ver preview.',
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: _buildAssetPreview(
                                          selected,
                                          BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    selected.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Categoría: ${selected.category}'),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Descripción: ${(selected.description ?? '').trim().isEmpty ? 'Sin descripción' : selected.description!.trim()}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tags: ${selected.tags.isEmpty ? 'Sin tags' : selected.tags.join(', ')}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text('Origen: ${_originLabel(selected)}'),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Uso recomendado: ${(selected.relatedService ?? '').trim().isEmpty ? selected.category : selected.relatedService!.trim()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: () => Navigator.of(
                                        context,
                                      ).pop(selected!.id),
                                      icon: const Icon(Icons.check_rounded),
                                      label: const Text('Usar esta imagen'),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetPreview(MarketingMediaAsset item, BoxFit fit) {
    if (_isVideoAsset(item)) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1F3B), Color(0xFF102A4C)],
          ),
        ),
        child: const Center(
          child: Icon(
            Icons.play_circle_fill_rounded,
            size: 56,
            color: Color(0xFF67E8F9),
          ),
        ),
      );
    }

    return Image.network(
      item.fileUrl,
      fit: fit,
      errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
    );
  }

  bool _isVideoAsset(MarketingMediaAsset item) {
    return item.mimeType.toLowerCase().startsWith('video/');
  }

  String _originLabel(MarketingMediaAsset item) {
    switch (_originKey(item)) {
      case 'PRODUCT_IMAGE':
        return 'Imagen de productos';
      case 'FILE_EXPLORER':
        return 'Explorador de archivo';
      case 'GALLERY_IMAGE':
      default:
        return 'Imagen de galería';
    }
  }

  String _originKey(MarketingMediaAsset item) {
    final raw = (item.sourceType ?? '').trim().toUpperCase();
    if (raw == 'PRODUCT_IMAGE') return 'PRODUCT_IMAGE';
    if (raw == 'FILE_EXPLORER') return 'FILE_EXPLORER';
    if (raw == 'GALLERY_IMAGE') return 'GALLERY_IMAGE';

    final tags = item.tags
        .map((tag) => tag.toLowerCase())
        .toList(growable: false);
    if (tags.contains('catalogo') || tags.contains('imagen-producto')) {
      return 'PRODUCT_IMAGE';
    }
    if (tags.contains('explorador-archivo') || tags.contains('manual-upload')) {
      return 'FILE_EXPLORER';
    }
    return 'GALLERY_IMAGE';
  }

  bool _isPublishedState(MarketingMediaAsset item) {
    final tags = item.tags
        .map((tag) => tag.toLowerCase())
        .toList(growable: false);
    if (tags.contains('estado-publicado')) return true;
    if (tags.contains('origen:estado_diario')) return true;
    if (tags.contains('usado-en:estados')) return true;
    return item.category.toLowerCase().contains('estado publicado');
  }
}

class _SelectGenerationImagesDialog extends StatefulWidget {
  const _SelectGenerationImagesDialog({required this.assets});

  final List<MarketingMediaAsset> assets;

  @override
  State<_SelectGenerationImagesDialog> createState() =>
      _SelectGenerationImagesDialogState();
}

class _SelectGenerationImagesDialogState
    extends State<_SelectGenerationImagesDialog> {
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final visibleAssets = widget.assets
        .where((asset) {
          final url = asset.fileUrl.trim();
          return url.isNotEmpty;
        })
        .toList(growable: false);

    return AlertDialog(
      title: const Text('Selecciona hasta 3 imágenes'),
      content: SizedBox(
        width: 840,
        child: visibleAssets.isEmpty
            ? const Text('No hay imágenes activas para usar como referencia.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elige 1, 2 o 3 imágenes. El sistema las usará como referencia para crear la publicidad.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Scrollbar(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: visibleAssets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final asset = visibleAssets[index];
                          final selected = _selected.contains(asset.id);
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                if (selected) {
                                  _selected.remove(asset.id);
                                  return;
                                }
                                if (_selected.length >= 3) return;
                                _selected.add(asset.id);
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: SizedBox(
                                      width: 68,
                                      height: 68,
                                      child: Image.network(
                                        asset.fileUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                              Icons.image_not_supported_rounded,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          asset.relatedService
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? asset.relatedService!.trim()
                                              : asset.fileName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          asset.category,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Checkbox(
                                    value: selected,
                                    onChanged: (_) {
                                      setState(() {
                                        if (selected) {
                                          _selected.remove(asset.id);
                                          return;
                                        }
                                        if (_selected.length >= 3) return;
                                        _selected.add(asset.id);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Seleccionadas: ${_selected.length}/3',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_selected.toList(growable: false)),
          icon: const Icon(Icons.auto_fix_high_rounded),
          label: const Text('Generar'),
        ),
      ],
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.items});

  final List<MarketingStory> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(text: 'Sin actividad reciente en historial.');
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          for (final item in items)
            ListTile(
              leading: _StatusPill(status: item.status),
              title: Text(item.title),
              subtitle: Text(
                '${_formatDate(item.date)} · ${_storyTypeLabel(item.type)} · Regenerado: ${item.regeneratedCount}x',
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.approvedByUserName.trim().isNotEmpty)
                    Text(
                      item.approvedByUserName,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  Text(
                    item.approvedAt != null
                        ? 'Aprobado: ${_formatDateTime(item.approvedAt)}'
                        : item.rejectedAt != null
                        ? 'Rechazado: ${_formatDateTime(item.rejectedAt)}'
                        : 'Sin decisión',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ConfigTab extends StatefulWidget {
  const _ConfigTab({
    required this.config,
    required this.busy,
    required this.onSave,
  });

  final MarketingFlowConfig? config;
  final bool busy;
  final Future<void> Function(MarketingFlowConfig config) onSave;

  @override
  State<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<_ConfigTab> {
  late final TextEditingController _count = TextEditingController();
  late final TextEditingController _hour = TextEditingController();
  late final TextEditingController _regenerateHours = TextEditingController();
  late final TextEditingController _priorityProducts = TextEditingController();
  late final TextEditingController _targetCity = TextEditingController();
  late final TextEditingController _brandTone = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _activeVal = false;
  bool _pausedVal = false;
  bool _autoRegenerateVal = false;

  @override
  void initState() {
    super.initState();
    if (widget.config != null) {
      _activeVal = widget.config!.active;
      _pausedVal = widget.config!.paused;
      _autoRegenerateVal = widget.config!.autoRegenerate;
      _count.text = widget.config!.dailyStoriesCount.toString();
      _hour.text = widget.config!.generationTime;
      _regenerateHours.text = widget.config!.regenerateAfterHours.toString();
      _priorityProducts.text = widget.config!.priorityProducts.join(', ');
      _targetCity.text = widget.config!.targetCity;
      _brandTone.text = widget.config!.brandTone;
    }
  }

  @override
  void dispose() {
    _count.dispose();
    _hour.dispose();
    _regenerateHours.dispose();
    _priorityProducts.dispose();
    _targetCity.dispose();
    _brandTone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    if (config == null) {
      return Center(
        child: Text(
          'Configuración no disponible',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            SwitchListTile.adaptive(
              value: _activeVal,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _activeVal = value),
              title: const Text('activo'),
            ),
            SwitchListTile.adaptive(
              value: _pausedVal,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _pausedVal = value),
              title: const Text('pausado'),
            ),
            SwitchListTile.adaptive(
              value: _autoRegenerateVal,
              onChanged: widget.busy
                  ? null
                  : (value) => setState(() => _autoRegenerateVal = value),
              title: const Text('auto_regenerar_si_no_aprueba'),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'cantidad_estados_diarios (default 3)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _hour,
              decoration: const InputDecoration(
                labelText: 'hora_generacion (HH:mm)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _regenerateHours,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'horas_para_regenerar (default 6)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priorityProducts,
              decoration: const InputDecoration(
                labelText: 'productos_prioritarios (coma separada)',
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _targetCity,
              decoration: const InputDecoration(labelText: 'ciudad_objetivo'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _brandTone,
              decoration: const InputDecoration(labelText: 'tono_de_marca'),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: widget.busy
                  ? null
                  : () async {
                      if (!_formKey.currentState!.validate()) return;
                      final payload = MarketingFlowConfig(
                        id: config.id,
                        active: _activeVal,
                        paused: _pausedVal,
                        dailyStoriesCount:
                            int.tryParse(_count.text.trim()) ?? 3,
                        generationTime: _hour.text.trim().isEmpty
                            ? '08:00'
                            : _hour.text.trim(),
                        autoRegenerate: _autoRegenerateVal,
                        regenerateAfterHours:
                            int.tryParse(_regenerateHours.text.trim()) ?? 6,
                        priorityProducts: _priorityProducts.text
                            .split(',')
                            .map((item) => item.trim())
                            .where((item) => item.isNotEmpty)
                            .toList(growable: false),
                        targetCity: _targetCity.text.trim(),
                        brandTone: _brandTone.text.trim(),
                      );
                      await widget.onSave(payload);
                    },
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar configuración'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryFullscreenPreview extends StatelessWidget {
  const _StoryFullscreenPreview({required this.story, required this.imageUrl});

  final MarketingStory story;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl.trim().isNotEmpty;

    return Material(
      color: const Color(0xFF07111F),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Diseño final 9:16',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: 9 / 16,
                        child: SizedBox(
                          width: 360,
                          child: hasImage
                              ? _StoryImageView(url: imageUrl)
                              : const _BrokenImagePlaceholder(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final MarketingStoryStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, text) = switch (status) {
      MarketingStoryStatus.pending => (
        const Color(0xFFFFF3CD),
        const Color(0xFF7A5A00),
        'Pendiente',
      ),
      MarketingStoryStatus.approved => (
        const Color(0xFFD9FBE5),
        const Color(0xFF0E5F33),
        'Aprobado',
      ),
      MarketingStoryStatus.rejected => (
        const Color(0xFFFFE1E1),
        const Color(0xFF7B1A1A),
        'Rechazado',
      ),
      MarketingStoryStatus.regenerated => (
        const Color(0xFFE8EAF0),
        const Color(0xFF334155),
        'Regenerado',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _PublishStatusPill extends StatelessWidget {
  const _PublishStatusPill({
    required this.status,
    required this.facebookPostId,
    required this.facebookStoryId,
    required this.instagramPostId,
    required this.instagramStoryId,
    required this.publishedChannels,
    required this.publishTargets,
  });

  final MarketingPublishStatus status;
  final String? facebookPostId;
  final String? facebookStoryId;
  final String? instagramPostId;
  final String? instagramStoryId;
  final List<MarketingPublishTarget> publishedChannels;
  final List<MarketingPublishTarget> publishTargets;

  @override
  Widget build(BuildContext context) {
    final hasFacebookPost = (facebookPostId ?? '').trim().isNotEmpty;
    final hasFacebookStory = (facebookStoryId ?? '').trim().isNotEmpty;
    final hasFacebook = hasFacebookPost || hasFacebookStory;
    final hasInstagramPost = (instagramPostId ?? '').trim().isNotEmpty;
    final hasInstagramStory = (instagramStoryId ?? '').trim().isNotEmpty;
    final hasInstagram = hasInstagramPost || hasInstagramStory;
    final anyPublished =
        publishedChannels.isNotEmpty || hasFacebook || hasInstagram;
    final effectiveStatus =
        anyPublished && status == MarketingPublishStatus.error
        ? MarketingPublishStatus.partial
        : anyPublished && status == MarketingPublishStatus.pending
        ? MarketingPublishStatus.partial
        : status;
    final requestedInstagram =
        publishTargets.contains(MarketingPublishTarget.instagramPost) ||
        publishTargets.contains(MarketingPublishTarget.instagramStory);

    final (bg, fg, text) = switch (effectiveStatus) {
      MarketingPublishStatus.pending => (
        const Color(0xFFE2E8F0),
        const Color(0xFF334155),
        'Pendiente',
      ),
      MarketingPublishStatus.publishing => (
        const Color(0xFFDBEAFE),
        const Color(0xFF1D4ED8),
        'Publicando',
      ),
      MarketingPublishStatus.published => (
        const Color(0xFFD9FBE5),
        const Color(0xFF0E5F33),
        hasFacebookStory && hasInstagramStory
            ? 'Stories OK'
            : hasFacebookPost && hasInstagramPost
            ? 'Posts OK'
            : hasFacebook && hasInstagram
            ? 'FB + IG'
            : hasInstagramStory && !hasInstagramPost
            ? 'IG Story'
            : hasFacebookStory && !hasFacebookPost
            ? 'FB Story'
            : hasInstagram
            ? 'Instagram'
            : 'Facebook',
      ),
      MarketingPublishStatus.partial => (
        const Color(0xFFFFF3CD),
        const Color(0xFF7A5A00),
        hasFacebook && requestedInstagram ? 'FB parcial' : 'Parcial',
      ),
      MarketingPublishStatus.error => (
        const Color(0xFFFFE1E1),
        const Color(0xFF7B1A1A),
        'Error',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      alignment: Alignment.center,
      child: Text(text),
    );
  }
}

class _EditStoryPayload {
  const _EditStoryPayload({
    required this.title,
    required this.shortText,
    required this.longText,
    required this.hashtags,
    required this.imagePrompt,
    required this.imageUrl,
  });

  final String title;
  final String shortText;
  final String longText;
  final List<String> hashtags;
  final String imagePrompt;
  final String imageUrl;
}

class _EditStoryDialog extends StatefulWidget {
  const _EditStoryDialog({
    required this.story,
    this.mediaAssets = const [],
    this.onUploadImage,
  });

  final MarketingStory story;
  final List<MarketingMediaAsset> mediaAssets;
  final Future<String?> Function(BuildContext context)? onUploadImage;

  @override
  State<_EditStoryDialog> createState() => _EditStoryDialogState();
}

class _EditStoryDialogState extends State<_EditStoryDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _shortText;
  late final TextEditingController _longText;
  late final TextEditingController _hashtags;
  late final TextEditingController _imagePrompt;
  late final TextEditingController _imageUrl;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.story.title);
    _shortText = TextEditingController(text: widget.story.shortText);
    _longText = TextEditingController(text: widget.story.longText);
    _hashtags = TextEditingController(text: widget.story.hashtags.join(' '));
    _imagePrompt = TextEditingController(text: widget.story.imagePrompt);
    _imageUrl = TextEditingController(text: widget.story.imageUrl);
  }

  @override
  void dispose() {
    _title.dispose();
    _shortText.dispose();
    _longText.dispose();
    _hashtags.dispose();
    _imagePrompt.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar contenido'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _shortText,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Texto corto'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _longText,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(labelText: 'Texto largo'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _hashtags,
                  decoration: const InputDecoration(
                    labelText: 'Hashtags (separados por espacio)',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _imagePrompt,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Prompt de imagen',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _imageUrl,
                        decoration: const InputDecoration(
                          labelText: 'Imagen URL o image_placeholder',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.mediaAssets.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final chosen = await showDialog<String>(
                            context: context,
                            builder: (_) => _PickMediaAssetDialog(
                              assets: widget.mediaAssets,
                              selectedId: _imageUrl.text,
                            ),
                          );
                          if (chosen != null && chosen.isNotEmpty) {
                            MarketingMediaAsset? asset;
                            for (final a in widget.mediaAssets) {
                              if (a.id == chosen ||
                                  a.mediaAssetId == chosen ||
                                  a.contentGalleryItemId == chosen) {
                                asset = a;
                                break;
                              }
                            }
                            if (asset != null) {
                              final url = asset.fileUrl.trim();
                              if (url.isNotEmpty) {
                                _imageUrl.text = url;
                                setState(() {});
                              }
                            }
                          }
                        },
                        icon: const Icon(Icons.image_rounded, size: 16),
                        label: const Text('Galería'),
                      ),
                    const SizedBox(width: 8),
                    if (widget.onUploadImage != null)
                      OutlinedButton.icon(
                        onPressed: () async {
                          final uploadedUrl = await widget.onUploadImage!(
                            context,
                          );
                          if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
                            _imageUrl.text = uploadedUrl;
                            setState(() {});
                          }
                        },
                        icon: const Icon(Icons.cloud_upload_rounded, size: 16),
                        label: const Text('Subir'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.of(context).pop(
              _EditStoryPayload(
                title: _title.text,
                shortText: _shortText.text,
                longText: _longText.text,
                hashtags: _hashtags.text
                    .split(RegExp(r'\s+'))
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(growable: false),
                imagePrompt: _imagePrompt.text,
                imageUrl: _imageUrl.text.trim().isEmpty
                    ? 'image_placeholder'
                    : _imageUrl.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

String _storyTypeLabel(MarketingStoryType type) {
  switch (type) {
    case MarketingStoryType.sales:
      return 'Estado 1: Venta directa';
    case MarketingStoryType.trust:
      return 'Estado 2: Confianza / autoridad';
    case MarketingStoryType.educational:
      return 'Estado 3: Educativo / necesidad';
  }
}

String _storyTypeShort(MarketingStoryType type) {
  switch (type) {
    case MarketingStoryType.sales:
      return 'Venta';
    case MarketingStoryType.trust:
      return 'Confianza';
    case MarketingStoryType.educational:
      return 'Educativo';
  }
}

String _safeImageUrl(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  if (value.startsWith('data:image/')) return value;
  if (value.startsWith('//')) return 'https:$value';
  if (value.startsWith('image_placeholder')) return '';
  final base = Env.apiBaseUrl;
  if (value.startsWith('/')) {
    return '${base.replaceFirst(RegExp(r'/+$'), '')}$value';
  }
  final clean = value.replaceFirst(RegExp(r'^\./'), '');
  return '${base.replaceFirst(RegExp(r'/+$'), '')}/${clean.replaceFirst(RegExp(r'^/+'), '')}';
}

bool _isVideoMediaUrl(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.startsWith('data:video/')) return true;
  return RegExp(r'\.(mp4|mov|m4v|webm|mkv)(\?|$)').hasMatch(value);
}

String _resolveFinalImageUrl(MarketingStory story) {
  final generated = _safeImageUrl(story.generatedImageUrl);
  if (generated.isNotEmpty) {
    return _appendCacheVersion(generated, story.updatedAt ?? story.date);
  }
  // Fallback: manual upload saved via edit dialog goes to imageUrl field
  final manual = _safeImageUrl(story.imageUrl);
  if (manual.isNotEmpty) {
    return _appendCacheVersion(manual, story.updatedAt ?? story.date);
  }
  return '';
}

String _resolveBaseImageUrl(MarketingStory story) {
  final assetFile = _safeImageUrl(story.mediaAsset?.fileUrl);
  if (assetFile.isNotEmpty) {
    return _appendCacheVersion(assetFile, story.updatedAt ?? story.date);
  }

  final assetThumb = _safeImageUrl(story.mediaAsset?.thumbnailUrl);
  if (assetThumb.isNotEmpty) {
    return _appendCacheVersion(assetThumb, story.updatedAt ?? story.date);
  }

  return _appendCacheVersion(
    _safeImageUrl(story.imageUrl),
    story.updatedAt ?? story.date,
  );
}

bool _isBaseImageConfirmed(MarketingStory story) {
  return story.imageGenerationMetadata['imageSelectionConfirmed'] == true;
}

String _appendCacheVersion(String url, DateTime? versionDate) {
  if (url.isEmpty) return '';
  if (!url.startsWith('http://') && !url.startsWith('https://')) return url;

  final version = (versionDate ?? DateTime.now()).millisecondsSinceEpoch;
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  final updatedQuery = Map<String, String>.from(uri.queryParameters)
    ..['v'] = '$version';
  return uri.replace(queryParameters: updatedQuery).toString();
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _formatDateTime(DateTime? value) {
  if (value == null) return '-';
  return '${_formatDate(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
