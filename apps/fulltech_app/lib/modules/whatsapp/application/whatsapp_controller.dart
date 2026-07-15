import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/whatsapp_instance_repository.dart';
import '../whatsapp_instance_model.dart';

class WhatsappState {
  final bool isLoading;
  final bool isCreating;
  final bool isRefreshing;
  final WhatsappInstanceStatusResponse? instance;
  final WhatsappQrResponse? qr;
  final List<WhatsappAdminUserEntry> adminUsers;
  final bool adminUsersLoading;
  final String? error;
  final String? qrError;

  const WhatsappState({
    this.isLoading = false,
    this.isCreating = false,
    this.isRefreshing = false,
    this.instance,
    this.qr,
    this.adminUsers = const [],
    this.adminUsersLoading = false,
    this.error,
    this.qrError,
  });

  WhatsappState copyWith({
    bool? isLoading,
    bool? isCreating,
    bool? isRefreshing,
    WhatsappInstanceStatusResponse? instance,
    WhatsappQrResponse? qr,
    List<WhatsappAdminUserEntry>? adminUsers,
    bool? adminUsersLoading,
    String? error,
    String? qrError,
    bool clearError = false,
    bool clearQrError = false,
    bool clearInstance = false,
    bool clearQr = false,
  }) {
    return WhatsappState(
      isLoading: isLoading ?? this.isLoading,
      isCreating: isCreating ?? this.isCreating,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      instance: clearInstance ? null : (instance ?? this.instance),
      qr: clearQr ? null : (qr ?? this.qr),
      adminUsers: adminUsers ?? this.adminUsers,
      adminUsersLoading: adminUsersLoading ?? this.adminUsersLoading,
      error: clearError ? null : (error ?? this.error),
      qrError: clearQrError ? null : (qrError ?? this.qrError),
    );
  }
}

final whatsappControllerProvider =
    StateNotifierProvider<WhatsappController, WhatsappState>((ref) {
      return WhatsappController(ref.watch(whatsappInstanceRepositoryProvider));
    });

class WhatsappController extends StateNotifier<WhatsappState> {
  final WhatsappInstanceRepository _repo;
  Timer? _pollTimer;

  WhatsappController(this._repo) : super(const WhatsappState());

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Carga el estado de la instancia del usuario.
  Future<void> loadInstance() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final result = await _repo.getInstanceStatus();
      if (!mounted) return;
      state = state.copyWith(isLoading: false, instance: result);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: '$e');
    }
  }

  /// Crea una nueva instancia de WhatsApp.
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
      // Reload status after creation
      final result = await _repo.getInstanceStatus();
      if (!mounted) return;
      state = state.copyWith(isCreating: false, instance: result);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isCreating: false, error: '$e');
    }
  }

  /// Elimina la instancia de WhatsApp del usuario.
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

  /// Obtiene el código QR para conectar WhatsApp.
  /// Valida el estado antes de solicitar el QR:
  /// - Si la instancia no existe, la crea primero.
  /// - Si ya está conectada, no solicita el QR.
  Future<void> refreshQr() async {
    state = state.copyWith(clearQrError: true);

    // Refresh instance status first
    try {
      final current = await _repo.getInstanceStatus();
      if (!mounted) return;
      state = state.copyWith(instance: current);

      // Already connected — no need for QR
      if (current.isConnected) {
        _stopPolling();
        return;
      }

      // Instance does not exist — create it first
      if (!current.exists) {
        state = state.copyWith(isCreating: true);
        await _repo.createInstance();
        if (!mounted) return;
        state = state.copyWith(isCreating: false);
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(qrError: 'Error validando estado: $e');
      return;
    }

    // Request QR
    try {
      final qr = await _repo.getQrCode();
      if (!mounted) return;
      state = state.copyWith(qr: qr);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(qrError: '$e');
    }
  }

  /// Detiene el polling de estado.
  void stopPolling() => _stopPolling();

  /// Inicia polling cada 5 segundos para verificar si WhatsApp se conectó.
  void startPolling() {
    _stopPolling();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted) {
        _stopPolling();
        return;
      }
      try {
        final result = await _repo.getInstanceStatus();
        if (!mounted) return;
        state = state.copyWith(instance: result, isRefreshing: false);
        if (result.isConnected) {
          _stopPolling();
        }
      } catch (_) {
        // Silently skip poll errors
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Carga lista de usuarios con estado WhatsApp (solo admin).
  Future<void> loadAdminUsers() async {
    if (state.adminUsersLoading) return;
    state = state.copyWith(adminUsersLoading: true);
    try {
      final users = await _repo.getAdminUsers();
      if (!mounted) return;
      state = state.copyWith(adminUsers: users, adminUsersLoading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(adminUsersLoading: false, error: '$e');
    }
  }
}
