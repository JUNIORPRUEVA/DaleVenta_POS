import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../marketing_api.dart';
import '../marketing_campaign_models.dart';

/// Autosave state for campaign drafts
class AutosaveState {
  final bool isLoading;
  final bool hasUnsavedChanges;
  final String? lastSavedAt;
  final String? error;

  AutosaveState({
    this.isLoading = false,
    this.hasUnsavedChanges = false,
    this.lastSavedAt,
    this.error,
  });

  AutosaveState copyWith({
    bool? isLoading,
    bool? hasUnsavedChanges,
    String? lastSavedAt,
    String? error,
  }) {
    return AutosaveState(
      isLoading: isLoading ?? this.isLoading,
      hasUnsavedChanges: hasUnsavedChanges ?? this.hasUnsavedChanges,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
      error: error ?? this.error,
    );
  }
}

/// Tracks unsaved changes and triggers autosave with debounce
class CampaignAutosaveController extends StateNotifier<AutosaveState> {
  final MarketingApi _api;
  Timer? _debounceTimer;
  final Duration _debounceDuration;

  MarketingCampaign? _currentCampaign;
  MarketingCampaign? _pendingChanges;

  CampaignAutosaveController(
    this._api, {
    Duration debounceDuration = const Duration(milliseconds: 800),
  }) : _debounceDuration = debounceDuration,
       super(AutosaveState());

  /// Set the current campaign
  void setCampaign(MarketingCampaign campaign) {
    _currentCampaign = campaign;
    _pendingChanges = null;
    state = AutosaveState();
  }

  /// Mark changes pending and trigger autosave after debounce
  void markChanged(MarketingCampaign updated) {
    _pendingChanges = updated;

    if (state.isLoading) return;

    state = state.copyWith(hasUnsavedChanges: true, error: null);

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, _performAutosave);
  }

  /// Perform the actual save
  Future<void> _performAutosave() async {
    if (_pendingChanges == null || _currentCampaign == null) return;

    state = state.copyWith(isLoading: true);

    try {
      await _api.updateCampaign(
        _pendingChanges!.id,
        headline: _pendingChanges!.headline,
        primaryText: _pendingChanges!.primaryText,
        description: _pendingChanges!.description,
        cta: _pendingChanges!.cta ?? 'WHATSAPP_MESSAGE',
        dailyBudget: _pendingChanges!.dailyBudget,
        totalBudget: _pendingChanges!.totalBudget,
        whatsappPhone: _pendingChanges!.whatsappPhone,
        destinationUrl: _pendingChanges!.destinationUrl,
        finalAudience: _pendingChanges!.finalAudience,
      );

      _currentCampaign = _pendingChanges;
      _pendingChanges = null;

      state = state.copyWith(
        isLoading: false,
        hasUnsavedChanges: false,
        lastSavedAt: DateTime.now().toString(),
        error: null,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        hasUnsavedChanges: true,
        error: 'Error al guardar: $e',
      );
    }
  }

  /// Force immediate save (don't wait for debounce)
  Future<void> forceSave() async {
    _debounceTimer?.cancel();
    await _performAutosave();
  }

  /// Clear error message
  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Provider for autosave controller
final campaignAutosaveProvider =
    StateNotifierProvider.family<
      CampaignAutosaveController,
      AutosaveState,
      String
    >((ref, campaignId) {
      final api = ref.watch(marketingApiProvider);
      return CampaignAutosaveController(api);
    });
