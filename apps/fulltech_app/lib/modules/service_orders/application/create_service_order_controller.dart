import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/user_model.dart';
import '../../clientes/cliente_model.dart';
import '../../clientes/data/clientes_repository.dart';
import '../../cotizaciones/cotizacion_models.dart';
import '../../cotizaciones/data/cotizaciones_repository.dart';
import '../data/service_orders_api.dart';
import '../data/upload_repository.dart';
import '../service_order_models.dart';
import '../../../features/user/data/users_repository.dart';

class CreateServiceOrderState {
  final bool loading;
  final bool submitting;
  final bool initialized;
  final String? error;
  final String? actionError;
  final List<ClienteModel> clients;
  final List<CotizacionModel> quotations;
  final List<UserModel> technicians;
  final List<ServiceOrderDraftReference> references;
  final ClienteModel? selectedClient;
  final CotizacionModel? selectedQuotation;
  final UserModel? selectedTechnician;
  final DateTime? scheduledFor;
  final ServiceOrderCategory category;
  final ServiceOrderType? serviceType;
  final ServiceOrderModel? cloneSource;
  final ServiceOrderModel? editSource;
  final String? quotationMessage;
  final bool uploadingEvidence;
  final double uploadProgress;
  final String? uploadLabel;

  const CreateServiceOrderState({
    this.loading = false,
    this.submitting = false,
    this.initialized = false,
    this.error,
    this.actionError,
    this.clients = const [],
    this.quotations = const [],
    this.technicians = const [],
    this.references = const [],
    this.selectedClient,
    this.selectedQuotation,
    this.selectedTechnician,
    this.scheduledFor,
    this.category = ServiceOrderCategory.camara,
    this.serviceType,
    this.cloneSource,
    this.editSource,
    this.quotationMessage,
    this.uploadingEvidence = false,
    this.uploadProgress = 0,
    this.uploadLabel,
  });

  bool get isCloneMode => cloneSource != null;
  bool get isEditMode => editSource != null;

  CreateServiceOrderState copyWith({
    bool? loading,
    bool? submitting,
    bool? initialized,
    String? error,
    String? actionError,
    List<ClienteModel>? clients,
    List<CotizacionModel>? quotations,
    List<UserModel>? technicians,
    List<ServiceOrderDraftReference>? references,
    ClienteModel? selectedClient,
    CotizacionModel? selectedQuotation,
    UserModel? selectedTechnician,
    DateTime? scheduledFor,
    ServiceOrderCategory? category,
    ServiceOrderType? serviceType,
    ServiceOrderModel? cloneSource,
    ServiceOrderModel? editSource,
    String? quotationMessage,
    bool? uploadingEvidence,
    double? uploadProgress,
    String? uploadLabel,
    bool clearError = false,
    bool clearActionError = false,
    bool clearSelectedQuotation = false,
    bool clearSelectedTechnician = false,
    bool clearQuotationMessage = false,
    bool clearUploadLabel = false,
  }) {
    return CreateServiceOrderState(
      loading: loading ?? this.loading,
      submitting: submitting ?? this.submitting,
      initialized: initialized ?? this.initialized,
      error: clearError ? null : (error ?? this.error),
      actionError: clearActionError ? null : (actionError ?? this.actionError),
      clients: clients ?? this.clients,
      quotations: quotations ?? this.quotations,
      technicians: technicians ?? this.technicians,
      references: references ?? this.references,
      selectedClient: selectedClient ?? this.selectedClient,
      selectedQuotation: clearSelectedQuotation
          ? null
          : (selectedQuotation ?? this.selectedQuotation),
      selectedTechnician: clearSelectedTechnician
          ? null
          : (selectedTechnician ?? this.selectedTechnician),
      scheduledFor: scheduledFor ?? this.scheduledFor,
      category: category ?? this.category,
      serviceType: serviceType ?? this.serviceType,
      cloneSource: cloneSource ?? this.cloneSource,
      editSource: editSource ?? this.editSource,
      quotationMessage: clearQuotationMessage
          ? null
          : (quotationMessage ?? this.quotationMessage),
      uploadingEvidence: uploadingEvidence ?? this.uploadingEvidence,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadLabel: clearUploadLabel ? null : (uploadLabel ?? this.uploadLabel),
    );
  }
}

class CreateServiceOrderSubmissionResult {
  final ServiceOrderModel order;
  final String? warningMessage;

  const CreateServiceOrderSubmissionResult({
    required this.order,
    this.warningMessage,
  });
}

final createServiceOrderControllerProvider = StateNotifierProvider.autoDispose
    .family<
      CreateServiceOrderController,
      CreateServiceOrderState,
      ServiceOrderCreateArgs?
    >((ref, args) {
      return CreateServiceOrderController(ref, args)..load();
    });

class CreateServiceOrderController
    extends StateNotifier<CreateServiceOrderState> {
  CreateServiceOrderController(this.ref, this.args)
    : super(
        CreateServiceOrderState(
          cloneSource: args?.cloneSource,
          editSource: args?.editSource,
          scheduledFor:
              args?.editSource?.scheduledFor ?? args?.cloneSource?.scheduledFor,
          category:
              args?.editSource?.category ??
              args?.cloneSource?.category ??
              ServiceOrderCategory.camara,
        ),
      );

  final Ref ref;
  final ServiceOrderCreateArgs? args;

  String get _ownerId => ref.read(authStateProvider).user?.id ?? '';
  String get _currentRoleKey =>
      normalizeRoleKey(ref.read(authStateProvider).user?.role);
  AppRole get _currentRole =>
      ref.read(authStateProvider).user?.appRole ?? AppRole.unknown;
  bool get _isCreatorEditingOrder =>
      args?.isEditMode == true && args?.editSource?.createdById == _ownerId;
  bool get _canEditOperationalNotes =>
      _currentRole == AppRole.tecnico ||
      _currentRole == AppRole.admin ||
      _currentRoleKey.contains('tecn') ||
      _currentRoleKey.contains('admin') ||
      _isCreatorEditingOrder;
  bool get _canAssignTechnician =>
      _currentRole == AppRole.admin ||
      _currentRole == AppRole.asistente ||
      _currentRole == AppRole.vendedor ||
      _currentRole == AppRole.marketing ||
      _currentRole == AppRole.tecnico ||
      _currentRoleKey.contains('admin') ||
      _currentRoleKey.contains('asist') ||
      _currentRoleKey.contains('vend') ||
      _currentRoleKey.contains('mark') ||
      _currentRoleKey.contains('tecn') ||
      _isCreatorEditingOrder;

  Future<List<UserModel>> _loadTechnicians() async {
    final users = await ref
        .read(usersRepositoryProvider)
        .getAllUsers(forceRefresh: true, skipLoader: true);
    return users
        .where(
          (user) =>
              user.appRole == AppRole.tecnico ||
              normalizeRoleKey(user.role).contains('tecn'),
        )
        .toList(growable: false);
  }

  Future<void> ensureTechniciansLoaded() async {
    if (!_canAssignTechnician ||
        state.loading ||
        state.technicians.isNotEmpty) {
      return;
    }
    try {
      final technicians = await _loadTechnicians();
      state = state.copyWith(technicians: technicians, clearActionError: true);
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo cargar la lista de técnicos';
      state = state.copyWith(actionError: message);
    }
  }

  Future<void> load() async {
    if (state.initialized || state.loading) return;
    state = state.copyWith(
      loading: true,
      clearError: true,
      clearActionError: true,
    );
    try {
      final clients = await ref
          .read(clientesRepositoryProvider)
          .listClients(ownerId: _ownerId, pageSize: 200);
      var technicians = const <UserModel>[];
      if (_canAssignTechnician) {
        try {
          technicians = await _loadTechnicians();
        } catch (_) {
          // Keep form usable even if user listing fails due role/endpoint restrictions.
          technicians = const <UserModel>[];
        }
      }
      final seedOrder = args?.editSource ?? args?.cloneSource;
      final seedQuotation = args?.initialQuotation;
      final seedClientId =
          (seedOrder?.clientId ??
                  args?.initialClientId ??
                  seedQuotation?.customerId ??
                  '')
              .trim();
      final selectedClient = seedClientId.isEmpty
          ? null
          : clients
                .where((item) => item.id == seedClientId)
                .firstWhere(
                  (item) => true,
                  orElse: () => ClienteModel(
                    id: seedClientId,
                    ownerId: _ownerId,
                    nombre: (seedQuotation?.customerName ?? 'Cliente vinculado')
                        .trim(),
                    telefono: (seedQuotation?.customerPhone ?? '').trim(),
                  ),
                );
      final assignedToId = seedOrder?.assignedToId;
      final selectedTechnician = assignedToId == null
          ? null
          : technicians
                .where((item) => item.id == assignedToId)
                .firstWhere(
                  (item) => true,
                  orElse: () => UserModel(
                    id: assignedToId,
                    email: '',
                    nombreCompleto: 'Técnico asignado',
                    telefono: '',
                    role: 'TECNICO',
                  ),
                );
      state = state.copyWith(
        loading: false,
        initialized: true,
        clients: clients,
        technicians: technicians,
        selectedClient: selectedClient,
        selectedTechnician: selectedTechnician,
        scheduledFor: seedOrder?.scheduledFor,
        serviceType: seedOrder?.serviceType,
      );
      if (selectedClient != null) {
        await selectClient(
          selectedClient,
          preserveQuotationId: seedOrder?.quotationId ?? seedQuotation?.id,
        );
      }
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo preparar el formulario';
      state = state.copyWith(loading: false, initialized: true, error: message);
    }
  }

  Future<void> selectClient(
    ClienteModel client, {
    String? preserveQuotationId,
  }) async {
    final normalizedPreserveQuotationId = (preserveQuotationId ?? '').trim();
    state = state.copyWith(
      selectedClient: client,
      quotations: const [],
      clearSelectedQuotation: true,
      clearError: true,
      clearActionError: true,
      clearQuotationMessage: true,
      loading: true,
    );
    try {
      final quotations = await ref
          .read(cotizacionesRepositoryProvider)
          .listAndCache(take: 200);
      final nextQuotations = [...quotations];
      CotizacionModel? selectedQuotation;
      if (normalizedPreserveQuotationId.isNotEmpty) {
        for (final quotation in nextQuotations) {
          if (quotation.id == normalizedPreserveQuotationId) {
            selectedQuotation = quotation;
            break;
          }
        }
        if (selectedQuotation == null) {
          try {
            final preservedQuotation = await ref
                .read(cotizacionesRepositoryProvider)
                .getByIdAndCache(normalizedPreserveQuotationId);
            nextQuotations.insert(0, preservedQuotation);
            selectedQuotation = preservedQuotation;
          } catch (_) {
            // Keep the fetched list to avoid blocking order creation flow.
          }
        }
      } else {
        final phone = client.telefono.trim();
        if (phone.isNotEmpty) {
          for (final quotation in nextQuotations) {
            if ((quotation.customerPhone ?? '').trim() == phone) {
              selectedQuotation = quotation;
              break;
            }
          }
        }
      }
      state = state.copyWith(
        loading: false,
        quotations: nextQuotations,
        selectedQuotation: selectedQuotation,
        quotationMessage: nextQuotations.isEmpty
            ? 'No hay cotizaciones disponibles. Puedes crear una nueva o continuar sin cotización.'
            : selectedQuotation != null
            ? 'Cotización seleccionada automáticamente'
            : 'La cotización es opcional. Puedes seleccionar una o continuar sin ella.',
      );
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudieron cargar las cotizaciones';
      state = state.copyWith(loading: false, actionError: message);
    }
  }

  Future<void> applyCreatedClient(ClienteModel client) async {
    final nextClients = [
      client,
      for (final item in state.clients)
        if (item.id != client.id) item,
    ];
    state = state.copyWith(
      clients: nextClients,
      clearActionError: true,
      clearError: true,
    );
    await selectClient(client);
  }

  void selectQuotation(CotizacionModel? quotation) {
    state = state.copyWith(
      selectedQuotation: quotation,
      clearActionError: true,
      quotationMessage: quotation == null
          ? state.quotationMessage
          : 'Cotización lista para crear la orden',
    );
  }

  void applyCreatedQuotation(CotizacionModel quotation) {
    final nextQuotations = [
      quotation,
      for (final item in state.quotations)
        if (item.id != quotation.id) item,
    ];
    state = state.copyWith(
      quotations: nextQuotations,
      selectedQuotation: quotation,
      clearActionError: true,
      quotationMessage: 'Cotización lista para crear la orden',
    );
  }

  void selectTechnician(UserModel? user) {
    state = state.copyWith(selectedTechnician: user, clearActionError: true);
  }

  void setCategory(ServiceOrderCategory category) {
    if (state.isCloneMode) return;
    state = state.copyWith(category: category, clearActionError: true);
  }

  void setServiceType(ServiceOrderType? serviceType) {
    state = state.copyWith(serviceType: serviceType, clearActionError: true);
  }

  void addTextReference(String content) {
    final normalized = content.trim();
    if (normalized.isEmpty) return;
    state = state.copyWith(
      references: [
        ...state.references,
        ServiceOrderDraftReference.text(id: _draftId(), content: normalized),
      ],
      clearActionError: true,
    );
  }

  Future<void> addVideoReference({
    required String fileName,
    List<int>? bytes,
    String? path,
    int? sizeBytes,
  }) async {
    await _withUploadState(
      label: 'Subiendo video',
      action: () async {
        final uploaded = await ref
            .read(uploadRepositoryProvider)
            .uploadVideo(
              fileName: fileName,
              bytes: bytes,
              path: path,
              onProgress: _updateUploadProgress,
            );
        state = state.copyWith(
          references: [
            ...state.references,
            ServiceOrderDraftReference.video(
              id: _draftId(),
              uploadedUrl: uploaded.url,
              localPath: (path ?? '').trim().isEmpty ? null : path!.trim(),
              fileName: fileName,
              sizeBytes: sizeBytes ?? uploaded.size,
            ),
          ],
          clearActionError: true,
        );
      },
      fallbackMessage: 'No se pudo subir el video',
    );
  }

  Future<void> addImageReference({
    required String fileName,
    List<int>? bytes,
    String? path,
    int? sizeBytes,
  }) async {
    await _withUploadState(
      label: 'Subiendo imagen',
      action: () async {
        final uploaded = await ref
            .read(uploadRepositoryProvider)
            .uploadImage(
              fileName: fileName,
              bytes: bytes,
              path: path,
              onProgress: _updateUploadProgress,
            );
        state = state.copyWith(
          references: [
            ...state.references,
            ServiceOrderDraftReference.image(
              id: _draftId(),
              uploadedUrl: uploaded.url,
              previewBytes: bytes == null ? null : Uint8List.fromList(bytes),
              localPath: (path ?? '').trim().isEmpty ? null : path!.trim(),
              fileName: fileName,
              sizeBytes: sizeBytes ?? uploaded.size,
            ),
          ],
          clearActionError: true,
        );
      },
      fallbackMessage: 'No se pudo subir la imagen',
    );
  }

  void removeReference(String id) {
    state = state.copyWith(
      references: state.references.where((item) => item.id != id).toList(),
      clearActionError: true,
    );
  }

  void setScheduledFor(DateTime? value) {
    state = state.copyWith(scheduledFor: value, clearActionError: true);
  }

  Future<CreateServiceOrderSubmissionResult> submit({
    required String technicalNote,
    required String extraRequirements,
  }) async {
    final client = state.selectedClient;
    final quotation = state.selectedQuotation;
    final serviceType = state.serviceType;
    if (client == null) {
      throw ApiException('Debes seleccionar un cliente');
    }
    if (serviceType == null) {
      throw ApiException('Debes seleccionar el tipo de servicio');
    }
    final effectiveQuotationId =
        quotation?.id ??
        state.editSource?.quotationId ??
        state.cloneSource?.quotationId;
    final technicalNoteValue = _canEditOperationalNotes
        ? technicalNote.trim()
        : '';
    final extraRequirementsValue = _canEditOperationalNotes
        ? extraRequirements.trim()
        : '';
    final assignedToId = _canAssignTechnician
        ? state.selectedTechnician?.id
        : null;

    state = state.copyWith(submitting: true, clearActionError: true);
    try {
      final result = state.isEditMode
          ? await ref
                .read(serviceOrdersApiProvider)
                .updateOrder(
                  state.editSource!.id,
                  UpdateServiceOrderRequest(
                    clientId: client.id,
                    quotationId: effectiveQuotationId,
                    category: state.category,
                    serviceType: serviceType,
                    technicalNote: technicalNoteValue,
                    extraRequirements: extraRequirementsValue,
                    assignedToId: assignedToId,
                    scheduledFor: state.scheduledFor,
                  ),
                )
          : state.isCloneMode
          ? await ref
                .read(serviceOrdersApiProvider)
                .cloneOrder(
                  state.cloneSource!.id,
                  CloneServiceOrderRequest(
                    serviceType: serviceType,
                    clientId: client.id,
                    quotationId: effectiveQuotationId,
                    technicalNote: technicalNoteValue,
                    extraRequirements: extraRequirementsValue,
                    assignedToId: assignedToId,
                  ),
                )
          : await ref
                .read(serviceOrdersApiProvider)
                .createOrder(
                  CreateServiceOrderRequest(
                    clientId: client.id,
                    quotationId: quotation?.id,
                    category: state.category,
                    serviceType: serviceType,
                    technicalNote: technicalNoteValue,
                    extraRequirements: extraRequirementsValue,
                    assignedToId: assignedToId,
                    scheduledFor: state.scheduledFor,
                  ),
                );
      final warningMessage = await _sendDraftReferences(result.id);
      state = state.copyWith(submitting: false);
      return CreateServiceOrderSubmissionResult(
        order: result,
        warningMessage: warningMessage,
      );
    } catch (error) {
      final message = error is ApiException
          ? error.message
          : 'No se pudo guardar la orden';
      state = state.copyWith(submitting: false, actionError: message);
      rethrow;
    }
  }

  Future<String?> _sendDraftReferences(String orderId) async {
    if (state.references.isEmpty) return null;

    try {
      final api = ref.read(serviceOrdersApiProvider);

      for (final reference in state.references) {
        await api.addEvidence(
          orderId,
          CreateServiceOrderEvidenceRequest(
            type: reference.type,
            content: reference.referenceContent,
          ),
        );
      }

      return null;
    } catch (_) {
      return 'La orden fue creada, pero no se pudieron guardar todas las referencias.';
    }
  }

  void _updateUploadProgress(double progress) {
    state = state.copyWith(uploadProgress: progress.clamp(0, 1));
  }

  Future<void> _withUploadState({
    required String label,
    required Future<void> Function() action,
    required String fallbackMessage,
  }) async {
    state = state.copyWith(
      uploadingEvidence: true,
      uploadProgress: 0,
      uploadLabel: label,
      clearActionError: true,
    );
    try {
      await action();
      state = state.copyWith(
        uploadingEvidence: false,
        uploadProgress: 0,
        clearUploadLabel: true,
      );
    } catch (error) {
      final message = error is ApiException ? error.message : fallbackMessage;
      state = state.copyWith(
        uploadingEvidence: false,
        uploadProgress: 0,
        clearUploadLabel: true,
        actionError: message,
      );
      rethrow;
    }
  }

  String _draftId() => DateTime.now().microsecondsSinceEpoch.toString();
}
