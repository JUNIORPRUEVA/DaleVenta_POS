enum MarketingCampaignStatus {
  draft,
  ready,
  publishing,
  active,
  paused,
  error,
  rejected,
}

enum MarketingCampaignPhase { design, copySegmentation, publish }

enum MarketingCampaignCurrency { dop, usd }

double? _readNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final raw = '$value'.trim();
  if (raw.isEmpty) return null;
  return double.tryParse(raw);
}

MarketingCampaignStatus parseMarketingCampaignStatus(String? value) {
  switch ((value ?? '').trim().toUpperCase()) {
    case 'READY':
      return MarketingCampaignStatus.ready;
    case 'PUBLISHING':
      return MarketingCampaignStatus.publishing;
    case 'ACTIVE':
      return MarketingCampaignStatus.active;
    case 'PAUSED':
      return MarketingCampaignStatus.paused;
    case 'ERROR':
      return MarketingCampaignStatus.error;
    case 'REJECTED':
      return MarketingCampaignStatus.rejected;
    case 'DRAFT':
    default:
      return MarketingCampaignStatus.draft;
  }
}

MarketingCampaignPhase parseMarketingCampaignPhase(String? value) {
  switch ((value ?? '').trim().toUpperCase()) {
    case 'COPY_SEGMENTATION':
      return MarketingCampaignPhase.copySegmentation;
    case 'PUBLISH':
      return MarketingCampaignPhase.publish;
    case 'DESIGN':
    default:
      return MarketingCampaignPhase.design;
  }
}

MarketingCampaignCurrency parseMarketingCampaignCurrency(String? value) {
  switch ((value ?? '').trim().toUpperCase()) {
    case 'USD':
      return MarketingCampaignCurrency.usd;
    case 'DOP':
    default:
      return MarketingCampaignCurrency.dop;
  }
}

String marketingCampaignStatusApi(MarketingCampaignStatus status) {
  switch (status) {
    case MarketingCampaignStatus.ready:
      return 'READY';
    case MarketingCampaignStatus.publishing:
      return 'PUBLISHING';
    case MarketingCampaignStatus.active:
      return 'ACTIVE';
    case MarketingCampaignStatus.paused:
      return 'PAUSED';
    case MarketingCampaignStatus.error:
      return 'ERROR';
    case MarketingCampaignStatus.rejected:
      return 'REJECTED';
    case MarketingCampaignStatus.draft:
      return 'DRAFT';
  }
}

String marketingCampaignPhaseApi(MarketingCampaignPhase phase) {
  switch (phase) {
    case MarketingCampaignPhase.copySegmentation:
      return 'COPY_SEGMENTATION';
    case MarketingCampaignPhase.publish:
      return 'PUBLISH';
    case MarketingCampaignPhase.design:
      return 'DESIGN';
  }
}

String marketingCampaignCurrencyApi(MarketingCampaignCurrency currency) {
  switch (currency) {
    case MarketingCampaignCurrency.usd:
      return 'USD';
    case MarketingCampaignCurrency.dop:
      return 'DOP';
  }
}

class MarketingCampaign {
  const MarketingCampaign({
    required this.id,
    required this.date,
    required this.status,
    required this.phase,
    required this.baseImageUrl,
    required this.finalDesignUrl,
    required this.galleryAssetId,
    required this.headline,
    required this.primaryText,
    required this.description,
    required this.cta,
    required this.hashtags,
    required this.aiAngle,
    required this.aiResearchId,
    required this.recommendedAudience,
    required this.finalAudience,
    required this.dailyBudget,
    required this.totalBudget,
    required this.currency,
    required this.whatsappPhone,
    required this.whatsappMessageTemplate,
    required this.destinationUrl,
    required this.metaCampaignId,
    required this.metaAdSetId,
    required this.metaCreativeId,
    required this.metaAdId,
    required this.metaImageHash,
    required this.metaVideoId,
    required this.metaMediaType,
    required this.metaMediaUrl,
    required this.metaMediaUploadStatus,
    required this.metaPublishProgress,
    required this.metaStatus,
    required this.metaError,
    required this.metaErrorCode,
    required this.metaErrorSubcode,
    required this.fbtraceId,
    required this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final DateTime? date;
  final MarketingCampaignStatus status;
  final MarketingCampaignPhase phase;
  final String? baseImageUrl;
  final String? finalDesignUrl;
  final String? galleryAssetId;
  final String? headline;
  final String? primaryText;
  final String? description;
  final String? cta;
  final List<String> hashtags;
  final String? aiAngle;
  final String? aiResearchId;
  final Map<String, dynamic>? recommendedAudience;
  final Map<String, dynamic>? finalAudience;
  final double? dailyBudget;
  final double? totalBudget;
  final MarketingCampaignCurrency currency;
  final String? whatsappPhone;
  final String? whatsappMessageTemplate;
  final String? destinationUrl;
  final String? metaCampaignId;
  final String? metaAdSetId;
  final String? metaCreativeId;
  final String? metaAdId;
  final String? metaImageHash;
  final String? metaVideoId;
  final String? metaMediaType;
  final String? metaMediaUrl;
  final String? metaMediaUploadStatus;
  final List<Map<String, dynamic>> metaPublishProgress;
  final String? metaStatus;
  final String? metaError;
  final String? metaErrorCode;
  final String? metaErrorSubcode;
  final String? fbtraceId;
  final DateTime? publishedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory MarketingCampaign.fromJson(Map<String, dynamic> json) {
    final hashtagsRaw = json['hashtags'];
    final recommendedAudienceRaw = json['recommendedAudienceJson'];
    final finalAudienceRaw = json['finalAudienceJson'];

    return MarketingCampaign(
      id: '${json['id'] ?? ''}',
      date: DateTime.tryParse('${json['date'] ?? ''}'),
      status: parseMarketingCampaignStatus('${json['status'] ?? ''}'),
      phase: parseMarketingCampaignPhase('${json['phase'] ?? ''}'),
      baseImageUrl: '${json['baseImageUrl'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['baseImageUrl']}',
      finalDesignUrl: '${json['finalDesignUrl'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['finalDesignUrl']}',
      galleryAssetId: '${json['galleryAssetId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['galleryAssetId']}',
      headline: '${json['headline'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['headline']}',
      primaryText: '${json['primaryText'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['primaryText']}',
      description: '${json['description'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['description']}',
      cta: '${json['cta'] ?? ''}'.trim().isEmpty ? null : '${json['cta']}',
      hashtags: hashtagsRaw is List
          ? hashtagsRaw
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      aiAngle: '${json['aiAngle'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['aiAngle']}',
      aiResearchId: '${json['aiResearchId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['aiResearchId']}',
      recommendedAudience: recommendedAudienceRaw is Map
          ? recommendedAudienceRaw.cast<String, dynamic>()
          : null,
      finalAudience: finalAudienceRaw is Map
          ? finalAudienceRaw.cast<String, dynamic>()
          : null,
      dailyBudget: _readNullableDouble(json['dailyBudget']),
      totalBudget: _readNullableDouble(json['totalBudget']),
      currency: parseMarketingCampaignCurrency('${json['currency'] ?? ''}'),
      whatsappPhone: '${json['whatsappPhone'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['whatsappPhone']}',
      whatsappMessageTemplate:
          '${json['whatsappMessageTemplate'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['whatsappMessageTemplate']}',
      destinationUrl: '${json['destinationUrl'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['destinationUrl']}',
      metaCampaignId: '${json['metaCampaignId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaCampaignId']}',
      metaAdSetId: '${json['metaAdSetId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaAdSetId']}',
      metaCreativeId: '${json['metaCreativeId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaCreativeId']}',
      metaAdId: '${json['metaAdId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaAdId']}',
      metaImageHash: '${json['metaImageHash'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaImageHash']}',
      metaVideoId: '${json['metaVideoId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaVideoId']}',
      metaMediaType: '${json['metaMediaType'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaMediaType']}',
      metaMediaUrl: '${json['metaMediaUrl'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaMediaUrl']}',
      metaMediaUploadStatus:
          '${json['metaMediaUploadStatus'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaMediaUploadStatus']}',
      metaPublishProgress: json['metaPublishProgressJson'] is List
          ? (json['metaPublishProgressJson'] as List)
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList(growable: false)
          : const <Map<String, dynamic>>[],
      metaStatus: '${json['metaStatus'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaStatus']}',
      metaError: '${json['metaError'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaError']}',
      metaErrorCode: '${json['metaErrorCode'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaErrorCode']}',
      metaErrorSubcode: '${json['metaErrorSubcode'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['metaErrorSubcode']}',
      fbtraceId: '${json['fbtraceId'] ?? ''}'.trim().isEmpty
          ? null
          : '${json['fbtraceId']}',
      publishedAt: DateTime.tryParse('${json['publishedAt'] ?? ''}'),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }
}

class MetaAdsConfigDebug {
  const MetaAdsConfigDebug({
    required this.hasAppId,
    required this.hasAppSecret,
    required this.hasBusinessId,
    required this.hasAdAccountId,
    required this.hasPageId,
    required this.hasInstagramId,
    required this.tokenPreview,
    required this.tokenValid,
    required this.scopes,
    required this.adAccountAccessible,
  });

  final bool hasAppId;
  final bool hasAppSecret;
  final bool hasBusinessId;
  final bool hasAdAccountId;
  final bool hasPageId;
  final bool hasInstagramId;
  final String tokenPreview;
  final bool tokenValid;
  final List<String> scopes;
  final bool adAccountAccessible;

  factory MetaAdsConfigDebug.fromJson(Map<String, dynamic> json) {
    final scopesRaw = json['scopes'];
    return MetaAdsConfigDebug(
      hasAppId: json['hasAppId'] == true,
      hasAppSecret: json['hasAppSecret'] == true,
      hasBusinessId: json['hasBusinessId'] == true,
      hasAdAccountId: json['hasAdAccountId'] == true,
      hasPageId: json['hasPageId'] == true,
      hasInstagramId: json['hasInstagramId'] == true,
      tokenPreview: '${json['tokenPreview'] ?? ''}',
      tokenValid: json['tokenValid'] == true,
      scopes: scopesRaw is List
          ? scopesRaw.map((item) => '$item').toList(growable: false)
          : const <String>[],
      adAccountAccessible: json['adAccountAccessible'] == true,
    );
  }
}

class MetaRuntimeConfigDebug {
  const MetaRuntimeConfigDebug({
    required this.graphVersion,
    required this.appId,
    required this.appSecretConfigured,
    required this.adAccountId,
    required this.campaignMode,
    required this.pageId,
    required this.instagramBusinessId,
    required this.whatsappPhoneNumberId,
    required this.whatsappBusinessAccountId,
    required this.businessId,
    required this.adsTokenPreview,
    required this.userTokenPreview,
    required this.organicTokenPreview,
  });

  final String graphVersion;
  final String appId;
  final bool appSecretConfigured;
  final String adAccountId;
  final String campaignMode;
  final String pageId;
  final String instagramBusinessId;
  final String whatsappPhoneNumberId;
  final String whatsappBusinessAccountId;
  final String businessId;
  final String adsTokenPreview;
  final String userTokenPreview;
  final String organicTokenPreview;

  factory MetaRuntimeConfigDebug.fromJson(Map<String, dynamic> json) {
    return MetaRuntimeConfigDebug(
      graphVersion: '${json['graphVersion'] ?? ''}',
      appId: '${json['appId'] ?? ''}',
      appSecretConfigured: json['appSecretConfigured'] == true,
      adAccountId: '${json['adAccountId'] ?? ''}',
      campaignMode: '${json['campaignMode'] ?? 'DIRECT_IMAGE_URL'}',
      pageId: '${json['pageId'] ?? ''}',
      instagramBusinessId: '${json['instagramBusinessId'] ?? ''}',
      whatsappPhoneNumberId: '${json['whatsappPhoneNumberId'] ?? ''}',
      whatsappBusinessAccountId: '${json['whatsappBusinessAccountId'] ?? ''}',
      businessId: '${json['businessId'] ?? ''}',
      adsTokenPreview: '${json['adsTokenPreview'] ?? ''}',
      userTokenPreview: '${json['userTokenPreview'] ?? ''}',
      organicTokenPreview: '${json['organicTokenPreview'] ?? ''}',
    );
  }
}

class MetaAdsPermissionsDebug {
  const MetaAdsPermissionsDebug({
    required this.tokenValid,
    required this.tokenSource,
    required this.usingAdsAccessToken,
    required this.appId,
    required this.tokenPreview,
    required this.adAccountId,
    required this.hasAdsManagement,
    required this.hasAdsRead,
    required this.hasBusinessManagement,
    required this.adAccountAccessible,
    required this.canReadAdImages,
    required this.pageAccessible,
    required this.instagramAccessible,
    required this.whatsappPhoneAccessible,
    required this.canUploadAdImage,
    required this.recommendedFixes,
  });

  final bool tokenValid;
  final String tokenSource;
  final bool usingAdsAccessToken;
  final String appId;
  final String tokenPreview;
  final String adAccountId;
  final bool hasAdsManagement;
  final bool hasAdsRead;
  final bool hasBusinessManagement;
  final bool adAccountAccessible;
  final bool canReadAdImages;
  final bool pageAccessible;
  final bool instagramAccessible;
  final bool whatsappPhoneAccessible;
  final bool canUploadAdImage;
  final List<String> recommendedFixes;

  factory MetaAdsPermissionsDebug.fromJson(Map<String, dynamic> json) {
    final fixesRaw = json['recommendedFixes'];
    return MetaAdsPermissionsDebug(
      tokenValid: json['tokenValid'] == true,
      tokenSource: '${json['tokenSource'] ?? ''}',
      usingAdsAccessToken: json['usingAdsAccessToken'] == true,
      appId: '${json['appId'] ?? ''}',
      tokenPreview: '${json['tokenPreview'] ?? ''}',
      adAccountId: '${json['adAccountId'] ?? ''}',
      hasAdsManagement: json['hasAdsManagement'] == true,
      hasAdsRead: json['hasAdsRead'] == true,
      hasBusinessManagement: json['hasBusinessManagement'] == true,
      adAccountAccessible: json['adAccountAccessible'] == true,
      canReadAdImages: json['canReadAdImages'] == true,
      pageAccessible: json['pageAccessible'] == true,
      instagramAccessible: json['instagramAccessible'] == true,
      whatsappPhoneAccessible: json['whatsappPhoneAccessible'] == true,
      canUploadAdImage: json['canUploadAdImage'] == true,
      recommendedFixes: fixesRaw is List
          ? fixesRaw.map((item) => '$item').toList(growable: false)
          : const <String>[],
    );
  }
}

class MetaWhatsappDebug {
  const MetaWhatsappDebug({
    required this.hasMetaAccessToken,
    required this.hasAdAccountId,
    required this.hasFacebookPageId,
    required this.hasInstagramBusinessId,
    required this.hasWhatsappPhoneNumberId,
    required this.hasWhatsappBusinessAccountId,
    required this.whatsappPhoneNumberId,
    required this.whatsappBusinessAccountId,
    required this.businessId,
    required this.tokenValid,
    required this.scopes,
    required this.phoneProbeOk,
    required this.phoneProbeMessage,
    required this.phoneProbeCode,
  });

  final bool hasMetaAccessToken;
  final bool hasAdAccountId;
  final bool hasFacebookPageId;
  final bool hasInstagramBusinessId;
  final bool hasWhatsappPhoneNumberId;
  final bool hasWhatsappBusinessAccountId;
  final String whatsappPhoneNumberId;
  final String whatsappBusinessAccountId;
  final String businessId;
  final bool tokenValid;
  final List<String> scopes;
  final bool phoneProbeOk;
  final String phoneProbeMessage;
  final String? phoneProbeCode;

  bool get hasPermissionWarning => !phoneProbeOk && (phoneProbeCode == '10');

  factory MetaWhatsappDebug.fromJson(Map<String, dynamic> json) {
    final scopesRaw = json['scopes'];
    final phoneProbe = (json['phoneNumberProbe'] is Map)
        ? (json['phoneNumberProbe'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return MetaWhatsappDebug(
      hasMetaAccessToken: json['hasMetaAccessToken'] == true,
      hasAdAccountId: json['hasAdAccountId'] == true,
      hasFacebookPageId: json['hasFacebookPageId'] == true,
      hasInstagramBusinessId: json['hasInstagramBusinessId'] == true,
      hasWhatsappPhoneNumberId: json['hasWhatsappPhoneNumberId'] == true,
      hasWhatsappBusinessAccountId:
          json['hasWhatsappBusinessAccountId'] == true,
      whatsappPhoneNumberId: '${json['whatsappPhoneNumberId'] ?? ''}',
      whatsappBusinessAccountId: '${json['whatsappBusinessAccountId'] ?? ''}',
      businessId: '${json['businessId'] ?? ''}',
      tokenValid: json['tokenValid'] == true,
      scopes: scopesRaw is List
          ? scopesRaw.map((item) => '$item').toList(growable: false)
          : const <String>[],
      phoneProbeOk: phoneProbe['ok'] == true,
      phoneProbeMessage: '${phoneProbe['message'] ?? ''}',
      phoneProbeCode: '${phoneProbe['code'] ?? ''}'.trim().isEmpty
          ? null
          : '${phoneProbe['code']}',
    );
  }
}
