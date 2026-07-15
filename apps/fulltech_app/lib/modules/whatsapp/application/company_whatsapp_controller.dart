import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/company_whatsapp_repository.dart';
import '../whatsapp_instance_model.dart';

class CompanyWhatsappState {
  final bool isLoading;
  final bool isCreating;
  final WhatsappInstanceStatusResponse? instance;
  final WhatsappQrResponse? qr;
  final String? error;
  final String? qrError;

  const CompanyWhatsappState({
    this.isLoading = false,
    this.isCreating = false,
    this.instance,
    this.qr,
    this.error,
    this.qrError,
  });

  CompanyWhatsappState copyWith({
    bool? isLoading,
    bool? isCreating,
    WhatsappInstanceStatusResponse? instance,
    WhatsappQrResponse? qr,
    String? error,
    String? qrError,
    bool clearError = false,
    bool clearQrError = false,
    bool clearInstance = false,
    bool clearQr = false,
  }) {
    return CompanyWhatsappState(
      isLoading: isLoading ?? this.isLoading,
      isCreating: isCreating ?? this.isCreating,
      instance: clearInstance ? null : (instance ?? this.instance),
      qr: clearQr ? null : (qr ?? this.qr),
      error: clearError ? null : (error ?? this.error),
      qrError: clearQrError ? null : (qrError ?? this.qrError),
    );
  }
}

final companyWhatsappControllerProvider =
    StateNotifierProvider<CompanyWhatsappController, CompanyWhatsappState>(
      (ref) => CompanyWhatsappController(
        ref.watch(companyWhatsappRepositoryProvider),
      ),
    );

class CompanyWhatsappController extends StateNotifier<CompanyWhatsappState> {
  final CompanyWhatsappRepository _repo;
  Timer? _pollTimer;

  CompanyWhatsappController(this._repo) : super(const CompanyWhatsappState());

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> loadStatus() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repo.getStatus();
      if (!mounted) return;
      state = state.copyWith(isLoading: false, instance: result);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  Future<void> createInstance({
    String? instanceName,
    String? phoneNumber,
  }) async {
    if (state.isCreating) return;
    state = state.copyWith(isCreating: true, clearError: true);
    try {
      await _repo.createInstance(
        instanceName: instanceName,
        phoneNumber: phoneNumber,
      );
      if (!mounted) return;
      final result = await _repo.getStatus();
      if (!mounted) return;
      state = state.copyWith(isCreating: false, instance: result);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isCreating: false, error: '$e');
    }
  }

  Future<void> deleteInstance() async {
    state = state.copyWith(clearError: true);
    try {
      await _repo.deleteInstance();
      if (!mounted) return;
      _stopPolling();
      state = state.copyWith(
        clearInstance: true,
        clearQr: true,
        clearQrError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> refreshQr() async {
    state = state.copyWith(clearQrError: true);
    try {
      final current = await _repo.getStatus();
      if (!mounted) return;
      state = state.copyWith(instance: current);
      if (current.isConnected) {
        _stopPolling();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(qrError: 'Error validando estado: $e');
      return;
    }
    try {
      final qr = await _repo.getQr();
      if (!mounted) return;
      state = state.copyWith(qr: qr);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(qrError: '$e');
    }
  }

  void stopPolling() => _stopPolling();

  void startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) {
        _stopPolling();
        return;
      }
      try {
        final result = await _repo.getStatus();
        if (!mounted) return;
        state = state.copyWith(instance: result);
        if (result.isConnected) _stopPolling();
      } catch (_) {}
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
