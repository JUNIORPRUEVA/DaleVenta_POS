class MarketingFlowConfig {
  const MarketingFlowConfig({
    required this.id,
    required this.active,
    required this.paused,
    required this.dailyStoriesCount,
    required this.generationTime,
    required this.autoRegenerate,
    required this.regenerateAfterHours,
    required this.priorityProducts,
    required this.targetCity,
    required this.brandTone,
  });

  final String id;
  final bool active;
  final bool paused;
  final int dailyStoriesCount;
  final String generationTime;
  final bool autoRegenerate;
  final int regenerateAfterHours;
  final List<String> priorityProducts;
  final String targetCity;
  final String brandTone;

  factory MarketingFlowConfig.fromJson(Map<String, dynamic> json) {
    return MarketingFlowConfig(
      id: '${json['id'] ?? ''}',
      active: json['active'] == true,
      paused: json['paused'] == true,
      dailyStoriesCount: (json['dailyStoriesCount'] as num?)?.toInt() ?? 3,
      generationTime: '${json['generationTime'] ?? '08:00'}',
      autoRegenerate: json['autoRegenerate'] == true,
      regenerateAfterHours:
          (json['regenerateAfterHours'] as num?)?.toInt() ?? 6,
      priorityProducts: (json['priorityProducts'] is List)
          ? (json['priorityProducts'] as List)
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const [],
      targetCity: '${json['targetCity'] ?? ''}',
      brandTone: '${json['brandTone'] ?? ''}',
    );
  }
}

enum MarketingStoryType { sales, trust, educational }

enum MarketingStoryStatus { pending, approved, rejected, regenerated }

enum MarketingPublishStatus { pending, publishing, published, partial, error }

enum MarketingPublishTarget {
  facebookStory,
  instagramStory,
  facebookPost,
  instagramPost,
}

enum MarketingImageStatus { pending, queued, processing, generated, failed }

MarketingStoryType parseStoryType(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'TRUST':
      return MarketingStoryType.trust;
    case 'EDUCATIONAL':
      return MarketingStoryType.educational;
    case 'SALES':
    default:
      return MarketingStoryType.sales;
  }
}

MarketingStoryStatus parseStoryStatus(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'APPROVED':
      return MarketingStoryStatus.approved;
    case 'REJECTED':
      return MarketingStoryStatus.rejected;
    case 'REGENERATED':
      return MarketingStoryStatus.regenerated;
    case 'PENDING':
    default:
      return MarketingStoryStatus.pending;
  }
}

MarketingPublishStatus parsePublishStatus(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'PUBLISHING':
      return MarketingPublishStatus.publishing;
    case 'PUBLISHED':
      return MarketingPublishStatus.published;
    case 'PARTIAL':
      return MarketingPublishStatus.partial;
    case 'ERROR':
      return MarketingPublishStatus.error;
    case 'PENDING':
    default:
      return MarketingPublishStatus.pending;
  }
}

MarketingPublishTarget? parsePublishTarget(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  switch (normalized) {
    case 'facebook_story':
      return MarketingPublishTarget.facebookStory;
    case 'instagram_story':
      return MarketingPublishTarget.instagramStory;
    case 'facebook_post':
      return MarketingPublishTarget.facebookPost;
    case 'instagram_post':
      return MarketingPublishTarget.instagramPost;
    default:
      return null;
  }
}

String publishTargetApiValue(MarketingPublishTarget value) {
  switch (value) {
    case MarketingPublishTarget.facebookStory:
      return 'facebook_story';
    case MarketingPublishTarget.instagramStory:
      return 'instagram_story';
    case MarketingPublishTarget.facebookPost:
      return 'facebook_post';
    case MarketingPublishTarget.instagramPost:
      return 'instagram_post';
  }
}

List<MarketingPublishTarget> parsePublishTargets(dynamic value) {
  if (value is! List) return const [];
  final items = <MarketingPublishTarget>[];
  for (final item in value) {
    final parsed = parsePublishTarget('$item');
    if (parsed != null && !items.contains(parsed)) {
      items.add(parsed);
    }
  }
  return items;
}

MarketingImageStatus parseImageStatus(String? value) {
  final normalized = (value ?? '').trim().toUpperCase();
  switch (normalized) {
    case 'QUEUED':
      return MarketingImageStatus.queued;
    case 'PROCESSING':
      return MarketingImageStatus.processing;
    case 'GENERATED':
      return MarketingImageStatus.generated;
    case 'FAILED':
      return MarketingImageStatus.failed;
    case 'PENDING_MEDIA':
    case 'PENDING':
    default:
      return MarketingImageStatus.pending;
  }
}

class MarketingMediaAsset {
  const MarketingMediaAsset({
    required this.id,
    required this.contentGalleryItemId,
    required this.mediaAssetId,
    required this.fileUrl,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.fileName,
    required this.mimeType,
    required this.category,
    required this.relatedService,
    required this.tags,
    required this.description,
    required this.origin,
    required this.isAuthorizedForPublicidad,
    required this.isActive,
    required this.isFeatured,
    required this.useCount,
    required this.lastUsedAt,
    required this.latestStoryId,
    required this.latestStoryTitle,
    required this.latestStoryDate,
    required this.latestStoryType,
    required this.sourceType,
  });

  final String id;
  final String? contentGalleryItemId;
  final String? mediaAssetId;
  final String fileUrl;
  final String imageUrl;
  final String? thumbnailUrl;
  final String fileName;
  final String mimeType;
  final String category;
  final String? relatedService;
  final List<String> tags;
  final String? description;
  final String? origin;
  final bool isAuthorizedForPublicidad;
  final bool isActive;
  final bool isFeatured;
  final int useCount;
  final DateTime? lastUsedAt;
  final String? latestStoryId;
  final String? latestStoryTitle;
  final DateTime? latestStoryDate;
  final String? latestStoryType;
  final String? sourceType;

  factory MarketingMediaAsset.fromJson(Map<String, dynamic> json) {
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final latestStoryRaw = json['latestStory'];
    final latestStory = latestStoryRaw is Map
        ? latestStoryRaw.cast<String, dynamic>()
        : const <String, dynamic>{};
    final rawFileUrl = '${json['fileUrl'] ?? json['imageUrl'] ?? ''}'.trim();
    final rawImageUrl = '${json['imageUrl'] ?? json['fileUrl'] ?? ''}'.trim();
    final contentGalleryItemId =
        '${json['contentGalleryItemId'] ?? ''}'.trim().isEmpty
        ? null
        : '${json['contentGalleryItemId']}';
    final mediaAssetId = '${json['mediaAssetId'] ?? ''}'.trim().isEmpty
        ? null
        : '${json['mediaAssetId']}';
    return MarketingMediaAsset(
      id: '${json['id'] ?? ''}',
      contentGalleryItemId: contentGalleryItemId,
      mediaAssetId: mediaAssetId,
      fileUrl: rawFileUrl,
      imageUrl: rawImageUrl,
      thumbnailUrl: (json['thumbnailUrl'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['thumbnailUrl']}',
      fileName: '${json['fileName'] ?? ''}',
      mimeType: '${json['mimeType'] ?? ''}',
      category: '${json['category'] ?? ''}',
      relatedService: (json['relatedService'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['relatedService']}',
      tags: tags,
      description: (json['description'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['description']}',
      origin: '${json['origin'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['origin']}',
      isAuthorizedForPublicidad: json['isAuthorizedForPublicidad'] != false,
      isActive: json['isActive'] != false,
      isFeatured: json['isFeatured'] == true,
      useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      lastUsedAt: DateTime.tryParse('${json['lastUsedAt'] ?? ''}'),
      latestStoryId: '${latestStory['id'] ?? ''}'.trim().isEmpty
          ? null
          : '${latestStory['id']}',
      latestStoryTitle: '${latestStory['title'] ?? ''}'.trim().isEmpty
          ? null
          : '${latestStory['title']}',
      latestStoryDate: DateTime.tryParse('${latestStory['date'] ?? ''}'),
      latestStoryType: '${latestStory['type'] ?? ''}'.trim().isEmpty
          ? null
          : '${latestStory['type']}',
      sourceType: '${json['sourceType'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['sourceType']}',
    );
  }
}

class MarketingLearningInsight {
  const MarketingLearningInsight({
    required this.id,
    required this.category,
    required this.insight,
    required this.score,
    required this.status,
  });

  final String id;
  final String category;
  final String insight;
  final double score;
  final String status;

  factory MarketingLearningInsight.fromJson(Map<String, dynamic> json) {
    return MarketingLearningInsight(
      id: '${json['id'] ?? ''}',
      category: '${json['category'] ?? ''}',
      insight: '${json['insight'] ?? ''}',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      status: '${json['status'] ?? ''}',
    );
  }
}

class MarketingLearningStats {
  const MarketingLearningStats({
    required this.activeCount,
    required this.discardedCount,
    required this.topInsights,
  });

  final int activeCount;
  final int discardedCount;
  final List<MarketingLearningInsight> topInsights;

  factory MarketingLearningStats.fromJson(Map<String, dynamic> json) {
    final rawRows = json['topInsights'];
    final rows = rawRows is List ? rawRows : const [];
    return MarketingLearningStats(
      activeCount: (json['activeCount'] as num?)?.toInt() ?? 0,
      discardedCount: (json['discardedCount'] as num?)?.toInt() ?? 0,
      topInsights: rows
          .whereType<Map>()
          .map(
            (item) =>
                MarketingLearningInsight.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }
}

class MarketingResearchDetail {
  const MarketingResearchDetail({
    required this.id,
    required this.date,
    required this.status,
    required this.createdAt,
    required this.confidenceScore,
    required this.mainFocus,
    required this.researchPrompt,
    required this.marketSummary,
    required this.competitorPublishingPatterns,
    required this.commonOffers,
    required this.observedPriceRanges,
    required this.contentOpportunities,
    required this.strongAngles,
    required this.weakAngles,
    required this.recommendedContentTypes,
    required this.recommendedOffers,
    required this.recommendedHooks,
    required this.recommendedCTAs,
    required this.doMoreOfThis,
    required this.avoidThis,
    required this.dataSources,
  });

  final String id;
  final DateTime? date;
  final String status;
  final DateTime? createdAt;
  final double confidenceScore;
  final String mainFocus;
  final String researchPrompt;
  final String marketSummary;
  final String competitorPublishingPatterns;
  final String commonOffers;
  final String observedPriceRanges;
  final String contentOpportunities;
  final List<String> strongAngles;
  final List<String> weakAngles;
  final List<String> recommendedContentTypes;
  final List<String> recommendedOffers;
  final List<String> recommendedHooks;
  final List<String> recommendedCTAs;
  final List<String> doMoreOfThis;
  final List<String> avoidThis;
  final List<String> dataSources;

  factory MarketingResearchDetail.fromJson(Map<String, dynamic> json) {
    return MarketingResearchDetail(
      id: '${json['id'] ?? ''}',
      date: DateTime.tryParse('${json['date'] ?? ''}'),
      status: '${json['status'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0,
      mainFocus: '${json['mainFocus'] ?? ''}',
      researchPrompt: '${json['researchPrompt'] ?? ''}',
      marketSummary: '${json['marketSummary'] ?? ''}',
      competitorPublishingPatterns:
          '${json['competitorPublishingPatterns'] ?? ''}',
      commonOffers: '${json['commonOffers'] ?? ''}',
      observedPriceRanges: '${json['observedPriceRanges'] ?? ''}',
      contentOpportunities: '${json['contentOpportunities'] ?? ''}',
      strongAngles: _stringListFromUnknown(json['strongAngles']),
      weakAngles: _stringListFromUnknown(json['weakAngles']),
      recommendedContentTypes: _stringListFromUnknown(
        json['recommendedContentTypes'],
      ),
      recommendedOffers: _stringListFromUnknown(json['recommendedOffers']),
      recommendedHooks: _stringListFromUnknown(json['recommendedHooks']),
      recommendedCTAs: _stringListFromUnknown(json['recommendedCTAs']),
      doMoreOfThis: _stringListFromUnknown(json['doMoreOfThis']),
      avoidThis: _stringListFromUnknown(json['avoidThis']),
      dataSources: _stringListFromUnknown(json['dataSources']),
    );
  }
}

List<String> _stringListFromUnknown(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String storyTypeApiValue(MarketingStoryType type) {
  switch (type) {
    case MarketingStoryType.sales:
      return 'SALES';
    case MarketingStoryType.trust:
      return 'TRUST';
    case MarketingStoryType.educational:
      return 'EDUCATIONAL';
  }
}

String storyStatusApiValue(MarketingStoryStatus status) {
  switch (status) {
    case MarketingStoryStatus.pending:
      return 'PENDING';
    case MarketingStoryStatus.approved:
      return 'APPROVED';
    case MarketingStoryStatus.rejected:
      return 'REJECTED';
    case MarketingStoryStatus.regenerated:
      return 'REGENERATED';
  }
}

class MarketingStory {
  const MarketingStory({
    required this.id,
    required this.date,
    required this.type,
    required this.title,
    required this.shortText,
    required this.longText,
    required this.hashtags,
    required this.imagePrompt,
    required this.imageUrl,
    required this.status,
    required this.generationAttempt,
    required this.approvedByUserName,
    required this.approvedAt,
    required this.rejectedAt,
    required this.updatedAt,
    required this.researchId,
    required this.mediaAssetId,
    required this.visualConcept,
    required this.designNotes,
    required this.imageStatus,
    required this.generatedImageUrl,
    required this.generatedImageProvider,
    required this.imageGenerationMetadata,
    required this.usedResearchAngle,
    required this.usedOffer,
    required this.usedCTA,
    required this.publishedAt,
    required this.facebookPostId,
    required this.instagramPostId,
    required this.instagramMediaId,
    required this.instagramStoryId,
    required this.facebookStoryId,
    required this.facebookStoryStatus,
    required this.facebookStoryError,
    required this.instagramStoryStatus,
    required this.facebookPostStatus,
    required this.instagramPostStatus,
    required this.instagramContainerId,
    required this.instagramStoryContainerId,
    required this.instagramStoryPublishedAt,
    required this.publishedChannels,
    required this.publishTargets,
    required this.publishStatus,
    required this.publishError,
    required this.publishErrorCode,
    required this.publishErrorDetails,
    required this.retryCount,
    required this.mediaAsset,
  });

  final String id;
  final DateTime date;
  final MarketingStoryType type;
  final String title;
  final String shortText;
  final String longText;
  final List<String> hashtags;
  final String imagePrompt;
  final String imageUrl;
  final MarketingStoryStatus status;
  final int generationAttempt;
  final String approvedByUserName;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final DateTime? updatedAt;
  final String? researchId;
  final String? mediaAssetId;
  final String visualConcept;
  final String designNotes;
  final MarketingImageStatus imageStatus;
  final String generatedImageUrl;
  final String generatedImageProvider;
  final Map<String, dynamic> imageGenerationMetadata;
  final String usedResearchAngle;
  final String usedOffer;
  final String usedCTA;
  final DateTime? publishedAt;
  final String? facebookPostId;
  final String? instagramPostId;
  final String? instagramMediaId;
  final String? instagramStoryId;
  final String? facebookStoryId;
  final String? facebookStoryStatus;
  final String? facebookStoryError;
  final String? instagramStoryStatus;
  final String? facebookPostStatus;
  final String? instagramPostStatus;
  final String? instagramContainerId;
  final String? instagramStoryContainerId;
  final DateTime? instagramStoryPublishedAt;
  final List<MarketingPublishTarget> publishedChannels;
  final List<MarketingPublishTarget> publishTargets;
  final MarketingPublishStatus publishStatus;
  final String? publishError;
  final String? publishErrorCode;
  final Map<String, dynamic> publishErrorDetails;
  final int retryCount;
  final MarketingMediaAsset? mediaAsset;

  int get regeneratedCount =>
      generationAttempt <= 1 ? 0 : generationAttempt - 1;

  factory MarketingStory.fromJson(Map<String, dynamic> json) {
    final approvedBy = json['approvedByUser'];
    final rawAsset = json['mediaAsset'];
    final approvedByName = approvedBy is Map
        ? '${approvedBy['nombreCompleto'] ?? ''}'.trim()
        : '';

    return MarketingStory(
      id: '${json['id'] ?? ''}',
      date: DateTime.tryParse('${json['date'] ?? ''}') ?? DateTime.now(),
      type: parseStoryType('${json['type'] ?? ''}'),
      title: '${json['title'] ?? ''}',
      shortText: '${json['shortText'] ?? ''}',
      longText: '${json['longText'] ?? ''}',
      hashtags: (json['hashtags'] is List)
          ? (json['hashtags'] as List)
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const [],
      imagePrompt: '${json['imagePrompt'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      status: parseStoryStatus('${json['status'] ?? ''}'),
      generationAttempt: (json['generationAttempt'] as num?)?.toInt() ?? 1,
      approvedByUserName: approvedByName,
      approvedAt: DateTime.tryParse('${json['approvedAt'] ?? ''}'),
      rejectedAt: DateTime.tryParse('${json['rejectedAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      researchId: (json['researchId'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['researchId']}',
      mediaAssetId: (json['mediaAssetId'] ?? '').toString().trim().isEmpty
          ? null
          : '${json['mediaAssetId']}',
      visualConcept: '${json['visualConcept'] ?? ''}',
      designNotes: '${json['designNotes'] ?? ''}',
      imageStatus: parseImageStatus('${json['imageStatus'] ?? ''}'),
      generatedImageUrl: '${json['generatedImageUrl'] ?? ''}',
      generatedImageProvider: '${json['generatedImageProvider'] ?? ''}',
      imageGenerationMetadata: (json['imageGenerationMetadata'] is Map)
          ? (json['imageGenerationMetadata'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
      usedResearchAngle: '${json['usedResearchAngle'] ?? ''}',
      usedOffer: '${json['usedOffer'] ?? ''}',
      usedCTA: '${json['usedCTA'] ?? ''}',
      publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
      facebookPostId: '${json['facebookPostId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['facebookPostId']}',
      instagramPostId:
          '${json['instagramPostId'] ?? json['instagramMediaId'] ?? ''}'
              .trim()
              .isEmpty
          ? null
          : '${json['instagramPostId'] ?? json['instagramMediaId']}',
      instagramMediaId:
          '${json['instagramMediaId'] ?? json['instagramPostId'] ?? ''}'
              .trim()
              .isEmpty
          ? null
          : '${json['instagramMediaId'] ?? json['instagramPostId']}',
      instagramStoryId: '${json['instagramStoryId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['instagramStoryId']}',
      facebookStoryId: '${json['facebookStoryId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['facebookStoryId']}',
      facebookStoryStatus: '${json['facebookStoryStatus'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['facebookStoryStatus']}',
      facebookStoryError: '${json['facebookStoryError'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['facebookStoryError']}',
      instagramStoryStatus:
          '${json['instagramStoryStatus'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['instagramStoryStatus']}',
      facebookPostStatus: '${json['facebookPostStatus'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['facebookPostStatus']}',
      instagramPostStatus: '${json['instagramPostStatus'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['instagramPostStatus']}',
      instagramContainerId:
          '${json['instagramContainerId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['instagramContainerId']}',
      instagramStoryContainerId:
          '${json['instagramStoryContainerId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['instagramStoryContainerId']}',
      instagramStoryPublishedAt: DateTime.tryParse(
        '${json['instagramStoryPublishedAt'] ?? ''}',
      ),
      publishedChannels: parsePublishTargets(json['publishedChannels']),
      publishTargets: parsePublishTargets(json['publishTargets']),
      publishStatus: parsePublishStatus('${json['publishStatus'] ?? ''}'),
      publishError: '${json['publishError'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['publishError']}',
      publishErrorCode: '${json['publishErrorCode'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['publishErrorCode']}',
      publishErrorDetails: (json['publishErrorDetails'] is Map)
          ? (json['publishErrorDetails'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{},
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      mediaAsset: rawAsset is Map
          ? MarketingMediaAsset.fromJson(rawAsset.cast<String, dynamic>())
          : null,
    );
  }
}

class MarketingDashboardResearch {
  const MarketingDashboardResearch({
    required this.id,
    required this.status,
    required this.confidenceScore,
    required this.createdAt,
  });

  final String id;
  final String status;
  final double confidenceScore;
  final DateTime? createdAt;

  factory MarketingDashboardResearch.fromJson(Map<String, dynamic> json) {
    return MarketingDashboardResearch(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? ''}',
      confidenceScore: (json['confidenceScore'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
    );
  }
}

class MarketingDashboard {
  const MarketingDashboard({
    required this.flowStatus,
    required this.pendingApprovalCount,
    required this.approvedTodayCount,
    required this.lastGenerationAt,
    required this.nextSuggestedGeneration,
    required this.latestResearch,
    required this.researchUsable,
    required this.nextAutoResearch,
    required this.researchFrequencyDays,
    required this.serviceRadiusKm,
    required this.serviceZone,
    required this.storiesFromCurrentResearch,
  });

  final String flowStatus;
  final int pendingApprovalCount;
  final int approvedTodayCount;
  final DateTime? lastGenerationAt;
  final DateTime? nextSuggestedGeneration;
  final MarketingDashboardResearch? latestResearch;
  final bool researchUsable;
  final DateTime? nextAutoResearch;
  final int researchFrequencyDays;
  final int serviceRadiusKm;
  final String serviceZone;
  final int storiesFromCurrentResearch;

  factory MarketingDashboard.fromJson(Map<String, dynamic> json) {
    return MarketingDashboard(
      flowStatus: '${json['flowStatus'] ?? 'INACTIVO'}',
      pendingApprovalCount:
          (json['pendingApprovalCount'] as num?)?.toInt() ?? 0,
      approvedTodayCount: (json['approvedTodayCount'] as num?)?.toInt() ?? 0,
      lastGenerationAt: DateTime.tryParse('${json['lastGenerationAt'] ?? ''}'),
      nextSuggestedGeneration: DateTime.tryParse(
        '${json['nextSuggestedGeneration'] ?? ''}',
      ),
      latestResearch: json['latestResearch'] is Map
          ? MarketingDashboardResearch.fromJson(
              (json['latestResearch'] as Map).cast<String, dynamic>(),
            )
          : null,
      researchUsable: json['researchUsable'] == true,
      nextAutoResearch: DateTime.tryParse('${json['nextAutoResearch'] ?? ''}'),
      researchFrequencyDays:
          (json['researchFrequencyDays'] as num?)?.toInt() ?? 7,
      serviceRadiusKm: (json['serviceRadiusKm'] as num?)?.toInt() ?? 25,
      serviceZone: '${json['serviceZone'] ?? 'Higüey, La Altagracia'}',
      storiesFromCurrentResearch:
          (json['storiesFromCurrentResearch'] as num?)?.toInt() ?? 0,
    );
  }
}

class MarketingHistoryResponse {
  const MarketingHistoryResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<MarketingStory> items;
  final int total;
  final int page;
  final int limit;

  factory MarketingHistoryResponse.fromJson(Map<String, dynamic> json) {
    final rows = (json['items'] is List) ? (json['items'] as List) : const [];
    return MarketingHistoryResponse(
      items: rows
          .whereType<Map>()
          .map((item) => MarketingStory.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
    );
  }
}

class MarketingPublishedAsset {
  const MarketingPublishedAsset({
    required this.id,
    required this.storyId,
    required this.mediaAssetId,
    required this.generatedImageUrl,
    required this.imageUrl,
    required this.headline,
    required this.shortText,
    required this.cta,
    required this.hashtags,
    required this.storyType,
    required this.platform,
    required this.status,
    required this.approvedAt,
    required this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.date,
    required this.mediaAsset,
  });

  final String id;
  final String storyId;
  final String? mediaAssetId;
  final String generatedImageUrl;
  final String imageUrl;
  final String headline;
  final String shortText;
  final String cta;
  final List<String> hashtags;
  final String storyType;
  final String platform;
  final String status;
  final DateTime? approvedAt;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? date;
  final MarketingMediaAsset? mediaAsset;

  factory MarketingPublishedAsset.fromJson(Map<String, dynamic> json) {
    final rawAsset = json['mediaAsset'];
    final hashtagsRaw = json['hashtags'];
    final hashtags = hashtagsRaw is List
        ? hashtagsRaw
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return MarketingPublishedAsset(
      id: '${json['id'] ?? ''}',
      storyId: '${json['storyId'] ?? ''}',
      mediaAssetId: '${json['mediaAssetId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['mediaAssetId']}',
      generatedImageUrl: '${json['generatedImageUrl'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      headline: '${json['headline'] ?? ''}',
      shortText: '${json['shortText'] ?? ''}',
      cta: '${json['cta'] ?? ''}',
      hashtags: hashtags,
      storyType: '${json['storyType'] ?? ''}',
      platform: '${json['platform'] ?? 'PENDING_PLATFORM'}',
      status: '${json['status'] ?? ''}',
      approvedAt: DateTime.tryParse('${json['approvedAt'] ?? ''}'),
      publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
      date: DateTime.tryParse('${json['date'] ?? ''}'),
      mediaAsset: rawAsset is Map
          ? MarketingMediaAsset.fromJson(rawAsset.cast<String, dynamic>())
          : null,
    );
  }
}

class MarketingResetCleanSummary {
  const MarketingResetCleanSummary({
    required this.storiesDeleted,
    required this.generatedImagesDeleted,
    required this.activityLogsDeleted,
    required this.publishedDraftsDeleted,
    required this.researchKept,
    required this.mediaAssetsKept,
  });

  final int storiesDeleted;
  final int generatedImagesDeleted;
  final int activityLogsDeleted;
  final int publishedDraftsDeleted;
  final int researchKept;
  final int mediaAssetsKept;

  factory MarketingResetCleanSummary.fromJson(Map<String, dynamic> json) {
    return MarketingResetCleanSummary(
      storiesDeleted: (json['storiesDeleted'] as num?)?.toInt() ?? 0,
      generatedImagesDeleted:
          (json['generatedImagesDeleted'] as num?)?.toInt() ?? 0,
      activityLogsDeleted: (json['activityLogsDeleted'] as num?)?.toInt() ?? 0,
      publishedDraftsDeleted:
          (json['publishedDraftsDeleted'] as num?)?.toInt() ?? 0,
      researchKept: (json['researchKept'] as num?)?.toInt() ?? 0,
      mediaAssetsKept: (json['mediaAssetsKept'] as num?)?.toInt() ?? 0,
    );
  }
}

class MarketingRepairIncompleteError {
  const MarketingRepairIncompleteError({
    required this.storyId,
    required this.reason,
  });

  final String storyId;
  final String reason;

  factory MarketingRepairIncompleteError.fromJson(Map<String, dynamic> json) {
    return MarketingRepairIncompleteError(
      storyId: '${json['storyId'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
    );
  }
}

class MarketingRepairIncompleteSummary {
  const MarketingRepairIncompleteSummary({
    required this.date,
    required this.targeted,
    required this.repaired,
    required this.failed,
  });

  final String date;
  final int targeted;
  final int repaired;
  final List<MarketingRepairIncompleteError> failed;

  factory MarketingRepairIncompleteSummary.fromJson(Map<String, dynamic> json) {
    final rawFailed = (json['failed'] is List)
        ? (json['failed'] as List)
        : const [];
    return MarketingRepairIncompleteSummary(
      date: '${json['date'] ?? ''}',
      targeted: (json['targeted'] as num?)?.toInt() ?? 0,
      repaired: (json['repaired'] as num?)?.toInt() ?? 0,
      failed: rawFailed
          .whereType<Map>()
          .map(
            (item) => MarketingRepairIncompleteError.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
    );
  }
}
