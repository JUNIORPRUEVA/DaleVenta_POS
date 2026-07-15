class ImageAnalysisResult {
  const ImageAnalysisResult({
    required this.mediaAssetId,
    required this.fileUrl,
    required this.category,
    required this.productType,
    required this.visualQuality,
    required this.qualityScore,
    required this.recommendation,
    required this.recommendationReason,
    required this.bestForStoryTypes,
    required this.estimatedConversionLift,
    required this.suggestedAngle,
    required this.lightingQuality,
    required this.productClarityScore,
    required this.backgroundQuality,
    required this.usageHistory,
  });

  final String mediaAssetId;
  final String fileUrl;
  final String category;
  final String productType;
  final String visualQuality; // excellent, good, acceptable, poor
  final int qualityScore; // 0-100
  final String recommendation;
  final List<String> recommendationReason;
  final List<String> bestForStoryTypes; // ['sales', 'trust', 'educational']
  final int estimatedConversionLift; // percentage
  final String suggestedAngle;
  final String
  lightingQuality; // professional, good, acceptable, needs_improvement
  final int productClarityScore; // 0-100
  final String backgroundQuality; // professional, acceptable, distracting
  final UsageMetrics usageHistory;

  factory ImageAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ImageAnalysisResult(
      mediaAssetId: json['mediaAssetId'] ?? '',
      fileUrl: json['fileUrl'] ?? '',
      category: json['category'] ?? 'Uncategorized',
      productType: json['productType'] ?? 'General',
      visualQuality: json['visualQuality'] ?? 'acceptable',
      qualityScore: (json['qualityScore'] as num?)?.toInt() ?? 50,
      recommendation: json['recommendation'] ?? '',
      recommendationReason: (json['recommendationReason'] is List)
          ? (json['recommendationReason'] as List).cast<String>()
          : const [],
      bestForStoryTypes: (json['bestForStoryTypes'] is List)
          ? (json['bestForStoryTypes'] as List).cast<String>()
          : const [],
      estimatedConversionLift:
          (json['estimatedConversionLift'] as num?)?.toInt() ?? 5,
      suggestedAngle: json['suggestedAngle'] ?? '',
      lightingQuality: json['lightingQuality'] ?? 'acceptable',
      productClarityScore: (json['productClarityScore'] as num?)?.toInt() ?? 60,
      backgroundQuality: json['backgroundQuality'] ?? 'acceptable',
      usageHistory: UsageMetrics.fromJson(
        (json['usageHistory'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class UsageMetrics {
  const UsageMetrics({
    required this.timesUsed,
    required this.lastUsedAt,
    required this.conversionMetrics,
  });

  final int timesUsed;
  final DateTime? lastUsedAt;
  final ConversionMetrics conversionMetrics;

  factory UsageMetrics.fromJson(Map<String, dynamic> json) {
    return UsageMetrics(
      timesUsed: (json['timesUsed'] as num?)?.toInt() ?? 0,
      lastUsedAt: json['lastUsedAt'] is String
          ? DateTime.tryParse(json['lastUsedAt'] as String)
          : null,
      conversionMetrics: ConversionMetrics.fromJson(
        (json['conversionMetrics'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
    );
  }
}

class ConversionMetrics {
  const ConversionMetrics({
    required this.impressions,
    required this.clicks,
    required this.conversions,
  });

  final int impressions;
  final int clicks;
  final int conversions;

  factory ConversionMetrics.fromJson(Map<String, dynamic> json) {
    return ConversionMetrics(
      impressions: (json['impressions'] as num?)?.toInt() ?? 0,
      clicks: (json['clicks'] as num?)?.toInt() ?? 0,
      conversions: (json['conversions'] as num?)?.toInt() ?? 0,
    );
  }
}
