import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'marketing_api.dart';
import 'marketing_campaign_models.dart';
import 'marketing_models.dart';
import 'providers/campaign_autosave_provider.dart';
import 'widgets/autosave_indicator.dart';

class PublicidadCampanasScreenV2 extends ConsumerStatefulWidget {
  const PublicidadCampanasScreenV2({super.key});

  @override
  ConsumerState<PublicidadCampanasScreenV2> createState() =>
      _PublicidadCampanasScreenV2State();
}

class _PublicidadCampanasScreenV2State
    extends ConsumerState<PublicidadCampanasScreenV2> {
  static const String _defaultMetaAdAccountId = 'act_1425678481793809';
  static const String _defaultCity = 'Higüey, La Altagracia';
  static const int _defaultRadiusKm = 10;
  static const double _defaultMinAge = 25;
  static const double _defaultMaxAge = 50;
  static const String _fixedObjective = 'OUTCOME_ENGAGEMENT';

  bool _loading = true;
  bool _busyAction = false;
  String? _error;
  int _activeSessionIndex = 0;

  List<MarketingCampaign> _campaigns = const [];
  List<MarketingMediaAsset> _assets = const [];
  MetaAdsConfigDebug _metaAdsConfig = const MetaAdsConfigDebug(
    hasAppId: false,
    hasAppSecret: false,
    hasBusinessId: false,
    hasAdAccountId: false,
    hasPageId: false,
    hasInstagramId: false,
    tokenPreview: '',
    tokenValid: false,
    scopes: <String>[],
    adAccountAccessible: false,
  );
  MetaAdsPermissionsDebug? _metaAdsPermissions;
  MetaRuntimeConfigDebug? _metaRuntimeConfig;
  String? _selectedId;
  final Set<String> _mediaChangeModeIds = <String>{};
  final Map<String, _CampaignCopy> _copyByCampaignId =
      <String, _CampaignCopy>{};

  final _dailyBudgetCtrl = TextEditingController(text: '500');
  final _cityCtrl = TextEditingController(text: _defaultCity);

  RangeValues _ageRange = const RangeValues(_defaultMinAge, _defaultMaxAge);
  int _radiusKm = _defaultRadiusKm;
  final Set<String> _selectedInterests = <String>{};

  Timer? _autosaveTimer;
  AutosaveState _autosaveState = AutosaveState();

  static const List<int> _radiusPresets = [5, 10, 15, 30];
  static const List<int> _budgetPresets = [300, 500, 1000, 3000];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _dailyBudgetCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  MarketingCampaign? get _selectedCampaign {
    try {
      return _campaigns.firstWhere((campaign) => campaign.id == _selectedId);
    } catch (_) {
      return _campaigns.isNotEmpty ? _campaigns.first : null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(marketingApiProvider);
      final tuple = await api.loadCampaigns();
      MetaRuntimeConfigDebug? runtimeConfig;
      try {
        runtimeConfig = await api.loadMetaRuntimeConfig();
      } catch (_) {
        runtimeConfig = null;
      }
      MetaAdsPermissionsDebug? permissions;
      try {
        permissions = await api.loadMetaAdsPermissionsDebug();
      } catch (_) {
        permissions = null;
      }
      final assets = _publishedCampaignAssets(await api.loadContentGallery());
      final selected = tuple.$1.any((item) => item.id == _selectedId)
          ? _selectedId
          : (tuple.$1.isNotEmpty ? tuple.$1.first.id : null);

      if (!mounted) return;
      setState(() {
        _campaigns = tuple.$1;
        _assets = assets;
        _metaAdsConfig = tuple.$2;
        _metaAdsPermissions = permissions;
        _metaRuntimeConfig = runtimeConfig;
        _selectedId = selected;
        for (final campaign in tuple.$1) {
          _copyByCampaignId[campaign.id] = _CampaignCopy.fromCampaign(campaign);
        }
        _loading = false;
      });

      if (selected != null) {
        final campaign = _campaigns.firstWhere((item) => item.id == selected);
        _syncFormFromCampaign(campaign);
        await _autoSelectInitialMediaIfNeeded(campaign);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is ApiException ? error.message : '$error';
        _loading = false;
      });
    }
  }

  void _syncFormFromCampaign(MarketingCampaign campaign) {
    final audience =
        campaign.finalAudience ?? campaign.recommendedAudience ?? {};
    _dailyBudgetCtrl.text = (campaign.dailyBudget ?? 500).toStringAsFixed(0);

    final city = '${audience['city'] ?? ''}'.trim();
    _cityCtrl.text = city.isEmpty ? _defaultCity : city;

    final radius = (audience['radiusKm'] as num?)?.toInt() ?? _defaultRadiusKm;
    _radiusKm = _radiusPresets.contains(radius) ? radius : _defaultRadiusKm;

    final minAge =
        (((audience['ageMin'] as num?)?.toDouble() ?? _defaultMinAge).clamp(
          18,
          65,
        )).toDouble();
    final maxAge =
        (((audience['ageMax'] as num?)?.toDouble() ?? _defaultMaxAge).clamp(
          18,
          65,
        )).toDouble();
    _ageRange = RangeValues(
      minAge <= maxAge ? minAge : _defaultMinAge,
      minAge <= maxAge ? maxAge : _defaultMaxAge,
    );

    _selectedInterests
      ..clear()
      ..addAll(_extractSuggestedInterests(campaign));
    _autosaveState = AutosaveState();
  }

  Future<void> _runAction(String label, Future<void> Function() action) async {
    if (_busyAction) return;
    setState(() => _busyAction = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label completado')));
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
      if (mounted) setState(() => _busyAction = false);
    }
  }

  Future<void> _openMetaTokenSettings() async {
    final api = ref.read(marketingApiProvider);
    try {
      final currentConfig = await api.loadMetaRuntimeConfig();
      if (!mounted) return;

      final payload = await showDialog<_MetaRuntimeConfigPayload>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _MetaRuntimeConfigDialog(initial: currentConfig),
      );
      if (payload == null) return;

      await api.updateMetaRuntimeConfig(
        graphVersion: payload.graphVersion,
        appId: payload.appId,
        appSecret: payload.appSecret,
        adAccountId: payload.adAccountId,
        campaignMode: payload.campaignMode,
        pageId: payload.pageId,
        instagramBusinessId: payload.instagramBusinessId,
        whatsappPhoneNumberId: payload.whatsappPhoneNumberId,
        whatsappBusinessAccountId: payload.whatsappBusinessAccountId,
        businessId: payload.businessId,
        adsAccessToken: payload.adsAccessToken,
      );

      final runtimeConfig = await api.loadMetaRuntimeConfig();
      final permissions = await api.loadMetaAdsPermissionsDebug();
      setState(() {
        _metaRuntimeConfig = runtimeConfig;
        _metaAdsPermissions = permissions;
      });
      MetaWhatsappDebug? whatsapp;
      try {
        whatsapp = await api.loadMetaWhatsappDebug();
      } catch (_) {
        // Backward compatibility: route may not exist in older deployed backend.
      }
      if (!mounted) return;
      final fixes = permissions.recommendedFixes;
      final fixText = fixes.isEmpty ? '' : '\nSugerencia: ${fixes.first}';
      final whatsappWarning = (whatsapp?.hasPermissionWarning ?? false)
          ? '\nAdvertencia: El token no puede consultar el número, pero se intentará usarlo al crear el anuncio.'
          : '';
      final whatsappUnavailable = whatsapp == null
          ? '\nNota: El debug de WhatsApp no está disponible en este backend (requiere actualización/reinicio del API).'
          : '';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _hasMinimumMetaAdsPermissions(permissions)
                ? 'Configuración Meta actualizada. Permisos Ads listos.'
                : 'Configuración guardada. Aún faltan permisos en Meta Ads.$fixText$whatsappWarning$whatsappUnavailable',
          ),
        ),
      );
      await _load();
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
    }
  }

  Future<void> _testMetaAdsConnection() async {
    final api = ref.read(marketingApiProvider);
    await _runAction('Prueba permisos Meta Ads', () async {
      final permissions = await api.loadMetaAdsPermissionsDebug();
      setState(() => _metaAdsPermissions = permissions);
      MetaWhatsappDebug? whatsapp;
      try {
        whatsapp = await api.loadMetaWhatsappDebug();
      } catch (_) {
        whatsapp = null;
      }
      if (!mounted) return;

      final checks = <String>[
        'Token válido: ${permissions.tokenValid ? 'OK' : 'FALLO'}',
        'Token Ads dedicado: ${permissions.usingAdsAccessToken ? 'OK (META_ADS_ACCESS_TOKEN) ✅' : 'FALLO (META_ADS_ACCESS_TOKEN no configurado) ❌'}',
        'ads_management: ${permissions.hasAdsManagement ? 'OK' : 'FALLO'}',
        'ads_read: ${permissions.hasAdsRead ? 'OK' : 'FALLO'}',
        if (_metaAdsConfig.hasBusinessId)
          'business_management: ${permissions.hasBusinessManagement ? 'OK' : 'FALLO'}',
        'Ad Account accesible: ${permissions.adAccountAccessible ? 'OK' : 'FALLO'}',
        'Puede leer adimages: ${permissions.canReadAdImages ? 'OK' : 'FALLO'}',
        'Puede subir imágenes: ${permissions.canUploadAdImage ? 'OK' : 'FALLO'}',
        'WhatsApp configurado: ${whatsapp == null ? 'ENDPOINT DEBUG NO DISPONIBLE' : (whatsapp.hasWhatsappPhoneNumberId ? 'OK' : 'FALLO')}',
      ];

      final warning = (whatsapp?.hasPermissionWarning ?? false)
          ? 'El token no puede consultar el número, pero se intentará usarlo al crear el anuncio.'
          : '';

      final fixes = permissions.recommendedFixes;
      final details = [
        'Token preview: ${permissions.tokenPreview.isEmpty ? '-' : permissions.tokenPreview}',
        'Token source: ${permissions.tokenSource.isEmpty ? '-' : permissions.tokenSource}',
        'App ID usado: ${permissions.appId.isEmpty ? '-' : permissions.appId}',
        'Ad Account usado: ${permissions.adAccountId.isEmpty ? '-' : permissions.adAccountId}',
        '',
        ...checks,
        if (whatsapp == null)
          'Nota: GET /marketing/debug/meta-whatsapp no existe en el backend actual. Reinicia/actualiza API para habilitarlo.',
        if (warning.isNotEmpty) 'Advertencia: $warning',
        if ((whatsapp?.phoneProbeMessage.trim().isNotEmpty ?? false))
          'Detalle WhatsApp: ${whatsapp!.phoneProbeMessage.trim()}',
        if (fixes.isNotEmpty) 'Sugerencia: ${fixes.first}',
      ].join('\n');

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Probar permisos Meta Ads'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(details)),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _testMetaAdsN8nLogic() async {
    final api = ref.read(marketingApiProvider);
    await _runAction('Prueba lógica n8n', () async {
      final report = await api.loadMetaN8nCompatibilityDebug();
      if (!mounted) return;

      final checksRaw = (report['checks'] is List)
          ? (report['checks'] as List)
          : const [];
      final lines = <String>[
        'Credencial equivalente: ${report['credentialEquivalent'] ?? 'Token Meta Ads'}',
        'Cuenta Ads actual: ${report['adAccountId'] ?? _defaultMetaAdAccountId}',
        'Modo: ${report['modeLabel'] ?? 'Compatible n8n'}',
        'Token preview: ${report['tokenPreview'] ?? '-'}',
        'App ID usado: ${report['appId'] ?? '-'}',
        '',
      ];

      for (final item in checksRaw.whereType<Map>()) {
        final check = item.cast<String, dynamic>();
        final ok = check['ok'] == true;
        final parts = <String>[
          '${ok ? 'OK' : 'FALLO'} ${check['label'] ?? 'Check'}',
          '${check['detail'] ?? ''}'.trim(),
          if ('${check['code'] ?? ''}'.trim().isNotEmpty)
            'code=${check['code']}',
          if ('${check['subcode'] ?? ''}'.trim().isNotEmpty)
            'subcode=${check['subcode']}',
          if ('${check['fbtraceId'] ?? ''}'.trim().isNotEmpty)
            'fbtrace_id=${check['fbtraceId']}',
        ].where((item) => item.trim().isNotEmpty).toList(growable: false);
        lines.add(parts.join(' · '));
      }

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Probar con lógica n8n'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: SelectableText(lines.join('\n')),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _createDraft() async {
    await _runAction('Campana creada', () async {
      final created = await ref
          .read(marketingApiProvider)
          .generateCampaignDraft();
      if (!mounted) return;
      setState(() {
        _upsertCampaign(created);
        _selectedId = created.id;
      });
      _syncFormFromCampaign(created);
    });
  }

  Future<void> _applyMediaAndAutoGenerate(MarketingMediaAsset asset) async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    final mediaAssetId = _campaignMediaAssetId(asset);
    if (mediaAssetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Esta imagen publicada no esta disponible para campanas.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _copyByCampaignId[campaign.id] = _CampaignCopy.generating();
    });

    await _runAction('Media aplicada y copy generado', () async {
      final api = ref.read(marketingApiProvider);
      final changed = await api.changeCampaignBaseImage(
        campaign.id,
        mediaAssetId,
      );
      if (mounted) {
        setState(() => _upsertCampaign(changed, keepGeneratingCopy: true));
      }

      final confirmed = await api.confirmCampaignBaseImage(campaign.id);
      if (mounted) {
        setState(() => _upsertCampaign(confirmed, keepGeneratingCopy: true));
      }

      final generated = await api.regenerateCampaignCopy(campaign.id);
      if (mounted) {
        setState(() {
          _mediaChangeModeIds.remove(campaign.id);
          _upsertCampaign(generated);
        });
      }
    });
  }

  Future<void> _autoSelectInitialMediaIfNeeded(
    MarketingCampaign campaign,
  ) async {
    final hasMedia =
        (campaign.galleryAssetId ?? '').trim().isNotEmpty ||
        (campaign.baseImageUrl ?? '').trim().isNotEmpty ||
        (campaign.finalDesignUrl ?? '').trim().isNotEmpty;
    if (_busyAction) return;

    if (hasMedia) {
      if (_copyFor(campaign).hasRealCopy) return;
      setState(() {
        _copyByCampaignId[campaign.id] = _CampaignCopy.generating();
      });
      try {
        final generated = await ref
            .read(marketingApiProvider)
            .regenerateCampaignCopy(campaign.id);
        if (mounted) {
          setState(() => _upsertCampaign(generated));
        }
      } catch (error, stackTrace) {
        debugPrint('Error generando copys iniciales: $error');
        debugPrint('$stackTrace');
      }
      return;
    }

    if (_assets.isEmpty) return;

    final asset = _preferredInitialAsset();
    if (asset == null) return;

    setState(() {
      _copyByCampaignId[campaign.id] = _CampaignCopy.generating();
    });

    try {
      final api = ref.read(marketingApiProvider);
      final mediaAssetId = _campaignMediaAssetId(asset);
      if (mediaAssetId == null) return;

      final changed = await api.changeCampaignBaseImage(
        campaign.id,
        mediaAssetId,
      );
      if (mounted) {
        setState(() => _upsertCampaign(changed, keepGeneratingCopy: true));
      }

      final confirmed = await api.confirmCampaignBaseImage(campaign.id);
      if (mounted) {
        setState(() => _upsertCampaign(confirmed, keepGeneratingCopy: true));
      }

      final generated = await api.regenerateCampaignCopy(campaign.id);
      if (mounted) {
        setState(() => _upsertCampaign(generated));
      }
    } catch (error, stackTrace) {
      debugPrint('Error auto seleccionando media: $error');
      debugPrint('$stackTrace');
    }
  }

  MarketingMediaAsset? _preferredInitialAsset() {
    if (_assets.isEmpty) return null;
    final sorted = [..._assets];
    sorted.sort((a, b) {
      final aDate = a.lastUsedAt ?? a.latestStoryDate ?? DateTime(1970);
      final bDate = b.lastUsedAt ?? b.latestStoryDate ?? DateTime(1970);
      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;
      if (a.isFeatured != b.isFeatured) return a.isFeatured ? -1 : 1;
      return b.useCount.compareTo(a.useCount);
    });
    return sorted.first;
  }

  List<MarketingMediaAsset> _publishedCampaignAssets(
    List<MarketingMediaAsset> assets,
  ) {
    return assets.where(_isPublishedCampaignAsset).toList(growable: false);
  }

  bool _isPublishedCampaignAsset(MarketingMediaAsset asset) {
    if (_campaignMediaAssetId(asset) == null) return false;
    final source = [
      asset.category,
      asset.relatedService ?? '',
      asset.origin ?? '',
      asset.sourceType ?? '',
      ...asset.tags,
    ].join(' ').toLowerCase();
    return source.contains('estado') ||
        source.contains('publicado') ||
        source.contains('published') ||
        source.contains('marketing_published_design') ||
        source.contains('origen:estado_diario') ||
        source.contains('source:marketing_published_design');
  }

  String? _campaignMediaAssetId(MarketingMediaAsset asset) {
    final mediaAssetId = (asset.mediaAssetId ?? '').trim();
    if (mediaAssetId.isNotEmpty) return mediaAssetId;
    final sourceType = (asset.sourceType ?? '').trim().toLowerCase();
    final origin = (asset.origin ?? '').trim().toLowerCase();
    if (sourceType == 'gallery' || origin == 'estado_diario') {
      final id = asset.id.trim();
      if (id.isNotEmpty && !id.contains(':')) return id;
    }
    return null;
  }

  void _startChangingMedia(MarketingCampaign campaign) {
    setState(() {
      _mediaChangeModeIds.add(campaign.id);
    });
  }

  Future<void> _regenerateCopyOnly() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    setState(() {
      _copyByCampaignId[campaign.id] = _CampaignCopy.generating();
    });

    await _runAction('Copy regenerado', () async {
      final generated = await ref
          .read(marketingApiProvider)
          .regenerateCampaignCopy(campaign.id);
      if (mounted) {
        setState(() => _upsertCampaign(generated));
      }
    });
  }

  void _scheduleAutosave() {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    _autosaveTimer?.cancel();
    setState(() {
      _autosaveState = _autosaveState.copyWith(
        hasUnsavedChanges: true,
        error: null,
      );
    });

    _autosaveTimer = Timer(const Duration(milliseconds: 850), () async {
      await _saveDraftSilently(campaign.id);
    });
  }

  Future<void> _saveDraftSilently(String campaignId) async {
    if (!mounted) return;
    setState(() {
      _autosaveState = _autosaveState.copyWith(isLoading: true, error: null);
    });

    try {
      final updated = await ref
          .read(marketingApiProvider)
          .updateCampaign(
            campaignId,
            cta: 'WHATSAPP_MESSAGE',
            dailyBudget: _dailyBudget,
            finalAudience: _buildAudience(),
          );

      if (!mounted) return;
      setState(() {
        _upsertCampaign(updated);
        _autosaveState = _autosaveState.copyWith(
          isLoading: false,
          hasUnsavedChanges: false,
          lastSavedAt: DateTime.now().toIso8601String(),
          error: null,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _autosaveState = _autosaveState.copyWith(
          isLoading: false,
          hasUnsavedChanges: true,
          error: '$error',
        );
      });
    }
  }

  Future<void> _publishCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;

    await _runAction('Campana publicada', () async {
      final permissions = await _refreshMetaAdsPermissions();
      if (!_hasMinimumMetaAdsPermissions(permissions)) {
        throw ApiException(
          _buildMetaAdsPermissionErrorMessage(permissions),
          422,
        );
      }
      await _saveDraftSilently(campaign.id);
      final published = await _createMetaCampaignWithProgress(campaign.id);
      if (mounted) {
        setState(() => _upsertCampaign(published));
      }
    });
  }

  Future<MetaAdsPermissionsDebug> _refreshMetaAdsPermissions() async {
    final permissions = await ref
        .read(marketingApiProvider)
        .loadMetaAdsPermissionsDebug();
    if (mounted) {
      setState(() => _metaAdsPermissions = permissions);
    }
    return permissions;
  }

  bool _hasMinimumMetaAdsPermissions(MetaAdsPermissionsDebug permissions) {
    final needsBusinessManagement = _metaAdsConfig.hasBusinessId;
    final requiresAdImages = _requiresAdImagesMode;
    return permissions.tokenValid &&
        permissions.usingAdsAccessToken &&
        permissions.hasAdsManagement &&
        permissions.hasAdsRead &&
        (!needsBusinessManagement || permissions.hasBusinessManagement) &&
        permissions.adAccountAccessible &&
        (!requiresAdImages || permissions.canReadAdImages) &&
        (!requiresAdImages || permissions.canUploadAdImage);
  }

  String _buildMetaAdsPermissionErrorMessage(
    MetaAdsPermissionsDebug permissions,
  ) {
    if (_requiresAdImagesMode && !permissions.canUploadAdImage) {
      return 'El token Meta Ads no tiene permiso real para subir imágenes al Ad Account. Revisa System User, Ads Management y acceso total a la cuenta publicitaria.';
    }

    final missing = <String>[];
    if (!permissions.tokenValid) missing.add('Token inválido');
    if (!permissions.usingAdsAccessToken) {
      missing.add('No está usando META_ADS_ACCESS_TOKEN');
    }
    if (!permissions.hasAdsManagement) missing.add('Falta ads_management');
    if (!permissions.hasAdsRead) missing.add('Falta ads_read');
    if (_metaAdsConfig.hasBusinessId && !permissions.hasBusinessManagement) {
      missing.add('Falta business_management');
    }
    if (!permissions.adAccountAccessible) {
      missing.add('Ad Account sin acceso real');
    }
    if (_requiresAdImagesMode && !permissions.canReadAdImages) {
      missing.add('No puede leer adimages');
    }

    if (missing.isEmpty) {
      return 'Permisos Meta Ads incompletos para crear campaña.';
    }

    return 'No se puede crear campaña en Meta Ads todavía: ${missing.join(', ')}.';
  }

  bool get _requiresAdImagesMode {
    return (_metaRuntimeConfig?.campaignMode ?? 'DIRECT_IMAGE_URL') ==
        'ADIMAGES_UPLOAD';
  }

  String get _campaignModeLabel {
    switch (_metaRuntimeConfig?.campaignMode ?? 'DIRECT_IMAGE_URL') {
      case 'DIRECT_VIDEO_URL':
        return 'Compatible n8n';
      case 'ADIMAGES_UPLOAD':
        return 'Imagen subida a AdImages';
      case 'DIRECT_IMAGE_URL':
      default:
        return 'Compatible n8n';
    }
  }

  Future<MarketingCampaign> _createMetaCampaignWithProgress(
    String campaignId,
  ) async {
    final api = ref.read(marketingApiProvider);
    var completed = false;
    final publishFuture = api
        .createMetaCampaign(campaignId, objective: _fixedObjective)
        .whenComplete(() => completed = true);

    while (!completed && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!mounted || completed) break;
      try {
        final latest = await api.loadCampaignDetails(campaignId);
        if (!mounted) break;
        setState(() => _upsertCampaign(latest));
      } catch (error, stackTrace) {
        debugPrint('Error leyendo progreso Meta Ads: $error');
        debugPrint('$stackTrace');
      }
    }

    try {
      return await publishFuture;
    } catch (_) {
      try {
        final latest = await api.loadCampaignDetails(campaignId);
        if (mounted) setState(() => _upsertCampaign(latest));
      } catch (error, stackTrace) {
        debugPrint('Error leyendo error Meta Ads final: $error');
        debugPrint('$stackTrace');
      }
      rethrow;
    }
  }

  Future<void> _activateCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Campana activada', () async {
      final updated = await ref
          .read(marketingApiProvider)
          .activateCampaign(campaign.id);
      if (mounted) setState(() => _upsertCampaign(updated));
    });
  }

  Future<void> _pauseCampaign() async {
    final campaign = _selectedCampaign;
    if (campaign == null) return;
    await _runAction('Campana pausada', () async {
      final updated = await ref
          .read(marketingApiProvider)
          .pauseCampaign(campaign.id);
      if (mounted) setState(() => _upsertCampaign(updated));
    });
  }

  void _showTechnicalDetails(MarketingCampaign campaign) {
    final lines = <String>[
      'Estado: ${campaign.metaStatus ?? marketingCampaignStatusApi(campaign.status)}',
      'Campaign ID: ${campaign.metaCampaignId ?? '-'}',
      'AdSet ID: ${campaign.metaAdSetId ?? '-'}',
      'Creative ID: ${campaign.metaCreativeId ?? '-'}',
      'Ad ID: ${campaign.metaAdId ?? '-'}',
      'Image hash: ${campaign.metaImageHash ?? '-'}',
      'Video ID: ${campaign.metaVideoId ?? '-'}',
      'Media type: ${campaign.metaMediaType ?? '-'}',
      'Media upload status: ${campaign.metaMediaUploadStatus ?? '-'}',
      'Media URL: ${campaign.metaMediaUrl ?? '-'}',
      'Error: ${campaign.metaError ?? '-'}',
      'Code: ${campaign.metaErrorCode ?? '-'}',
      'Subcode: ${campaign.metaErrorSubcode ?? '-'}',
      'fbtrace_id: ${campaign.fbtraceId ?? '-'}',
    ];
    final text = lines.join('\n');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalles técnicos Meta Ads'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) Navigator.of(context).pop();
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _upsertCampaign(
    MarketingCampaign campaign, {
    bool keepGeneratingCopy = false,
  }) {
    final index = _campaigns.indexWhere((item) => item.id == campaign.id);
    if (index == -1) {
      _campaigns = [campaign, ..._campaigns];
    } else {
      final updated = [..._campaigns];
      updated[index] = campaign;
      _campaigns = updated;
    }
    _copyByCampaignId[campaign.id] = keepGeneratingCopy
        ? _CampaignCopy.generating()
        : _CampaignCopy.fromCampaign(campaign);
  }

  _CampaignCopy _copyFor(MarketingCampaign campaign) {
    return _copyByCampaignId[campaign.id] ??
        _CampaignCopy.fromCampaign(campaign);
  }

  double get _dailyBudget => double.tryParse(_dailyBudgetCtrl.text.trim()) ?? 0;

  Map<String, dynamic> _buildAudience() {
    return {
      'city': _cityCtrl.text.trim(),
      'radiusKm': _radiusKm,
      'ageMin': _ageRange.start.round(),
      'ageMax': _ageRange.end.round(),
      'interests': _selectedInterests.toList(growable: false),
      'objective': _fixedObjective,
      'gender': 'ALL',
    };
  }

  List<String> _extractSuggestedInterests(MarketingCampaign campaign) {
    final source = campaign.recommendedAudience ?? campaign.finalAudience ?? {};
    final raw = source['interests'];
    if (raw is! List) return const <String>[];
    return raw
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  String _detectMediaType(MarketingCampaign campaign) {
    final selected = _assets.where(
      (item) => _campaignMediaAssetId(item) == campaign.galleryAssetId,
    );
    if (selected.isEmpty) return 'Media';
    return selected.first.mimeType.toLowerCase().contains('video')
        ? 'Video'
        : 'Imagen';
  }

  String _estimateReachText(double budget) {
    if (budget <= 0) return 'Ingresa presupuesto para estimar alcance';
    final min = (budget * 22).round();
    final max = (budget * 41).round();
    return 'Alcance estimado: $min - $max personas/dia';
  }

  List<String> _cityOptions(MarketingCampaign campaign) {
    final options = <String>{_defaultCity, 'Higuey', 'Punta Cana', 'Bavaro'};
    final source = campaign.recommendedAudience ?? campaign.finalAudience ?? {};
    final city = '${source['city'] ?? ''}'.trim();
    if (city.isNotEmpty) options.add(city);
    final current = _cityCtrl.text.trim();
    if (current.isNotEmpty) options.add(current);
    return options.toList(growable: false)..sort();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canView =
        user != null &&
        hasPermission(user.appRole, AppPermission.viewPublicidad);

    if (!canView) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad / Campanas'),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final campaign = _selectedCampaign;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: CustomAppBar(
        title: 'Publicidad / Campanas',
        actions: [
          IconButton(
            tooltip: 'Configuración Meta Ads',
            onPressed: _openMetaTokenSettings,
            icon: const Icon(Icons.settings_rounded),
          ),
          IconButton(
            tooltip: 'Probar permisos Meta Ads',
            onPressed: _busyAction ? null : _testMetaAdsConnection,
            icon: const Icon(Icons.network_check_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busyAction || _loading ? null : _createDraft,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva campana'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState()
          : campaign == null
          ? _buildEmptyState()
          : _buildResponsiveBody(campaign),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.campaign_rounded,
            size: 52,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay campanas todavia',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Crea una campana y publica en minutos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveBody(MarketingCampaign campaign) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1120;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 1320 : 980),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: Alignment.centerRight,
                                child: AutosaveStatusIndicator(
                                  state: _autosaveState,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildSimplifiedForm(
                                campaign,
                                includePreviewSession: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(flex: 4, child: _buildPreviewRail(campaign)),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: AutosaveStatusIndicator(state: _autosaveState),
                        ),
                        const SizedBox(height: 8),
                        _buildSimplifiedForm(campaign),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSimplifiedForm(
    MarketingCampaign campaign, {
    bool includePreviewSession = true,
  }) {
    final cityOptions = _cityOptions(campaign);
    final sessions =
        <({Widget child, IconData icon, String subtitle, String title})>[
          (
            title: 'Imagen + Copy IA',
            subtitle:
                'Elige media publicada. La IA genera copys y preview sola.',
            icon: Icons.perm_media_rounded,
            child: _buildMediaStep(campaign),
          ),
          (
            title: 'Presupuesto + Destino',
            subtitle:
                'Presupuesto, destino WhatsApp FullTech, Higüey 10 km y edades 25-50.',
            icon: Icons.tune_rounded,
            child: _buildSegmentationBudgetSession(campaign, cityOptions),
          ),
        ];
    if (includePreviewSession) {
      sessions.add((
        title: 'Preview + Publicar',
        subtitle: 'Facebook Feed, Instagram Feed, Story y publicacion final.',
        icon: Icons.preview_rounded,
        child: _buildPreviewPublishSession(campaign),
      ));
    } else {
      sessions.add((
        title: 'Publicar',
        subtitle: 'Crea la campana WhatsApp Messages en Meta.',
        icon: Icons.send_rounded,
        child: _buildPublishPanel(campaign),
      ));
    }
    final activeIndex = _activeSessionIndex.clamp(0, sessions.length - 1);
    final activeSession = sessions[activeIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSessionSelector(),
        const SizedBox(height: 12),
        _StepCard(
          title: '${activeIndex + 1}. ${activeSession.title}',
          subtitle: activeSession.subtitle,
          child: activeSession.child,
        ),
      ],
    );
  }

  Widget _buildSessionSelector() {
    final items = const [
      (label: 'Imagen + IA', icon: Icons.perm_media_rounded),
      (label: 'Presupuesto', icon: Icons.payments_rounded),
      (label: 'Publicar', icon: Icons.send_rounded),
    ];
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        color: scheme.surfaceContainerLowest,
      ),
      child: Row(
        children: List.generate(items.length, (index) {
          final item = items[index];
          final selected = _activeSessionIndex == index;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == items.length - 1 ? 0 : 4,
              ),
              child: InkWell(
                onTap: () => setState(() => _activeSessionIndex = index),
                borderRadius: BorderRadius.circular(9),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    color: selected ? scheme.primary : Colors.transparent,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 17,
                        color: selected
                            ? scheme.onPrimary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: selected
                                    ? scheme.onPrimary
                                    : scheme.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMediaSelector(MarketingCampaign campaign) {
    final activeMediaId = _activeMediaAssetId(campaign);
    if (_assets.isEmpty) {
      return const Text(
        'No hay imagenes publicadas disponibles para campanas.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _assets.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            final asset = _assets[index];
            return _MediaAssetTile(
              asset: asset,
              isSelected: activeMediaId == _campaignMediaAssetId(asset),
              isBusy: _busyAction,
              onTap: () => _applyMediaAndAutoGenerate(asset),
            );
          },
        );
      },
    );
  }

  Widget _buildMediaStep(MarketingCampaign campaign) {
    final activeMedia = _selectedMediaAsset(campaign);
    final isChanging = _mediaChangeModeIds.contains(campaign.id);
    final hasActiveMedia = activeMedia != null && !isChanging;
    final copy = _copyFor(campaign);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMediaStatusBanner(hasActiveMedia: hasActiveMedia),
        if (activeMedia != null) ...[
          const SizedBox(height: 10),
          _buildSelectedMediaSummary(
            asset: activeMedia,
            isChanging: isChanging,
            onChange: _busyAction ? null : () => _startChangingMedia(campaign),
          ),
        ],
        if (isChanging || activeMedia == null) ...[
          const SizedBox(height: 14),
          Text(
            'Galeria',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Elige una pieza. El preview se actualiza y la IA regenera copys con investigacion publicitaria.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _buildMediaSelector(campaign),
        ],
        const SizedBox(height: 14),
        _buildAiCopyBlock(copy),
      ],
    );
  }

  Widget _buildMediaStatusBanner({required bool hasActiveMedia}) {
    final scheme = Theme.of(context).colorScheme;
    final color = hasActiveMedia ? scheme.primary : scheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        children: [
          Icon(
            hasActiveMedia
                ? Icons.check_circle_rounded
                : Icons.warning_amber_rounded,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasActiveMedia
                  ? 'Imagen seleccionada'
                  : 'Selecciona una imagen para continuar',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedMediaSummary({
    required MarketingMediaAsset asset,
    required bool isChanging,
    required VoidCallback? onChange,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final thumb = (asset.thumbnailUrl ?? asset.imageUrl).trim();
    final isVideo = asset.mimeType.toLowerCase().contains('video');
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final mediaInfo = Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 74,
                height: 58,
                child: thumb.isEmpty
                    ? ColoredBox(color: scheme.surfaceContainerHighest)
                    : Image.network(thumb, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isChanging ? 'Elige una nueva imagen' : 'Imagen activa',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    asset.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _Pill(label: isVideo ? 'Video' : 'Imagen'),
                ],
              ),
            ),
          ],
        );
        final changeButton = OutlinedButton.icon(
          onPressed: onChange,
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
          label: const Text('Cambiar imagen'),
        );

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: scheme.surfaceContainer.withValues(alpha: 0.5),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    mediaInfo,
                    const SizedBox(height: 10),
                    changeButton,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: mediaInfo),
                    const SizedBox(width: 10),
                    changeButton,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildAiCopyBlock(_CampaignCopy copy) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final statusIcon = Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: scheme.primaryContainer.withValues(alpha: 0.65),
          ),
          child: copy.isGenerating
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                )
              : Icon(Icons.auto_fix_high_rounded, color: scheme.primary),
        );
        final copyText = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                copy.isGenerating
                    ? 'IA generando copys automaticamente'
                    : 'Copys IA listos',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Usa imagen seleccionada, investigacion, ciudad, categoria e intencion comercial.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        );
        final regenerateButton = OutlinedButton.icon(
          onPressed: _busyAction ? null : _regenerateCopyOnly,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Regenerar copy'),
        );
        Widget copyField({
          required String label,
          required String value,
          required IconData icon,
        }) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: scheme.surfaceContainerLowest,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                    fontWeight: label == 'Titulo' ? FontWeight.w800 : null,
                  ),
                ),
              ],
            ),
          );
        }

        final copyDetails = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            copyField(
              label: 'Titulo',
              value: copy.headlineText,
              icon: Icons.title_rounded,
            ),
            const SizedBox(height: 8),
            copyField(
              label: 'Texto principal',
              value: copy.primaryTextValue,
              icon: Icons.notes_rounded,
            ),
            const SizedBox(height: 8),
            copyField(
              label: 'Descripcion',
              value: copy.descriptionText,
              icon: Icons.short_text_rounded,
            ),
            if (copy.hashtagsText.isNotEmpty) ...[
              const SizedBox(height: 8),
              copyField(
                label: 'Hashtags',
                value: copy.hashtagsText,
                icon: Icons.tag_rounded,
              ),
            ],
          ],
        );

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            color: scheme.surface,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        statusIcon,
                        const SizedBox(width: 10),
                        copyText,
                      ],
                    ),
                    const SizedBox(height: 10),
                    regenerateButton,
                    const SizedBox(height: 12),
                    copyDetails,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        statusIcon,
                        const SizedBox(width: 10),
                        copyText,
                        const SizedBox(width: 10),
                        regenerateButton,
                      ],
                    ),
                    const SizedBox(height: 12),
                    copyDetails,
                  ],
                ),
        );
      },
    );
  }

  String? _activeMediaAssetId(MarketingCampaign campaign) {
    if (_mediaChangeModeIds.contains(campaign.id)) return null;
    return campaign.galleryAssetId;
  }

  MarketingMediaAsset? _selectedMediaAsset(MarketingCampaign campaign) {
    final id = campaign.galleryAssetId;
    if (id == null) return null;
    for (final asset in _assets) {
      if (_campaignMediaAssetId(asset) == id) return asset;
    }
    return null;
  }

  Widget _buildSegmentationBudgetSession(
    MarketingCampaign campaign,
    List<String> cityOptions,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _cityCtrl.text.trim().isEmpty
              ? null
              : _cityCtrl.text.trim(),
          items: cityOptions
              .map(
                (city) =>
                    DropdownMenuItem<String>(value: city, child: Text(city)),
              )
              .toList(growable: false),
          onChanged: _busyAction
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() => _cityCtrl.text = value);
                  _scheduleAutosave();
                },
          decoration: const InputDecoration(
            labelText: 'Ciudad',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Text('Radio', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _radiusPresets
              .map(
                (preset) => ChoiceChip(
                  selected: _radiusKm == preset,
                  label: Text('$preset km'),
                  onSelected: _busyAction
                      ? null
                      : (_) {
                          setState(() => _radiusKm = preset);
                          _scheduleAutosave();
                        },
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Text(
          'Edades: ${_ageRange.start.round()} - ${_ageRange.end.round()}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        RangeSlider(
          min: 18,
          max: 65,
          divisions: 47,
          labels: RangeLabels(
            _ageRange.start.round().toString(),
            _ageRange.end.round().toString(),
          ),
          values: _ageRange,
          onChanged: _busyAction
              ? null
              : (value) {
                  setState(() => _ageRange = value);
                  _scheduleAutosave();
                },
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _dailyBudgetCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            prefixText: 'DOP ',
            labelText: 'Presupuesto diario',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) {
            setState(() {});
            _scheduleAutosave();
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _budgetPresets
              .map(
                (preset) => ChoiceChip(
                  selected: _dailyBudget.round() == preset,
                  label: Text('$preset'),
                  onSelected: _busyAction
                      ? null
                      : (_) {
                          setState(() => _dailyBudgetCtrl.text = '$preset');
                          _scheduleAutosave();
                        },
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Theme.of(
              context,
            ).colorScheme.tertiaryContainer.withValues(alpha: 0.45),
          ),
          child: Text(
            _estimateReachText(_dailyBudget),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        const SizedBox(height: 12),
        _buildFixedWhatsappDestination(),
        const SizedBox(height: 10),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Pill(label: 'Objetivo: Mensajes WhatsApp'),
            _Pill(label: 'CTA: Enviar mensaje'),
            _Pill(label: 'Default: Higüey · 10 km · 25-50'),
          ],
        ),
      ],
    );
  }

  Widget _buildFixedWhatsappDestination() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
        color: scheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Icon(Icons.mark_unread_chat_alt_rounded, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destino: WhatsApp FullTech',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '+1 829-534-4286',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const _Pill(label: 'No editable'),
        ],
      ),
    );
  }

  Widget _buildPublishPanel(MarketingCampaign campaign) {
    final hasAdsTokenConfigured = _metaAdsConfig.tokenPreview.trim().isNotEmpty;
    final permissions = _metaAdsPermissions;
    final canCreateMeta =
        permissions != null && _hasMinimumMetaAdsPermissions(permissions);
    final runtimeConfig = _metaRuntimeConfig;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Destino: WhatsApp FullTech',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                'Número: +1 829-534-4286',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Token: ${hasAdsTokenConfigured ? 'Meta Ads configurado ✅' : 'Meta Ads faltante ⚠️'}',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Cuenta Ads actual: ${runtimeConfig?.adAccountId.isNotEmpty == true ? runtimeConfig!.adAccountId : _defaultMetaAdAccountId}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Credencial equivalente: Token Meta Ads',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Modo: $_campaignModeLabel',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (permissions != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Token preview: ${permissions.tokenPreview.isEmpty ? '-' : permissions.tokenPreview}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'App ID: ${permissions.appId.isEmpty ? '-' : permissions.appId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Ad Account: ${permissions.adAccountId.isEmpty ? '-' : permissions.adAccountId}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  'Fuente token: ${permissions.tokenSource.isEmpty ? '-' : permissions.tokenSource}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  permissions.usingAdsAccessToken
                      ? 'Token usado: META_ADS_ACCESS_TOKEN ✅'
                      : 'Token usado: META_ADS_ACCESS_TOKEN ❌',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busyAction ? null : _openMetaTokenSettings,
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Configuración Meta Ads'),
            ),
            OutlinedButton.icon(
              onPressed: _busyAction ? null : _testMetaAdsConnection,
              icon: const Icon(Icons.network_check_rounded),
              label: const Text('Probar permisos Meta Ads'),
            ),
            OutlinedButton.icon(
              onPressed: _busyAction ? null : _testMetaAdsN8nLogic,
              icon: const Icon(Icons.hub_rounded),
              label: const Text('Probar con lógica n8n'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!canCreateMeta)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              permissions == null
                  ? 'No se pueden validar permisos de Meta Ads todavía. Usa "Probar permisos Meta Ads".'
                  : _buildMetaAdsPermissionErrorMessage(permissions),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _busyAction || !canCreateMeta ? null : _publishCampaign,
            icon: _busyAction
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(
              _busyAction
                  ? 'Publicando en Meta Ads...'
                  : campaign.status == MarketingCampaignStatus.error
                  ? 'Reintentar campaña en Meta'
                  : 'Crear campaña en Meta',
            ),
          ),
        ),
        if (_shouldShowPublishProgress(campaign)) ...[
          const SizedBox(height: 12),
          _buildPublishProgress(campaign),
        ],
      ],
    );
  }

  bool _shouldShowPublishProgress(MarketingCampaign campaign) {
    return _busyAction ||
        campaign.metaPublishProgress.isNotEmpty ||
        (campaign.metaCampaignId ?? '').isNotEmpty ||
        (campaign.metaError ?? '').isNotEmpty;
  }

  Widget _buildPublishProgress(MarketingCampaign campaign) {
    final progress = campaign.metaPublishProgress;
    final ids = <String, String?>{
      'Campaign ID': campaign.metaCampaignId,
      'AdSet ID': campaign.metaAdSetId,
      'Creative ID': campaign.metaCreativeId,
      'Ad ID': campaign.metaAdId,
      'Image hash': campaign.metaImageHash,
      'Video ID': campaign.metaVideoId,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                campaign.status == MarketingCampaignStatus.error
                    ? Icons.error_rounded
                    : Icons.ads_click_rounded,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  campaign.status == MarketingCampaignStatus.error
                      ? 'Error Meta Ads'
                      : 'Progreso Meta Ads',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if ((campaign.metaStatus ?? '').isNotEmpty)
                _Pill(label: campaign.metaStatus!),
            ],
          ),
          const SizedBox(height: 10),
          if (progress.isNotEmpty)
            ...progress.map(_buildPublishStep).toList(growable: false),
          if ((campaign.metaError ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              [
                campaign.metaError,
                if ((campaign.metaErrorCode ?? '').isNotEmpty)
                  'code=${campaign.metaErrorCode}',
                if ((campaign.metaErrorSubcode ?? '').isNotEmpty)
                  'subcode=${campaign.metaErrorSubcode}',
                if ((campaign.fbtraceId ?? '').isNotEmpty)
                  'fbtrace_id=${campaign.fbtraceId}',
              ].whereType<String>().join(' · '),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if ((campaign.metaCampaignId ?? '').isNotEmpty &&
              campaign.status != MarketingCampaignStatus.error) ...[
            const SizedBox(height: 8),
            const _Pill(label: 'Estado: Pausada / Lista para activar'),
          ],
          if (ids.values.any((value) => (value ?? '').trim().isNotEmpty)) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ids.entries
                  .where((entry) => (entry.value ?? '').trim().isNotEmpty)
                  .map(
                    (entry) =>
                        _MetaIdChip(label: entry.key, value: entry.value!),
                  )
                  .toList(growable: false),
            ),
          ],
          if ((campaign.metaCampaignId ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busyAction ? null : _activateCampaign,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Activar campaña'),
                ),
                OutlinedButton.icon(
                  onPressed: _busyAction ? null : _pauseCampaign,
                  icon: const Icon(Icons.pause_rounded),
                  label: const Text('Pausar campaña'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showTechnicalDetails(campaign),
                  icon: const Icon(Icons.info_outline_rounded),
                  label: const Text('Ver detalles técnicos'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPublishStep(Map<String, dynamic> step) {
    final status = '${step['status'] ?? 'PENDING'}'.toUpperCase();
    final label = '${step['label'] ?? ''}'.trim();
    final detail = '${step['detail'] ?? ''}'.trim();
    final colorScheme = Theme.of(context).colorScheme;
    final icon = switch (status) {
      'DONE' => Icons.check_circle_rounded,
      'RUNNING' => Icons.sync_rounded,
      'ERROR' => Icons.error_rounded,
      _ => Icons.radio_button_unchecked_rounded,
    };
    final color = switch (status) {
      'DONE' => Colors.green.shade700,
      'RUNNING' => colorScheme.primary,
      'ERROR' => colorScheme.error,
      _ => colorScheme.outline,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (detail.isNotEmpty)
                  SelectableText(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPublishSession(MarketingCampaign campaign) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLargePreview(campaign),
        const SizedBox(height: 12),
        _buildPublishPanel(campaign),
      ],
    );
  }

  Widget _buildPreviewRail(MarketingCampaign campaign) {
    return _StepCard(
      title: 'Preview Meta Ads',
      subtitle: 'WhatsApp Messages fijo: Feed, Instagram y Story.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLargePreview(campaign, showHeader: false),
          const SizedBox(height: 12),
          _buildPublishPanel(campaign),
        ],
      ),
    );
  }

  Widget _buildLargePreview(
    MarketingCampaign campaign, {
    bool showHeader = true,
  }) {
    final image = campaign.finalDesignUrl ?? campaign.baseImageUrl ?? '';
    final mediaType = _detectMediaType(campaign);
    final copy = _copyFor(campaign);
    final headline = copy.headlineText;
    final primaryText = copy.primaryTextValue;
    final description = copy.descriptionText;
    final hashtags = copy.hashtagsText;

    Widget mediaBox(double height) {
      return image.trim().isEmpty
          ? Container(
              height: height,
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: const Center(child: Text('Sin media seleccionada')),
            )
          : Image.network(
              image,
              height: height,
              width: double.infinity,
              fit: BoxFit.cover,
            );
    }

    Widget feedPreview(String label, double height) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          color: scheme.surface,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      'F',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FULLTECH',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Patrocinado · $label',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  _Pill(label: mediaType),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                primaryText,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            mediaBox(height),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (hashtags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            hashtags,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                    label: const Text('Enviar mensaje'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget storyPreview() {
      return Container(
        width: double.infinity,
        height: 420,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          color: Colors.black,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            image.trim().isEmpty
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Text(
                        'Sin media seleccionada',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                : Image.network(image, fit: BoxFit.cover),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  const CircleAvatar(radius: 16, child: Text('F')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FULLTECH',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          'Patrocinado',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                        ),
                      ],
                    ),
                  ),
                  _Pill(label: mediaType),
                ],
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    headline,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    primaryText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 22,
              child: FilledButton.icon(
                onPressed: null,
                icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                label: const Text('Enviar mensaje'),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Preview Meta Ads',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (copy.isGenerating)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        feedPreview('Facebook Feed', 240),
        feedPreview('Instagram Feed', 260),
        storyPreview(),
      ],
    );
  }
}

class _CampaignCopy {
  const _CampaignCopy({
    required this.headline,
    required this.primaryText,
    required this.description,
    required this.hashtags,
    required this.isGenerating,
  });

  final String headline;
  final String primaryText;
  final String description;
  final List<String> hashtags;
  final bool isGenerating;

  factory _CampaignCopy.fromCampaign(MarketingCampaign campaign) {
    return _CampaignCopy(
      headline: (campaign.headline ?? '').trim(),
      primaryText: (campaign.primaryText ?? '').trim(),
      description: (campaign.description ?? '').trim(),
      hashtags: campaign.hashtags,
      isGenerating: false,
    );
  }

  factory _CampaignCopy.generating() {
    return const _CampaignCopy(
      headline: '',
      primaryText: '',
      description: '',
      hashtags: <String>[],
      isGenerating: true,
    );
  }

  String get headlineText => _realText(headline);
  String get primaryTextValue => _realText(primaryText);
  String get descriptionText => _realText(description);
  bool get hasRealCopy =>
      headline.trim().isNotEmpty &&
      primaryText.trim().isNotEmpty &&
      description.trim().isNotEmpty;
  String get hashtagsText => hashtags
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .map((tag) => tag.startsWith('#') ? tag : '#$tag')
      .join(' ');

  static String _realText(String value) {
    final clean = value.trim();
    return clean.isEmpty ? 'Generando copy...' : clean;
  }
}

class _MetaIdChip extends StatelessWidget {
  const _MetaIdChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MediaAssetTile extends StatefulWidget {
  const _MediaAssetTile({
    required this.asset,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
  });

  final MarketingMediaAsset asset;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  State<_MediaAssetTile> createState() => _MediaAssetTileState();
}

class _MediaAssetTileState extends State<_MediaAssetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumb = (widget.asset.thumbnailUrl ?? widget.asset.imageUrl).trim();
    final isVideo = widget.asset.mimeType.toLowerCase().contains('video');
    final borderColor = widget.isSelected
        ? scheme.primary
        : (_hovered
              ? scheme.primary.withValues(alpha: 0.55)
              : scheme.outlineVariant.withValues(alpha: 0.55));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.isBusy ? null : widget.onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected ? 2.4 : 1.2,
            ),
            color: widget.isSelected
                ? scheme.primaryContainer.withValues(alpha: 0.32)
                : (_hovered ? scheme.surfaceContainer : scheme.surface),
            boxShadow: _hovered || widget.isSelected
                ? [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : const [],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: thumb.isEmpty
                          ? ColoredBox(color: scheme.surfaceContainerHighest)
                          : Image.network(thumb, fit: BoxFit.cover),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.asset.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _Pill(label: isVideo ? 'Video' : 'Imagen'),
                            if (widget.asset.category.trim().isNotEmpty)
                              _Pill(label: widget.asset.category.trim()),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (widget.isSelected)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary,
                      border: Border.all(color: scheme.surface, width: 2),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 19,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              if (widget.isBusy)
                Positioned.fill(
                  child: ColoredBox(
                    color: scheme.surface.withValues(alpha: 0.52),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.secondaryContainer,
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _MetaRuntimeConfigPayload {
  const _MetaRuntimeConfigPayload({
    required this.graphVersion,
    required this.appId,
    required this.appSecret,
    required this.adAccountId,
    required this.campaignMode,
    required this.pageId,
    required this.instagramBusinessId,
    required this.whatsappPhoneNumberId,
    required this.whatsappBusinessAccountId,
    required this.businessId,
    required this.adsAccessToken,
  });

  final String graphVersion;
  final String appId;
  final String appSecret;
  final String adAccountId;
  final String campaignMode;
  final String pageId;
  final String instagramBusinessId;
  final String whatsappPhoneNumberId;
  final String whatsappBusinessAccountId;
  final String businessId;
  final String? adsAccessToken;
}

class _MetaRuntimeConfigDialog extends StatefulWidget {
  const _MetaRuntimeConfigDialog({required this.initial});

  final MetaRuntimeConfigDebug initial;

  @override
  State<_MetaRuntimeConfigDialog> createState() =>
      _MetaRuntimeConfigDialogState();
}

class _MetaRuntimeConfigDialogState extends State<_MetaRuntimeConfigDialog> {
  final _formKey = GlobalKey<FormState>();
  static const List<DropdownMenuItem<String>> _campaignModeItems = [
    DropdownMenuItem(
      value: 'DIRECT_VIDEO_URL',
      child: Text('Video URL directo'),
    ),
    DropdownMenuItem(
      value: 'DIRECT_IMAGE_URL',
      child: Text('Imagen URL directa'),
    ),
    DropdownMenuItem(
      value: 'ADIMAGES_UPLOAD',
      child: Text('Imagen subida a AdImages'),
    ),
  ];
  late final TextEditingController _graphVersionCtrl;
  late final TextEditingController _appIdCtrl;
  late final TextEditingController _appSecretCtrl;
  late final TextEditingController _adAccountCtrl;
  late final TextEditingController _pageIdCtrl;
  late final TextEditingController _instagramIdCtrl;
  late final TextEditingController _whatsappIdCtrl;
  late final TextEditingController _whatsappBusinessIdCtrl;
  late final TextEditingController _businessIdCtrl;
  late final TextEditingController _adsTokenCtrl;
  late String _campaignMode;

  @override
  void initState() {
    super.initState();
    _graphVersionCtrl = TextEditingController(
      text: widget.initial.graphVersion,
    );
    _appIdCtrl = TextEditingController(text: widget.initial.appId);
    _appSecretCtrl = TextEditingController();
    _adAccountCtrl = TextEditingController(
      text: widget.initial.adAccountId.isEmpty
          ? _PublicidadCampanasScreenV2State._defaultMetaAdAccountId
          : widget.initial.adAccountId,
    );
    _pageIdCtrl = TextEditingController(text: widget.initial.pageId);
    _instagramIdCtrl = TextEditingController(
      text: widget.initial.instagramBusinessId,
    );
    _whatsappIdCtrl = TextEditingController(
      text: widget.initial.whatsappPhoneNumberId,
    );
    _whatsappBusinessIdCtrl = TextEditingController(
      text: widget.initial.whatsappBusinessAccountId,
    );
    _businessIdCtrl = TextEditingController(text: widget.initial.businessId);
    _adsTokenCtrl = TextEditingController();
    _campaignMode = widget.initial.campaignMode.isEmpty
        ? 'DIRECT_IMAGE_URL'
        : widget.initial.campaignMode;
  }

  @override
  void dispose() {
    _graphVersionCtrl.dispose();
    _appIdCtrl.dispose();
    _appSecretCtrl.dispose();
    _adAccountCtrl.dispose();
    _pageIdCtrl.dispose();
    _instagramIdCtrl.dispose();
    _whatsappIdCtrl.dispose();
    _whatsappBusinessIdCtrl.dispose();
    _businessIdCtrl.dispose();
    _adsTokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configuración Meta Ads'),
      content: SizedBox(
        width: 640,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Configura las credenciales exclusivas de Meta Ads para campañas.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _graphVersionCtrl,
                  decoration: const InputDecoration(labelText: 'Graph version'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _appIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'META_ADS_APP_ID',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _appSecretCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'META_ADS_APP_SECRET',
                    helperText: widget.initial.appSecretConfigured
                        ? 'Ya configurado. Déjalo vacío para no reemplazar.'
                        : 'Obligatorio para validar debug_token.',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _adAccountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'META_AD_ACCOUNT_ID',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _campaignMode,
                  items: _campaignModeItems,
                  decoration: const InputDecoration(
                    labelText: 'Modo de campaña',
                  ),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _campaignMode = value);
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _pageIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'META_FACEBOOK_PAGE_ID',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _instagramIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'META_INSTAGRAM_BUSINESS_ID',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _whatsappIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'META_WHATSAPP_PHONE_NUMBER_ID',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _whatsappBusinessIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'META_WHATSAPP_BUSINESS_ACCOUNT_ID (opcional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _businessIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'META_BUSINESS_ID',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _adsTokenCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Token Ads (META_ADS_ACCESS_TOKEN)',
                    helperText:
                        'Actual: ${widget.initial.adsTokenPreview.isEmpty ? '-' : widget.initial.adsTokenPreview}',
                  ),
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
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop(
              _MetaRuntimeConfigPayload(
                graphVersion: _graphVersionCtrl.text.trim(),
                appId: _appIdCtrl.text.trim(),
                appSecret: _appSecretCtrl.text.trim(),
                adAccountId: _adAccountCtrl.text.trim().isEmpty
                    ? _PublicidadCampanasScreenV2State._defaultMetaAdAccountId
                    : _adAccountCtrl.text.trim(),
                campaignMode: _campaignMode,
                pageId: _pageIdCtrl.text.trim(),
                instagramBusinessId: _instagramIdCtrl.text.trim(),
                whatsappPhoneNumberId: _whatsappIdCtrl.text.trim(),
                whatsappBusinessAccountId: _whatsappBusinessIdCtrl.text.trim(),
                businessId: _businessIdCtrl.text.trim(),
                adsAccessToken: _adsTokenCtrl.text.trim().isEmpty
                    ? null
                    : _adsTokenCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Guardar configuración'),
        ),
      ],
    );
  }
}
