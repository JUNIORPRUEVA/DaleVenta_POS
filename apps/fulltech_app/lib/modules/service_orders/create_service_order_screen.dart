import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/service_media_url.dart';
import '../../core/utils/video_preview_controller.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../clientes/cliente_form_screen.dart';
import '../clientes/cliente_model.dart';
import '../cotizaciones/cotizacion_models.dart';
import '../cotizaciones/cotizaciones_screen.dart';
import 'application/create_service_order_controller.dart';
import 'service_order_models.dart';
import 'widgets/evidence_item_widget.dart';

Future<bool?> openCreateServiceOrderAdaptive(
  BuildContext context, {
  ServiceOrderCreateArgs? args,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final isDesktop = width >= kDesktopShellBreakpoint;

  if (!isDesktop) {
    return context.push<bool>(Routes.serviceOrderCreate, extra: args);
  }

  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Formulario de operaciones',
    barrierColor: Colors.black.withValues(alpha: 0.22),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(dialogContext);
      final panelWidth = size.width >= 1700
          ? 700.0
          : size.width >= 1440
          ? 640.0
          : size.width >= 1200
          ? 580.0
          : (size.width * 0.5).clamp(500.0, 620.0);

      return Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: size.height,
            child: CreateServiceOrderScreen(args: args, compactDialog: true),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class CreateServiceOrderScreen extends ConsumerStatefulWidget {
  const CreateServiceOrderScreen({
    super.key,
    this.args,
    this.compactDialog = false,
  });

  final ServiceOrderCreateArgs? args;
  final bool compactDialog;

  @override
  ConsumerState<CreateServiceOrderScreen> createState() =>
      _CreateServiceOrderScreenState();
}

class _CreateServiceOrderScreenState
    extends ConsumerState<CreateServiceOrderScreen> {
  late final TextEditingController _technicalNoteController;
  late final TextEditingController _extraRequirementsController;
  bool _inlineFlowBusy = false;

  @override
  void initState() {
    super.initState();
    final seedOrder = widget.args?.editSource ?? widget.args?.cloneSource;
    _technicalNoteController = TextEditingController(
      text: seedOrder?.technicalNote ?? '',
    );
    _extraRequirementsController = TextEditingController(
      text: seedOrder?.extraRequirements ?? '',
    );
  }

  @override
  void dispose() {
    _technicalNoteController.dispose();
    _extraRequirementsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = createServiceOrderControllerProvider(widget.args);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final user = ref.watch(authStateProvider).user;
    final userRoleKey = normalizeRoleKey(user?.role);
    final isCreatorEditingOrder =
        widget.args?.isEditMode == true &&
        widget.args?.editSource?.createdById == user?.id;
    final canManageOperationalFields =
        user?.appRole.isTechnician == true ||
        user?.appRole.isAdmin == true ||
        userRoleKey.contains('tecn') ||
        userRoleKey.contains('admin') ||
        isCreatorEditingOrder;
    final canCreateClients =
        user?.appRole == AppRole.admin ||
        user?.appRole == AppRole.asistente ||
        user?.appRole == AppRole.vendedor ||
        user?.appRole == AppRole.tecnico ||
        userRoleKey.contains('admin') ||
        userRoleKey.contains('asist') ||
        userRoleKey.contains('vend') ||
        userRoleKey.contains('tecn');
    final canAssignTechnician =
        user?.appRole == AppRole.admin ||
        user?.appRole == AppRole.asistente ||
        user?.appRole == AppRole.vendedor ||
        user?.appRole == AppRole.marketing ||
        user?.appRole == AppRole.tecnico ||
        userRoleKey.contains('admin') ||
        userRoleKey.contains('asist') ||
        userRoleKey.contains('vend') ||
        userRoleKey.contains('mark') ||
        userRoleKey.contains('tecn') ||
        isCreatorEditingOrder;
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= kDesktopShellBreakpoint;
    final shellFallback = widget.args?.isEditMode == true
        ? Routes.serviceOrderById(widget.args!.editSource!.id)
        : widget.args?.isCloneMode == true
        ? Routes.serviceOrderById(widget.args!.cloneSource!.id)
        : Routes.serviceOrders;
    final backButton = widget.compactDialog
        ? null
        : AppNavigator.maybeBackButton(context, fallbackRoute: shellFallback);

    final scaffold = Scaffold(
      drawer: isDesktop || widget.compactDialog
          ? null
          : buildAdaptiveDrawer(context, currentUser: user),
      backgroundColor: const Color(0xFFF9FFFC),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'service-order-reference-fab',
        onPressed: state.submitting || state.uploadingEvidence
            ? null
            : () => _showReferenceActions(context, controller),
        elevation: 8,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: const Icon(Icons.add_photo_alternate_rounded),
        label: const Text('Referencia'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= kDesktopShellBreakpoint;
                final form = _buildFormColumn(
                  context,
                  desktop: desktop,
                  state: state,
                  controller: controller,
                  canManageOperationalFields: canManageOperationalFields,
                  canAssignTechnician: canAssignTechnician,
                  canCreateClients: canCreateClients,
                );
                final horizontalPadding = desktop ? 20.0 : 16.0;

                return Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            84,
                            horizontalPadding,
                            120,
                          ),
                          children: [form],
                        ),
                      ),
                    ),
                    if (backButton != null)
                      Positioned(
                        top: MediaQuery.paddingOf(context).top,
                        left: 4,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          shape: const CircleBorder(),
                          elevation: 3,
                          shadowColor: Theme.of(
                            context,
                          ).colorScheme.shadow.withValues(alpha: 0.22),
                          child: Theme(
                            data: Theme.of(context).copyWith(
                              iconButtonTheme: const IconButtonThemeData(
                                style: ButtonStyle(
                                  foregroundColor:
                                      WidgetStatePropertyAll<Color>(
                                        Colors.black87,
                                      ),
                                  minimumSize: WidgetStatePropertyAll<Size>(
                                    Size(36, 36),
                                  ),
                                  padding: WidgetStatePropertyAll<EdgeInsets>(
                                    EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                            child: backButton,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (state.loading && !state.initialized)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        maintainBottomViewPadding: true,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final buttonWidth = (constraints.maxWidth * 0.52)
                .clamp(156.0, 210.0)
                .toDouble();

            return Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.16),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: buttonWidth,
                    child: FilledButton(
                      onPressed: state.submitting || state.uploadingEvidence
                          ? null
                          : () async {
                              if (state.scheduledFor == null) {
                                await AppFeedback.showError(
                                  context,
                                  'Selecciona la fecha y hora preferencial de la orden',
                                );
                                return;
                              }
                              try {
                                final result = await controller.submit(
                                  technicalNote: _technicalNoteController.text,
                                  extraRequirements:
                                      _extraRequirementsController.text,
                                );
                                if (!context.mounted) return;
                                await AppFeedback.showInfo(
                                  context,
                                  result.warningMessage ??
                                      (state.isEditMode
                                          ? 'Orden actualizada correctamente'
                                          : state.isCloneMode
                                          ? 'Orden clonada correctamente'
                                          : 'Orden creada correctamente'),
                                );
                                if (!context.mounted) return;
                                if (widget.compactDialog || state.isEditMode) {
                                  context.pop(true);
                                } else {
                                  context.go(Routes.serviceOrders);
                                }
                              } catch (_) {
                                if (!context.mounted) return;
                                final message =
                                    ref.read(provider).actionError ??
                                    'No se pudo guardar la orden';
                                await AppFeedback.showError(context, message);
                              }
                            },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(156, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onPrimary,
                        textStyle: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Guardar'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (!widget.compactDialog) {
      return scaffold;
    }

    final theme = Theme.of(context);
    final title = state.isEditMode
        ? 'Editar orden'
        : state.isCloneMode
        ? 'Clonar orden'
        : 'Nueva orden';

    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.84),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Completa la orden sin salir de operaciones.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimary.withValues(
                                alpha: 0.84,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: ClipRRect(child: scaffold)),
          ],
        ),
      ),
    );
  }

  Widget _buildFormColumn(
    BuildContext context, {
    required bool desktop,
    required CreateServiceOrderState state,
    required CreateServiceOrderController controller,
    required bool canManageOperationalFields,
    required bool canAssignTechnician,
    required bool canCreateClients,
  }) {
    final inputDecoration = _inputDecoration(context);
    final existingReferences = (state.editSource?.referenceItems ?? const [])
        .map(
          (reference) => ServiceOrderDraftReference(
            id: reference.id,
            type: reference.type,
            content: reference.content,
            createdAt: reference.createdAt,
            uploadedUrl: reference.type.isText ? null : reference.content,
            previewBytes: reference.previewBytes,
            localPath: reference.localPath,
            fileName: reference.fileName,
          ),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isCloneMode) ...[
          const SizedBox(height: 4),
          _CloneBanner(source: state.cloneSource!),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 12),
          _ErrorCard(message: state.error!),
        ],
        if (state.actionError != null) ...[
          const SizedBox(height: 12),
          _InfoCard(
            message: state.actionError!,
            color: Theme.of(context).colorScheme.errorContainer,
          ),
        ],
        if (state.uploadingEvidence) ...[
          const SizedBox(height: 12),
          _UploadProgressCard(
            label: state.uploadLabel ?? 'Subiendo archivo',
            progress: state.uploadProgress,
          ),
        ],
        if (_inlineFlowBusy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 3),
        ],
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.94,
            child: Row(
              children: [
                Expanded(
                  child: _CompactSelectorField(
                    label: 'Cliente',
                    value:
                        state.selectedClient?.nombre ?? 'Seleccionar cliente',
                    enabled: !_inlineFlowBusy,
                    onTap: () => _pickClient(context, state, controller),
                  ),
                ),
                if (canCreateClients) ...[
                  const SizedBox(width: 6),
                  _CompactActionIconButton(
                    icon: Icons.person_add_alt_1_rounded,
                    onTap: _inlineFlowBusy
                        ? null
                        : () => _createClientInline(context, controller),
                  ),
                  const SizedBox(width: 6),
                  _CompactActionIconButton(
                    icon: Icons.edit_rounded,
                    onTap: _inlineFlowBusy || state.selectedClient == null
                        ? null
                        : () => _editSelectedClientInline(
                            context,
                            state,
                            controller,
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: 0.94,
            child: Row(
              children: [
                Expanded(
                  child: _CompactSelectorField(
                    label: 'Cotización',
                    value: state.selectedQuotation == null
                        ? 'Opcional'
                        : 'Cotización ${state.selectedQuotation!.id.substring(0, state.selectedQuotation!.id.length >= 6 ? 6 : state.selectedQuotation!.id.length).toUpperCase()}',
                    enabled: !_inlineFlowBusy && state.selectedClient != null,
                    onTap: state.selectedClient == null
                        ? null
                        : () => _pickQuotation(context, state, controller),
                  ),
                ),
                const SizedBox(width: 6),
                _CompactActionIconButton(
                  icon: Icons.add_circle_outline_rounded,
                  onTap:
                      _inlineFlowBusy ||
                          state.loading ||
                          state.selectedClient == null
                      ? null
                      : () =>
                            _createQuotationInline(context, state, controller),
                ),
                if (state.selectedQuotation != null &&
                    _canEditQuotation(state.selectedQuotation!)) ...[
                  const SizedBox(width: 6),
                  _CompactActionIconButton(
                    icon: Icons.edit_outlined,
                    onTap: _inlineFlowBusy || state.loading
                        ? null
                        : () => _editQuotationInline(
                            context,
                            controller,
                            state.selectedQuotation!,
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Configuración',
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compactDecoration = inputDecoration.copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  );
                  final tooNarrow = constraints.maxWidth < 370;
                  if (tooNarrow) {
                    return Column(
                      children: [
                        DropdownButtonFormField<ServiceOrderCategory>(
                          isExpanded: true,
                          initialValue: state.category,
                          decoration: compactDecoration.copyWith(
                            labelText: 'Categoría',
                          ),
                          items: ServiceOrderCategory.values
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(
                                    category.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: state.isCloneMode
                              ? null
                              : (value) {
                                  if (value != null) {
                                    controller.setCategory(value);
                                  }
                                },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<ServiceOrderType>(
                          isExpanded: true,
                          initialValue: state.serviceType,
                          decoration: compactDecoration.copyWith(
                            labelText: 'Tipo',
                          ),
                          items: ServiceOrderType.values
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(
                                    type.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) =>
                              controller.setServiceType(value),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<ServiceOrderCategory>(
                          isExpanded: true,
                          initialValue: state.category,
                          decoration: compactDecoration.copyWith(
                            labelText: 'Categoría',
                          ),
                          items: ServiceOrderCategory.values
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(
                                    category.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: state.isCloneMode
                              ? null
                              : (value) {
                                  if (value != null) {
                                    controller.setCategory(value);
                                  }
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<ServiceOrderType>(
                          isExpanded: true,
                          initialValue: state.serviceType,
                          decoration: compactDecoration.copyWith(
                            labelText: 'Tipo',
                          ),
                          items: ServiceOrderType.values
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(
                                    type.label,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) =>
                              controller.setServiceType(value),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _CompactSelectorField(
                label: 'Fecha y hora *',
                value: state.scheduledFor == null
                    ? 'Seleccionar fecha y hora'
                    : DateFormat(
                        'dd/MM/yyyy h:mm a',
                        'es_DO',
                      ).format(state.scheduledFor!),
                enabled: !_inlineFlowBusy,
                onTap: () => _pickScheduledFor(context, state, controller),
              ),
              if (canAssignTechnician) ...[
                const SizedBox(height: 12),
                _TechnicianSelectorField(
                  value: state.selectedTechnician?.nombreCompleto,
                  onTap: () => _pickTechnician(context, state, controller),
                ),
              ],
            ],
          ),
        ),
        if (existingReferences.isNotEmpty || state.references.isNotEmpty) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Referencia',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (existingReferences.isNotEmpty)
                  ReferenceGallery(references: existingReferences),
                if (existingReferences.isNotEmpty &&
                    state.references.isNotEmpty)
                  const SizedBox(height: 12),
                if (state.references.isNotEmpty)
                  ReferenceGallery(
                    references: state.references,
                    onRemove: controller.removeReference,
                  ),
              ],
            ),
          ),
        ],
        if (canManageOperationalFields) ...[
          const SizedBox(height: 14),
          SectionCard(
            title: 'Notas',
            child: Column(
              children: [
                TextField(
                  controller: _technicalNoteController,
                  maxLines: 4,
                  decoration: inputDecoration.copyWith(
                    labelText: 'Nota técnica',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _extraRequirementsController,
                  maxLines: 3,
                  decoration: inputDecoration.copyWith(
                    labelText: 'Requisitos extra',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickClient(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final selected = await _showEntityPicker<ClienteModel>(
      context,
      title: 'Seleccionar cliente',
      items: state.clients,
      itemTitle: (client) => client.nombre,
      itemSubtitle: (client) => client.telefono,
    );
    if (selected == null || !mounted) return;
    await controller.selectClient(selected);
  }

  Future<void> _pickQuotation(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final outcome = await _showQuotationPicker(
      context,
      items: state.quotations,
    );
    if (!context.mounted || outcome == null) return;

    if (outcome.editRequested && outcome.quotation != null) {
      await _editQuotationInline(context, controller, outcome.quotation!);
      return;
    }
    if (outcome.createRequested) {
      await _createQuotationInline(context, state, controller);
      return;
    }

    controller.selectQuotation(outcome.quotation);
  }

  String _normalizeText(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  bool _canEditQuotation(CotizacionModel quotation) {
    final user = ref.read(authStateProvider).user;
    if (user == null) return false;
    if (user.appRole == AppRole.admin) return true;

    final userId = user.id.trim();
    final createdByUserId = (quotation.createdByUserId ?? '').trim();
    if (createdByUserId.isNotEmpty && createdByUserId == userId) {
      return true;
    }

    final createdByUserName = _normalizeText(quotation.createdByUserName);
    if (createdByUserName.isEmpty) return false;

    return createdByUserName == _normalizeText(user.nombreCompleto) ||
        createdByUserName == _normalizeText(user.email);
  }

  Future<void> _editQuotationInline(
    BuildContext context,
    CreateServiceOrderController controller,
    CotizacionModel quotation,
  ) async {
    if (!_canEditQuotation(quotation)) return;

    final updated = await Navigator.of(context).push<CotizacionModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CotizacionesScreen(
          initialQuotation: quotation,
          returnSavedQuotation: true,
        ),
      ),
    );
    if (updated == null || !mounted) return;
    await _runInlineFlow(() async {
      controller.applyCreatedQuotation(updated);
    });
  }

  Future<_QuotationPickerOutcome?> _showQuotationPicker(
    BuildContext context, {
    required List<CotizacionModel> items,
  }) async {
    final queryController = TextEditingController();
    final isDesktop =
        MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;
    final money = rdAccountingNumberFormat();

    Future<_QuotationPickerOutcome?> showPicker(
      Widget Function(StateSetter setState) builder,
    ) {
      if (isDesktop) {
        return showDialog<_QuotationPickerOutcome?>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => Dialog(
              elevation: 0,
              insetPadding: const EdgeInsets.all(24),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 680,
                ),
                child: builder(setState),
              ),
            ),
          ),
        );
      }

      return showModalBottomSheet<_QuotationPickerOutcome?>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.82,
              child: builder(setState),
            ),
          ),
        ),
      );
    }

    final result = await showPicker((setState) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final query = queryController.text.trim().toLowerCase();
      final filtered = items
          .where((item) {
            final code = item.id.toLowerCase();
            final createdBy = (item.createdByUserName ?? '').toLowerCase();
            final summary =
                '${item.items.length} items ${money.format(item.total)}'
                    .toLowerCase();
            return query.isEmpty ||
                code.contains(query) ||
                createdBy.contains(query) ||
                item.customerName.toLowerCase().contains(query) ||
                (item.customerPhone ?? '').toLowerCase().contains(query) ||
                summary.contains(query);
          })
          .toList(growable: false);

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isDesktop ? 24 : 20),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Seleccionar cotización',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: queryController,
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration(context).copyWith(
                  hintText: 'Buscar cotización',
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const _QuotationPickerOutcome.create()),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Crear cotización'),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: filtered.isEmpty
                    ? const _EmptyInlineState(
                        icon: Icons.receipt_long_outlined,
                        label: 'No hay cotizaciones para mostrar',
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final quotation = filtered[index];
                          final quoteCode = quotation.id.substring(
                            0,
                            quotation.id.length >= 6 ? 6 : quotation.id.length,
                          );
                          final createdBy = (quotation.createdByUserName ?? '')
                              .trim();
                          final subtitleParts = <String>[
                            '${quotation.items.length} items',
                            money.format(quotation.total),
                            if (createdBy.isNotEmpty) 'Creada por $createdBy',
                          ];

                          return _PickerListTile(
                            title: 'Cotización ${quoteCode.toUpperCase()}',
                            subtitle: subtitleParts.join(' · '),
                            icon: Icons.receipt_long_outlined,
                            onTap: () => Navigator.of(
                              context,
                            ).pop(_QuotationPickerOutcome.select(quotation)),
                            trailing: _canEditQuotation(quotation)
                                ? IconButton(
                                    tooltip: 'Editar cotización',
                                    onPressed: () => Navigator.of(context).pop(
                                      _QuotationPickerOutcome.edit(quotation),
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    });

    queryController.dispose();
    return result;
  }

  Future<void> _createClientInline(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final newClient = await openClienteFormAdaptive(context);
    if (newClient == null || !mounted) return;
    await _runInlineFlow(() => controller.applyCreatedClient(newClient));
  }

  Future<void> _editSelectedClientInline(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final clientId = (state.selectedClient?.id ?? '').trim();
    if (clientId.isEmpty) return;
    final updatedClient = await openClienteFormAdaptive(
      context,
      clienteId: clientId,
    );
    if (updatedClient == null || !mounted) return;
    await _runInlineFlow(() => controller.applyCreatedClient(updatedClient));
  }

  Future<void> _createQuotationInline(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final client = state.selectedClient;
    if (client == null) return;

    final quotation = await Navigator.of(context).push<CotizacionModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CotizacionesScreen(
          initialClient: client,
          returnSavedQuotation: true,
        ),
      ),
    );
    if (quotation == null || !mounted) return;
    await _runInlineFlow(() async {
      controller.applyCreatedQuotation(quotation);
    });
  }

  Future<void> _runInlineFlow(Future<void> Function() action) async {
    if (_inlineFlowBusy) return;
    setState(() => _inlineFlowBusy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _inlineFlowBusy = false);
      }
    }
  }

  Future<void> _pickScheduledFor(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    final now = DateTime.now();
    final initial = state.scheduledFor ?? now.add(const Duration(hours: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (pickedDate == null || !context.mounted || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !context.mounted || !mounted) return;

    controller.setScheduledFor(
      DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      ),
    );
  }

  Future<void> _pickTechnician(
    BuildContext context,
    CreateServiceOrderState state,
    CreateServiceOrderController controller,
  ) async {
    await controller.ensureTechniciansLoaded();
    if (!mounted || !context.mounted) return;
    final latestState = ref.read(
      createServiceOrderControllerProvider(widget.args),
    );

    if (latestState.technicians.isEmpty) {
      await AppFeedback.showError(
        context,
        'No hay técnicos disponibles para seleccionar',
      );
      return;
    }

    final selected = await _showEntityPicker(
      context,
      title: 'Seleccionar técnico',
      items: latestState.technicians,
      itemTitle: (user) => user.nombreCompleto,
      itemSubtitle: (user) => user.telefono,
      allowEmpty: true,
      emptyLabel: 'Sin asignar',
    );
    if (!mounted || !context.mounted) return;
    controller.selectTechnician(selected);
  }

  Future<T?> _showEntityPicker<T>(
    BuildContext context, {
    required String title,
    required List<T> items,
    required String Function(T item) itemTitle,
    String? Function(T item)? itemSubtitle,
    bool allowEmpty = false,
    String emptyLabel = '',
  }) async {
    final queryController = TextEditingController();
    final isDesktop =
        MediaQuery.sizeOf(context).width >= kDesktopShellBreakpoint;

    Future<T?> showPicker(Widget Function(StateSetter setState) builder) {
      if (isDesktop) {
        return showDialog<T?>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => Dialog(
              elevation: 0,
              insetPadding: const EdgeInsets.all(24),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 640,
                ),
                child: builder(setState),
              ),
            ),
          ),
        );
      }

      return showModalBottomSheet<T?>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: StatefulBuilder(
            builder: (context, setState) => SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * 0.82,
              child: builder(setState),
            ),
          ),
        ),
      );
    }

    return showPicker((setState) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      final query = queryController.text.trim().toLowerCase();
      final filtered = items
          .where((item) {
            final text = itemTitle(item).toLowerCase();
            final subtitle = (itemSubtitle?.call(item) ?? '').toLowerCase();
            return query.isEmpty ||
                text.contains(query) ||
                subtitle.contains(query);
          })
          .toList(growable: false);

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(isDesktop ? 24 : 20),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: queryController,
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration(context).copyWith(
                  hintText: 'Buscar',
                  prefixIcon: const Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 14),
              if (allowEmpty) ...[
                _PickerListTile(
                  icon: Icons.remove_circle_outline,
                  title: emptyLabel,
                  onTap: () => Navigator.of(context).pop(null),
                ),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: filtered.isEmpty
                    ? const _EmptyInlineState(
                        icon: Icons.search_off_rounded,
                        label: 'No hay resultados',
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _PickerListTile(
                            title: itemTitle(item),
                            subtitle: itemSubtitle?.call(item),
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    });
  }

  InputDecoration _inputDecoration(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );

    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
      disabledBorder: border,
      labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
    );
  }

  Future<void> _showReferenceActions(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Agregar referencia',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ReferenceSheetOption(
                  icon: Icons.notes_rounded,
                  title: 'Agregar texto',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _addNoteReference(context, controller);
                  },
                ),
                const SizedBox(height: 10),
                _ReferenceSheetOption(
                  icon: Icons.image_outlined,
                  title: 'Subir imagen',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _addImageReference(context, controller);
                  },
                ),
                const SizedBox(height: 10),
                _ReferenceSheetOption(
                  icon: Icons.videocam_outlined,
                  title: 'Subir video',
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    _addVideoReference(context, controller);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addNoteReference(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final value = await _promptMultilineInput(
      context,
      title: 'Agregar referencia',
      label: 'Escribe la referencia en texto',
    );
    if ((value ?? '').trim().isEmpty) return;
    controller.addTextReference(value!.trim());
  }

  Future<void> _addVideoReference(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    try {
      await controller.addVideoReference(
        fileName: file.name,
        bytes: file.bytes,
        path: kIsWeb ? null : file.path,
        sizeBytes: file.size,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref
                .read(createServiceOrderControllerProvider(widget.args))
                .actionError ??
            'No se pudo subir el video',
      );
    }
  }

  Future<void> _addImageReference(
    BuildContext context,
    CreateServiceOrderController controller,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null) return;
    try {
      await controller.addImageReference(
        bytes: bytes,
        path: kIsWeb ? null : file.path,
        fileName: file.name,
        sizeBytes: file.size,
      );
    } catch (_) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        ref
                .read(createServiceOrderControllerProvider(widget.args))
                .actionError ??
            'No se pudo subir la imagen',
      );
    }
  }

  Future<String?> _promptMultilineInput(
    BuildContext context, {
    required String title,
    required String label,
  }) {
    final textController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: textController,
            maxLines: 5,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, textController.text),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }
}

class _PickerListTile extends StatelessWidget {
  const _PickerListTile({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.outlineVariant),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon ?? Icons.person_outline_rounded,
                color: colorScheme.primary,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((subtitle ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotationPickerOutcome {
  const _QuotationPickerOutcome._({
    this.quotation,
    required this.editRequested,
    required this.createRequested,
  });

  const _QuotationPickerOutcome.select(CotizacionModel quotation)
    : this._(
        quotation: quotation,
        editRequested: false,
        createRequested: false,
      );

  const _QuotationPickerOutcome.edit(CotizacionModel quotation)
    : this._(quotation: quotation, editRequested: true, createRequested: false);

  const _QuotationPickerOutcome.create()
    : this._(quotation: null, editRequested: false, createRequested: true);

  final CotizacionModel? quotation;
  final bool editRequested;
  final bool createRequested;
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102542).withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  Flexible(child: trailing!),
                ],
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _CompactSelectorField extends StatelessWidget {
  const _CompactSelectorField({
    required this.label,
    required this.value,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactActionIconButton extends StatelessWidget {
  const _CompactActionIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

class _TechnicianSelectorField extends StatelessWidget {
  const _TechnicianSelectorField({this.value, this.onTap});

  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = (value ?? '').trim().isEmpty ? 'Seleccionar técnico' : value!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.engineering_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CloneBanner extends StatelessWidget {
  const _CloneBanner({required this.source});

  final ServiceOrderModel source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC9DAFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Clonando orden finalizada',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '${source.category.label} · ${source.serviceType.label}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      message: message,
      color: Theme.of(context).colorScheme.errorContainer,
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _UploadProgressCard extends StatelessWidget {
  const _UploadProgressCard({required this.label, required this.progress});

  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7F4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress <= 0 ? null : progress),
          const SizedBox(height: 8),
          Text('$percent% completado'),
        ],
      ),
    );
  }
}

class InputSelector extends StatelessWidget {
  const InputSelector({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.hint,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected =
        value.trim().isNotEmpty &&
        value.trim().toLowerCase() != 'buscar cliente' &&
        value.trim().toLowerCase() != 'seleccionar técnico';

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF7FAFF) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.28)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((hint ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hint!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class ReferenceGallery extends StatelessWidget {
  const ReferenceGallery({super.key, required this.references, this.onRemove});

  final List<ServiceOrderDraftReference> references;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final textReferences = references
        .where((item) => item.isText)
        .toList(growable: false);
    final mediaReferences = references
        .where((item) => !item.isText)
        .toList(growable: false);

    if (references.isEmpty) {
      return const _EmptyInlineState(
        icon: Icons.add_photo_alternate_outlined,
        label: 'Sin referencias',
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Column(
        key: ValueKey(references.length),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (textReferences.isNotEmpty)
            ...textReferences.map(
              (reference) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TextReferenceCard(
                  reference: reference,
                  onRemove: onRemove == null
                      ? null
                      : () => onRemove!(reference.id),
                ),
              ),
            ),
          if (mediaReferences.isNotEmpty)
            SizedBox(
              height: 148,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: mediaReferences
                      .map(
                        (reference) => Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: MediaPreviewCard(
                            reference: reference,
                            width: 132,
                            onRemove: onRemove == null
                                ? null
                                : () => onRemove!(reference.id),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MediaPreviewCard extends StatelessWidget {
  const MediaPreviewCard({
    super.key,
    required this.reference,
    this.width = 132,
    this.onRemove,
  });

  final ServiceOrderDraftReference reference;
  final double width;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final source = _resolvedReferenceSource(reference);

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.72),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _showMediaViewer(context, reference),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: reference.isImage
                      ? _ImageThumbnail(reference: reference)
                      : _VideoThumbnail(reference: reference),
                ),
              ),
            ),
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  reference.isImage ? 'Imagen' : 'Video',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (reference.isVideo)
              Positioned(
                bottom: 8,
                left: 8,
                child: _VideoDurationBadge(source: source),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close_rounded, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: 'Eliminar',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.92),
                  foregroundColor: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMediaViewer(
    BuildContext context,
    ServiceOrderDraftReference reference,
  ) {
    double dragOffset = 0;

    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar vista',
      barrierColor: Colors.black.withValues(alpha: 0.92),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return StatefulBuilder(
          builder: (context, setState) {
            return GestureDetector(
              onVerticalDragUpdate: (details) {
                setState(() {
                  dragOffset += details.delta.dy;
                });
              },
              onVerticalDragEnd: (details) {
                if (dragOffset.abs() > 80) {
                  Navigator.of(dialogContext).pop();
                  return;
                }
                setState(() {
                  dragOffset = 0;
                });
              },
              child: Material(
                color: Colors.transparent,
                child: Stack(
                  children: [
                    Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        transform: Matrix4.translationValues(0, dragOffset, 0),
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: reference.isImage
                                ? InteractiveViewer(
                                    child: reference.previewBytes != null
                                        ? Image.memory(
                                            reference.previewBytes!,
                                            fit: BoxFit.contain,
                                          )
                                        : Image.network(
                                            _resolvedReferenceSource(reference),
                                            fit: BoxFit.contain,
                                          ),
                                  )
                                : Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 720,
                                      ),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: EvidenceItemWidget(
                                          type: reference.type,
                                          url: reference.content,
                                          text: null,
                                          createdAt: reference.createdAt,
                                          previewBytes: reference.previewBytes,
                                          localPath: reference.localPath,
                                          fileName: reference.fileName,
                                          compact: false,
                                          showHeader: false,
                                          showSurface: false,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 18,
                      right: 18,
                      child: IconButton.filled(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        );
      },
    );
  }
}

class _TextReferenceCard extends StatelessWidget {
  const _TextReferenceCard({required this.reference, this.onRemove});

  final ServiceOrderDraftReference reference;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.notes_rounded,
              color: colorScheme.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Texto',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  reference.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.reference});

  final ServiceOrderDraftReference reference;

  @override
  Widget build(BuildContext context) {
    if (reference.previewBytes != null) {
      return Image.memory(
        reference.previewBytes!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }

    return Image.network(
      _resolvedReferenceSource(reference),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (context, error, stackTrace) {
        return const _EmptyInlineState(
          icon: Icons.broken_image_outlined,
          label: 'Sin imagen',
        );
      },
    );
  }
}

class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail({required this.reference});

  final ServiceOrderDraftReference reference;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFEEF2F8), Color(0xFFDCE3EF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Center(
            child: CircleAvatar(
              radius: 24,
              backgroundColor: Color(0xFFD8DDFC),
              child: Icon(Icons.play_arrow_rounded, size: 28),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.02),
                    Colors.black.withValues(alpha: 0.18),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _resolvedReferenceSource(ServiceOrderDraftReference reference) {
  final localPath = (reference.localPath ?? '').trim();
  if (localPath.isNotEmpty) return localPath;
  return resolveServiceMediaUrl(reference.previewSource);
}

class _VideoDurationBadge extends StatefulWidget {
  const _VideoDurationBadge({required this.source});

  final String source;

  @override
  State<_VideoDurationBadge> createState() => _VideoDurationBadgeState();
}

class _VideoDurationBadgeState extends State<_VideoDurationBadge> {
  String? _durationLabel;

  @override
  void initState() {
    super.initState();
    _resolveDuration();
  }

  Future<void> _resolveDuration() async {
    final controller = createVideoPreviewController(
      path: widget.source,
      fileName: widget.source,
    );
    if (controller == null) return;
    try {
      await controller.initialize();
      if (!mounted) return;
      final duration = controller.value.duration;
      final minutes = duration.inMinutes
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      final seconds = duration.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      setState(() {
        _durationLabel = '$minutes:$seconds';
      });
    } catch (_) {
      // Keep placeholder hidden when duration cannot be resolved.
    } finally {
      await controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if ((_durationLabel ?? '').isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _durationLabel!,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ReferenceSheetOption extends StatelessWidget {
  const _ReferenceSheetOption({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: colorScheme.primary.withValues(alpha: 0.06),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInlineState extends StatelessWidget {
  const _EmptyInlineState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
