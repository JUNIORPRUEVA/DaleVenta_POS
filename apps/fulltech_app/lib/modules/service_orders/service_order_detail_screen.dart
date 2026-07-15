import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../clientes/cliente_model.dart';
import '../clientes/client_location_utils.dart';
import '../cotizaciones/cotizacion_models.dart';
import '../cotizaciones/cotizaciones_screen.dart';
import 'application/service_order_detail_controller.dart';
import 'service_order_models.dart';
import 'service_order_schedule_formatter.dart';
import 'widgets/client_location_card.dart';
import 'widgets/evidence_item_widget.dart';
import 'widgets/service_order_quick_actions_modal.dart';

class ServiceOrderDetailScreen extends ConsumerStatefulWidget {
  const ServiceOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<ServiceOrderDetailScreen> createState() =>
      _ServiceOrderDetailScreenState();
}

class _ServiceOrderDetailScreenState
    extends ConsumerState<ServiceOrderDetailScreen> {
  String? _expandedSection = 'quotation-section';

  void _toggleSection(String sectionKey) {
    setState(() {
      _expandedSection = _expandedSection == sectionKey ? null : sectionKey;
    });
  }

  Future<void> _copyOrderInformation(
    ServiceOrderModel order,
    ServiceOrderDetailState state,
  ) async {
    final payload = _buildWhatsAppReadyOrderMessage(order, state);
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    await AppFeedback.showInfo(context, 'Información copiada al portapapeles');
  }

  Future<void> _editQuotationInline(
    BuildContext context,
    ServiceOrderDetailController controller,
    CotizacionModel quotation,
  ) async {
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
    await controller.refresh();
  }

  Future<void> _showQuotationPreviewDialog(CotizacionModel quotation) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final theme = Theme.of(dialogContext);
        final maxWidth = mediaQuery.size.width >= 1100
            ? 980.0
            : mediaQuery.size.width >= 700
            ? 760.0
            : mediaQuery.size.width - 24;
        final maxHeight = mediaQuery.size.height * 0.9;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 20,
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vista de cotización',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Consulta productos, observaciones y totales de la cotización vinculada.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                ),
                Expanded(child: _QuotationDialogBody(quotation: quotation)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleBackNavigation() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go(Routes.serviceOrders);
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.orderId;
    final provider = serviceOrderDetailControllerProvider(orderId);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final order = state.order;
    final pendingUploads =
        order?.evidences.where((item) => item.isPendingUpload).length ?? 0;
    final currentUser = ref.watch(authStateProvider).user;
    final currentUserId = currentUser?.id ?? '';
    final role = currentUser?.appRole ?? AppRole.unknown;
    final isAdmin = role.isAdmin;
    final canSeeTechnicalArea = role.isTechnician || role.isAdmin;
    final canEditOrder =
        order != null && (role.isAdmin || currentUserId == order.createdById);
    final canDeleteOrder = isAdmin && !state.loading && !state.working;
    final canEditOrderAction = canEditOrder && !state.loading && !state.working;
    final canCopyOrderAction =
        order != null && !state.loading && !state.working;
    final canRefreshAction = !state.loading && !state.working;
    final clientPhone = (state.client?.telefono ?? '').trim();
    final clientPhoneUri = _buildPhoneUri(clientPhone);
    final clientWhatsAppUri = _buildWhatsAppUri(clientPhone);
    final clientLocationUrl =
        (state.client?.locationUrl ?? order?.client?.locationUrl ?? '').trim();
    final locationPreview = parseClientLocationPreview(clientLocationUrl);
    final locationUri = buildClientNavigationUri(
      locationPreview,
      clientLocationUrl,
    );
    final sellerConversationUri = order == null
        ? null
        : _buildWhatsAppUri(state.usersById[order.createdById]?.telefono ?? '');
    final supportConversationUri = _buildAssistantConversationUri(
      state.usersById,
    );
    final technicianActionConfig = ServiceOrderQuickActionsConfig(
      clientCallUri: clientPhoneUri,
      clientWhatsAppUri: clientWhatsAppUri,
      locationUri: locationUri,
      sellerConversationUri: sellerConversationUri,
      supportConversationUri: supportConversationUri,
    );
    final canCallClientAction =
        clientPhoneUri != null && !state.loading && !state.working;
    final canOpenWhatsAppAction =
        clientWhatsAppUri != null && !state.loading && !state.working;
    final createdByName = order == null
        ? null
        : (state.usersById[order.createdById]?.nombreCompleto ??
                  order.createdById)
              .trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF9FFFC),
      floatingActionButton: _DetailFloatingActionsButton(
        isTechnician: role.isTechnician && order != null,
        canRefresh: canRefreshAction,
        canCopy: canCopyOrderAction,
        canEdit: canEditOrderAction,
        canDelete: canDeleteOrder,
        canCallClient: canCallClientAction,
        canOpenWhatsApp: canOpenWhatsAppAction,
        onRefresh: controller.refresh,
        onOpenTechnicianActions: role.isTechnician && order != null
            ? () {
                final useMobilePanel = MediaQuery.sizeOf(context).width < 720;
                showServiceOrderQuickActionsModal(
                  context: context,
                  ref: ref,
                  orderId: order.id,
                  order: order,
                  presentation: useMobilePanel
                      ? ServiceOrderQuickActionsPresentation.mobileRightPanel
                      : ServiceOrderQuickActionsPresentation.bottomSheet,
                  actionConfig: technicianActionConfig,
                  onOrderUpdated: () {
                    controller.refresh();
                  },
                );
              }
            : null,
        onCopy: canCopyOrderAction
            ? () => _copyOrderInformation(order, state)
            : null,
        onCallClient: canCallClientAction
            ? () => safeOpenUrl(
                context,
                clientPhoneUri,
                copiedMessage: 'No se pudo iniciar la llamada. Numero copiado.',
              )
            : null,
        onOpenWhatsApp: canOpenWhatsAppAction
            ? () => safeOpenUrl(
                context,
                clientWhatsAppUri,
                copiedMessage: 'No se pudo abrir WhatsApp. Enlace copiado.',
              )
            : null,
        onEdit: canEditOrderAction
            ? () async {
                final updated = await context.push<bool>(
                  Routes.serviceOrderCreate,
                  extra: ServiceOrderCreateArgs(editSource: order),
                );
                if (updated == true) {
                  await controller.refresh();
                  if (!context.mounted) return;
                  await AppFeedback.showInfo(context, 'Orden actualizada');
                }
              }
            : null,
        onDelete: canDeleteOrder && order != null
            ? () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) {
                    return AlertDialog(
                      title: const Text('Eliminar orden'),
                      content: const Text(
                        'Esta acción eliminará la orden actual y no se puede deshacer.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancelar'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          child: const Text('Eliminar'),
                        ),
                      ],
                    );
                  },
                );
                if (confirmed != true) return;

                try {
                  await controller.deleteOrder();
                  if (!context.mounted) return;
                  await AppFeedback.showInfo(context, 'Orden eliminada');
                  if (!context.mounted) return;
                  context.pop(true);
                } catch (_) {
                  if (!context.mounted) return;
                  await AppFeedback.showError(
                    context,
                    ref.read(provider).actionError ??
                        'No se pudo eliminar la orden',
                  );
                }
              }
            : null,
      ),
      body: Column(
        children: [
          _DetailTopBar(
            onBackPressed: _handleBackNavigation,
            creatorName: createdByName,
            status: order?.status,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: order == null
                  ? _DetailWarmupShell(message: state.error)
                  : RefreshIndicator(
                      onRefresh: controller.refresh,
                      child: ListView(
                        key: ValueKey(order.id),
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 112),
                        children: [
                          _HeroHeader(
                            order: order,
                            technicianName: order.assignedToId == null
                                ? null
                                : (state
                                              .usersById[order.assignedToId!]
                                              ?.nombreCompleto ??
                                          order.assignedToId)
                                      ?.trim(),
                          ),
                          const SizedBox(height: 10),
                          if (state.actionError != null) ...[
                            _MessageBanner(message: state.actionError!),
                            const SizedBox(height: 8),
                          ],
                          _InlineClientSection(state: state),
                          const SizedBox(height: 10),
                          SectionCard(
                            icon: Icons.timeline_rounded,
                            title: 'Historial de estado',
                            subtitle:
                                'Seguimiento real de cambios con fecha y hora.',
                            child: _StatusHistorySection(order: order),
                          ),
                          const SizedBox(height: 10),
                          ExpandableSectionCard(
                            storageKey: 'quotation-section',
                            expanded: _expandedSection == 'quotation-section',
                            onToggle: () => _toggleSection('quotation-section'),
                            icon: Icons.request_quote_outlined,
                            title: 'Cotización',
                            collapsedSummary: _buildQuotationSummary(
                              state.quotation,
                            ),
                            child: state.quotation == null
                                ? const Text('Sin cotización')
                                : _CompactQuotationDetails(
                                    quotation: state.quotation!,
                                    onOpen: () => _showQuotationPreviewDialog(
                                      state.quotation!,
                                    ),
                                    onEdit: canEditOrder
                                        ? () => _editQuotationInline(
                                            context,
                                            controller,
                                            state.quotation!,
                                          )
                                        : null,
                                  ),
                          ),
                          const SizedBox(height: 10),
                          if (canSeeTechnicalArea &&
                              (_hasContent(order.technicalNote) ||
                                  _hasContent(order.extraRequirements))) ...[
                            SectionCard(
                              icon: Icons.edit_note_rounded,
                              title: 'Notas operativas',
                              trailing: FilledButton.tonalIcon(
                                onPressed: state.working
                                    ? null
                                    : () => _editOperationalNotes(
                                        context,
                                        ref,
                                        provider,
                                      ),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.edit_note_rounded),
                                label: const Text('Editar'),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_hasContent(order.technicalNote))
                                    _ReadOnlyField(
                                      label: 'Nota técnica',
                                      value: order.technicalNote,
                                    ),
                                  if (_hasContent(order.extraRequirements)) ...[
                                    if (_hasContent(order.technicalNote))
                                      const SizedBox(height: 8),
                                    _ReadOnlyField(
                                      label: 'Requisitos extra',
                                      value: order.extraRequirements,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          SectionCard(
                            icon: Icons.forum_rounded,
                            title: 'Referencia',
                            child: order.referenceItems.isEmpty
                                ? const Text('Sin referencias')
                                : _EvidenceCollection(
                                    items: order.referenceItems,
                                    variant: EvidenceCardVariant.reference,
                                  ),
                          ),
                          const SizedBox(height: 10),
                          SectionCard(
                            icon: Icons.hardware_rounded,
                            title: 'Evidencia técnica',
                            trailing: canSeeTechnicalArea
                                ? MenuAnchor(
                                    menuChildren: [
                                      MenuItemButton(
                                        onPressed: () => _addTextEvidence(
                                          context,
                                          ref,
                                          provider,
                                        ),
                                        child: const Text('Agregar texto'),
                                      ),
                                      MenuItemButton(
                                        onPressed: () => _addImageEvidence(
                                          context,
                                          ref,
                                          provider,
                                        ),
                                        child: const Text('Subir imagen'),
                                      ),
                                      MenuItemButton(
                                        onPressed: () => _addVideoEvidence(
                                          context,
                                          ref,
                                          provider,
                                        ),
                                        child: const Text('Subir video'),
                                      ),
                                    ],
                                    builder: (context, menuController, child) {
                                      return OutlinedButton.icon(
                                        onPressed: state.working
                                            ? null
                                            : () {
                                                if (menuController.isOpen) {
                                                  menuController.close();
                                                } else {
                                                  menuController.open();
                                                }
                                              },
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.add_photo_alternate_outlined,
                                        ),
                                        label: const Text('Nueva evidencia'),
                                      );
                                    },
                                  )
                                : null,
                            child: order.technicalEvidenceItems.isEmpty
                                ? const Text('Sin evidencia técnica')
                                : _EvidenceCollection(
                                    items: order.technicalEvidenceItems,
                                    variant: EvidenceCardVariant.technical,
                                  ),
                          ),
                          const SizedBox(height: 10),
                          if (pendingUploads > 0) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    pendingUploads == 1
                                        ? '1 archivo subiendose en segundo plano...'
                                        : '$pendingUploads archivos subiendose en segundo plano...',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                          ExpandableSectionCard(
                            storageKey: 'reports-section',
                            expanded: _expandedSection == 'reports-section',
                            onToggle: () => _toggleSection('reports-section'),
                            icon: Icons.description_outlined,
                            title: 'Reporte técnico',
                            collapsedSummary: _buildReportsSummary(
                              order.reports,
                            ),
                            child: order.reports.isEmpty
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (canSeeTechnicalArea) ...[
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: FilledButton.tonalIcon(
                                            onPressed: state.working
                                                ? null
                                                : () => _addReport(
                                                    context,
                                                    ref,
                                                    provider,
                                                  ),
                                            style: FilledButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.note_add_outlined,
                                            ),
                                            label: const Text(
                                              'Agregar reporte',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      const Text('Sin reportes'),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (canSeeTechnicalArea) ...[
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: FilledButton.tonalIcon(
                                            onPressed: state.working
                                                ? null
                                                : () => _addReport(
                                                    context,
                                                    ref,
                                                    provider,
                                                  ),
                                            style: FilledButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.note_add_outlined,
                                            ),
                                            label: const Text(
                                              'Agregar reporte',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                      ],
                                      ...order.reports.asMap().entries.map(
                                        (entry) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: _FadeSlideIn(
                                            delayMs: 50 * entry.key,
                                            child: _ReportCard(
                                              report: entry.value,
                                              authorName: state
                                                  .usersById[entry
                                                      .value
                                                      .createdById]
                                                  ?.nombreCompleto,
                                            ),
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
          ),
        ],
      ),
      bottomNavigationBar: order == null || !order.isCloneSourceAllowed
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: () async {
                    final created = await context.push<bool>(
                      Routes.serviceOrderCreate,
                      extra: ServiceOrderCreateArgs(cloneSource: order),
                    );
                    if (created == true) {
                      if (!context.mounted) return;
                      context.pop(true);
                    }
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.copy_all_outlined),
                  label: const Text('Crear nueva orden desde esta'),
                ),
              ),
            ),
    );
  }
}

class _DetailFloatingActionsButton extends StatefulWidget {
  const _DetailFloatingActionsButton({
    required this.isTechnician,
    required this.canRefresh,
    required this.canCopy,
    required this.canEdit,
    required this.canDelete,
    required this.canCallClient,
    required this.canOpenWhatsApp,
    required this.onRefresh,
    this.onOpenTechnicianActions,
    this.onCopy,
    this.onCallClient,
    this.onOpenWhatsApp,
    this.onEdit,
    this.onDelete,
  });

  final bool isTechnician;
  final bool canRefresh;
  final bool canCopy;
  final bool canEdit;
  final bool canDelete;
  final bool canCallClient;
  final bool canOpenWhatsApp;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenTechnicianActions;
  final VoidCallback? onCopy;
  final VoidCallback? onCallClient;
  final VoidCallback? onOpenWhatsApp;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  @override
  State<_DetailFloatingActionsButton> createState() =>
      _DetailFloatingActionsButtonState();
}

class _DetailFloatingActionsButtonState
    extends State<_DetailFloatingActionsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeRotation;
  Timer? _shakeTimer;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _shakeRotation = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0, end: -0.06), weight: 18),
        TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.06), weight: 22),
        TweenSequenceItem(tween: Tween(begin: 0.06, end: -0.045), weight: 20),
        TweenSequenceItem(tween: Tween(begin: -0.045, end: 0.045), weight: 20),
        TweenSequenceItem(tween: Tween(begin: 0.045, end: 0), weight: 20),
      ],
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

    _shakeTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (!mounted || _shakeController.isAnimating) {
        return;
      }
      _shakeController.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _shakeTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final buttonBg = colorScheme.primary;
    final buttonFg = colorScheme.onPrimary;
    final buttonBorder = Color.alphaBlend(
      colorScheme.onPrimary.withValues(alpha: 0.16),
      buttonBg,
    );
    if (widget.isTechnician) {
      return AnimatedBuilder(
        animation: _shakeRotation,
        builder: (context, child) {
          return Transform.rotate(angle: _shakeRotation.value, child: child);
        },
        child: FloatingActionButton.extended(
          heroTag: 'detail-technician-actions-fab',
          onPressed: widget.onOpenTechnicianActions,
          tooltip: 'Gestionar',
          backgroundColor: buttonBg,
          foregroundColor: buttonFg,
          elevation: 1.2,
          hoverElevation: 1.6,
          focusElevation: 1.6,
          highlightElevation: 1.6,
          splashColor: buttonFg.withValues(alpha: 0.12),
          extendedPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: buttonBorder, width: 1),
          ),
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text(
            'Gestionar',
            style: TextStyle(
              fontSize: 12.6,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.08,
            ),
          ),
        ),
      );
    }
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: widget.canRefresh ? widget.onRefresh : null,
          leadingIcon: const Icon(Icons.refresh_rounded),
          child: const Text('Actualizar'),
        ),
        MenuItemButton(
          onPressed: widget.canCopy ? widget.onCopy : null,
          leadingIcon: const Icon(Icons.content_copy_rounded),
          child: const Text('Copiar información'),
        ),
        MenuItemButton(
          onPressed: widget.canCallClient ? widget.onCallClient : null,
          leadingIcon: const Icon(Icons.call_outlined),
          child: const Text('Llamar al cliente'),
        ),
        MenuItemButton(
          onPressed: widget.canOpenWhatsApp ? widget.onOpenWhatsApp : null,
          leadingIcon: const Icon(Icons.chat_bubble_outline_rounded),
          child: const Text('Escribir por WhatsApp'),
        ),
        MenuItemButton(
          onPressed: widget.canEdit ? () => widget.onEdit?.call() : null,
          leadingIcon: const Icon(Icons.edit_outlined),
          child: const Text('Editar orden'),
        ),
        if (widget.onDelete != null)
          MenuItemButton(
            onPressed: widget.canDelete ? () => widget.onDelete?.call() : null,
            leadingIcon: Icon(Icons.delete_outline, color: colorScheme.error),
            child: Text(
              'Eliminar orden',
              style: TextStyle(color: colorScheme.error),
            ),
          ),
      ],
      builder: (context, menuController, child) {
        return AnimatedBuilder(
          animation: _shakeRotation,
          builder: (context, animatedChild) {
            return Transform.rotate(
              angle: _shakeRotation.value,
              child: animatedChild,
            );
          },
          child: FloatingActionButton.small(
            heroTag: 'detail-actions-fab',
            onPressed: () {
              if (menuController.isOpen) {
                menuController.close();
              } else {
                menuController.open();
              }
            },
            tooltip: 'Acciones',
            child: const Icon(Icons.more_horiz_rounded),
          ),
        );
      },
    );
  }
}

class _DetailTopBar extends StatelessWidget {
  const _DetailTopBar({
    required this.onBackPressed,
    this.creatorName,
    this.status,
  });

  final VoidCallback onBackPressed;
  final String? creatorName;
  final ServiceOrderStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final normalizedCreator = (creatorName ?? '').trim();
    final creatorFirstName = normalizedCreator.isEmpty
        ? ''
        : normalizedCreator.split(RegExp(r'\s+')).first.trim();
    final hasCreator = creatorFirstName.isNotEmpty;

    return SafeArea(
      bottom: false,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.96),
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: onBackPressed,
              tooltip: 'Regresar',
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
            ),
            if (hasCreator) ...[
              Container(
                width: 1,
                height: 16,
                margin: const EdgeInsets.only(right: 10),
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
              Expanded(
                child: Text(
                  'Creador: $creatorFirstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ) ??
                      theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.onSurface,
                      ),
                ),
              ),
              const SizedBox(width: 10),
            ] else
              const Spacer(),
            if (status != null) StatusBadge(status: status!),
          ],
        ),
      ),
    );
  }
}

Uri? _buildPhoneUri(String rawPhone) {
  final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }
  return Uri.parse('tel:$digits');
}

Uri? _buildWhatsAppUri(String rawPhone) {
  var digits = rawPhone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) {
    return null;
  }
  if (digits.length == 10) {
    digits = '1$digits';
  }
  return Uri.parse('https://wa.me/$digits');
}

Uri? _buildAssistantConversationUri(Map<String, UserModel> usersById) {
  for (final user in usersById.values) {
    if (user.appRole == AppRole.asistente && user.telefono.trim().isNotEmpty) {
      return _buildWhatsAppUri(user.telefono);
    }
  }
  return null;
}

class _InlineClientSection extends StatelessWidget {
  const _InlineClientSection({required this.state});

  final ServiceOrderDetailState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = state.client;
    final values = <String>[
      _valueOrFallback(client?.nombre),
      _valueOrFallback(client?.telefono),
      _valueOrFallback(client?.direccion),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Text(
        values.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Future<void> _addTextEvidence(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final text = await _promptMultilineInput(
    context,
    title: 'Nueva evidencia en texto',
    hintText:
        'Describe el trabajo realizado, hallazgos o avances del servicio.',
    confirmLabel: 'Guardar',
  );
  if (text == null || text.trim().isEmpty) {
    return;
  }

  try {
    await ref.read(provider.notifier).addTextEvidence(text.trim());
    if (!context.mounted) return;
    await AppFeedback.showInfo(context, 'Evidencia agregada');
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo guardar la evidencia',
    );
  }
}

Future<void> _addImageEvidence(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.image,
    withData: true,
  );
  final files = result?.files ?? const <PlatformFile>[];
  if (files.isEmpty) {
    return;
  }

  try {
    var uploadedCount = 0;
    String? lastError;

    for (final file in files) {
      final bytes = file.bytes;
      final path = kIsWeb ? null : file.path;

      if ((bytes == null || bytes.isEmpty) &&
          (path == null || path.trim().isEmpty)) {
        lastError = 'No se pudo leer una de las imagenes seleccionadas';
        continue;
      }

      try {
        await ref
            .read(provider.notifier)
            .addImageEvidence(
              bytes: bytes ?? const <int>[],
              fileName: file.name,
              path: path,
            );
        uploadedCount++;
      } catch (_) {
        lastError =
            ref.read(provider).actionError ??
            'No se pudo subir una de las imagenes';
      }
    }

    if (uploadedCount == 0) {
      if (!context.mounted) return;
      await AppFeedback.showError(
        context,
        lastError ?? 'No se pudo subir ninguna imagen',
      );
      return;
    }

    if (!context.mounted) return;
    final totalSelected = files.length;
    final uploadedMessage = uploadedCount == 1
        ? '1 imagen agregada. Se esta subiendo en segundo plano.'
        : '$uploadedCount imagenes agregadas. Se estan subiendo en segundo plano.';
    final summary = uploadedCount == totalSelected
        ? uploadedMessage
        : '$uploadedMessage ${totalSelected - uploadedCount} no se pudieron procesar.';
    await AppFeedback.showInfo(context, summary);
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo subir la imagen',
    );
  }
}

Future<void> _addVideoEvidence(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: false,
    type: FileType.video,
    withData: true,
  );
  final file = result?.files.singleOrNull;
  if (file == null) {
    return;
  }

  final bytes = file.bytes;
  final path = kIsWeb ? null : file.path;
  if ((bytes == null || bytes.isEmpty) &&
      (path == null || path.trim().isEmpty)) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      'No se pudo leer el video seleccionado',
    );
    return;
  }

  try {
    await ref
        .read(provider.notifier)
        .addVideoEvidence(fileName: file.name, bytes: bytes, path: path);
    if (!context.mounted) return;
    await AppFeedback.showInfo(
      context,
      'Video agregado. Se esta subiendo en segundo plano.',
    );
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo subir el video',
    );
  }
}

Future<void> _addReport(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final reportType = await _pickReportType(context);
  if (reportType == null) {
    return;
  }
  if (!context.mounted) return;

  final report = await _promptMultilineInput(
    context,
    title: reportType.label,
    hintText: _reportHintText(reportType),
    confirmLabel: 'Guardar reporte',
  );
  if (report == null || report.trim().isEmpty) {
    return;
  }

  try {
    await ref.read(provider.notifier).addReport(reportType, report.trim());
    if (!context.mounted) return;
    await AppFeedback.showInfo(context, 'Reporte agregado');
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ?? 'No se pudo guardar el reporte',
    );
  }
}

Future<ServiceReportType?> _pickReportType(BuildContext context) {
  return showModalBottomSheet<ServiceReportType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tipo de reporte',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Selecciona el tipo de reporte que se agregará a esta orden.',
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(sheetContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              _ReportTypeAction(
                type: ServiceReportType.requerimientoCliente,
                subtitle:
                    'Para solicitudes o requerimientos adicionales del cliente',
                icon: Icons.assignment_ind_outlined,
                onTap: () => Navigator.pop(
                  sheetContext,
                  ServiceReportType.requerimientoCliente,
                ),
              ),
              const SizedBox(height: 10),
              _ReportTypeAction(
                type: ServiceReportType.servicioFinalizado,
                subtitle:
                    'Para documentar el cierre o resultado final del servicio',
                icon: Icons.task_alt_outlined,
                onTap: () => Navigator.pop(
                  sheetContext,
                  ServiceReportType.servicioFinalizado,
                ),
              ),
              const SizedBox(height: 10),
              _ReportTypeAction(
                type: ServiceReportType.otros,
                subtitle:
                    'Para otras observaciones importantes relacionadas con la orden',
                icon: Icons.notes_outlined,
                onTap: () =>
                    Navigator.pop(sheetContext, ServiceReportType.otros),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _reportHintText(ServiceReportType type) {
  switch (type) {
    case ServiceReportType.requerimientoCliente:
      return 'Describe el requerimiento del cliente, solicitud adicional o necesidad levantada';
    case ServiceReportType.servicioFinalizado:
      return 'Resume el trabajo finalizado, materiales usados y resultado entregado';
    case ServiceReportType.otros:
      return 'Describe cualquier otra observación, hallazgo o nota importante';
  }
}

Future<String?> _promptMultilineInput(
  BuildContext context, {
  required String title,
  required String hintText,
  required String confirmLabel,
}) async {
  final formKey = GlobalKey<FormState>();
  var draftValue = '';
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: draftValue,
            minLines: 4,
            maxLines: 7,
            autofocus: true,
            decoration: InputDecoration(
              hintText: hintText,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => draftValue = value,
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return 'Este campo es obligatorio';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) {
                return;
              }
              Navigator.of(dialogContext).pop(draftValue.trim());
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result;
}

Future<Map<String, String?>?> _promptOperationalNotes(
  BuildContext context, {
  required String? initialTechnicalNote,
  required String? initialExtraRequirements,
}) async {
  final technicalController = TextEditingController(
    text: initialTechnicalNote ?? '',
  );
  final requirementsController = TextEditingController(
    text: initialExtraRequirements ?? '',
  );

  final result = await showDialog<Map<String, String?>>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Gestionar orden'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: technicalController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Nota técnica',
                  hintText: 'Detalle del trabajo técnico o seguimiento interno',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: requirementsController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Solicitudes del cliente',
                  hintText:
                      'Requisitos, observaciones o solicitudes adicionales',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop({
                'technicalNote': technicalController.text.trim(),
                'extraRequirements': requirementsController.text.trim(),
              });
            },
            child: const Text('Guardar cambios'),
          ),
        ],
      );
    },
  );

  technicalController.dispose();
  requirementsController.dispose();
  return result;
}

Future<void> _editOperationalNotes(
  BuildContext context,
  WidgetRef ref,
  AutoDisposeStateNotifierProvider<
    ServiceOrderDetailController,
    ServiceOrderDetailState
  >
  provider,
) async {
  final state = ref.read(provider);
  final order = state.order;
  if (order == null) {
    return;
  }

  final payload = await _promptOperationalNotes(
    context,
    initialTechnicalNote: order.technicalNote,
    initialExtraRequirements: order.extraRequirements,
  );
  if (payload == null) {
    return;
  }

  try {
    await ref
        .read(provider.notifier)
        .updateOperationalDetails(
          technicalNote: payload['technicalNote'],
          extraRequirements: payload['extraRequirements'],
        );
    if (!context.mounted) return;
    await AppFeedback.showInfo(context, 'Orden actualizada');
  } catch (_) {
    if (!context.mounted) return;
    await AppFeedback.showError(
      context,
      ref.read(provider).actionError ??
          'No se pudieron guardar los cambios operativos',
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.order, this.technicianName});

  final ServiceOrderModel order;
  final String? technicianName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final createdAt = _formatDateTime(order.createdAt);
    final scheduledAt = order.scheduledFor?.toLocal();
    final serviceAt = scheduledAt == null
        ? 'Sin fecha programada'
        : formatServiceScheduledDateTime(scheduledAt);
    final serviceBucket = resolveServiceScheduleDayBucket(scheduledAt);
    final lastStatusAt = formatServiceScheduledDateTime(
      order.lastStatusChangedAt ?? order.updatedAt,
    );
    final assignedTechnician = _hasContent(technicianName)
        ? technicianName!.trim()
        : 'Sin asignar';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Orden de servicio · $createdAt',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No. ${_shortOrderId(order.id)} · ${order.serviceType.label} · ${order.category.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _DetailServiceScheduleCard(label: serviceAt, bucket: serviceBucket),
          const SizedBox(height: 8),
          _DetailHeaderLine(
            icon: Icons.engineering_outlined,
            title: 'Técnico asignado',
            value: assignedTechnician,
          ),
          const SizedBox(height: 6),
          _DetailHeaderLine(
            icon: Icons.flag_outlined,
            title: 'Estado actual',
            value: order.status.label,
          ),
          const SizedBox(height: 6),
          _DetailHeaderLine(
            icon: Icons.update_rounded,
            title: 'Último cambio de estado',
            value: lastStatusAt,
          ),
        ],
      ),
    );
  }
}

class _DetailHeaderLine extends StatelessWidget {
  const _DetailHeaderLine({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailServiceScheduleCard extends StatelessWidget {
  const _DetailServiceScheduleCard({required this.label, required this.bucket});

  final String label;
  final ServiceScheduleDayBucket bucket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _detailServiceScheduleStyle(bucket);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: style.border),
      ),
      child: Row(
        children: [
          Icon(
            bucket == ServiceScheduleDayBucket.overdue
                ? Icons.warning_amber_rounded
                : Icons.calendar_today_outlined,
            size: 16,
            color: style.foreground,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Servicio programado',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: style.foreground.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: style.foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailServiceScheduleStyle {
  const _DetailServiceScheduleStyle({
    required this.background,
    required this.border,
    required this.foreground,
  });

  final Color background;
  final Color border;
  final Color foreground;
}

_DetailServiceScheduleStyle _detailServiceScheduleStyle(
  ServiceScheduleDayBucket bucket,
) {
  switch (bucket) {
    case ServiceScheduleDayBucket.unscheduled:
      return const _DetailServiceScheduleStyle(
        background: Color(0xFFF4F6F8),
        border: Color(0xFFD5DCE3),
        foreground: Color(0xFF4C6072),
      );
    case ServiceScheduleDayBucket.today:
      return const _DetailServiceScheduleStyle(
        background: Color(0xFFE8F3FF),
        border: Color(0xFF8CB9E8),
        foreground: Color(0xFF0F4E8A),
      );
    case ServiceScheduleDayBucket.overdue:
      return const _DetailServiceScheduleStyle(
        background: Color(0xFFFFF1F0),
        border: Color(0xFFF2B8B5),
        foreground: Color(0xFF9F2D2A),
      );
    case ServiceScheduleDayBucket.tomorrow:
    case ServiceScheduleDayBucket.future:
      return const _DetailServiceScheduleStyle(
        background: Color(0xFFEFF6FF),
        border: Color(0xFFB2C8E7),
        foreground: Color(0xFF1E4F87),
      );
    case ServiceScheduleDayBucket.yesterday:
    case ServiceScheduleDayBucket.past:
      return const _DetailServiceScheduleStyle(
        background: Color(0xFFFFF8E6),
        border: Color(0xFFE8CF91),
        foreground: Color(0xFF8A5B00),
      );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.inverted = false});

  final ServiceOrderStatus status;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: inverted
            ? Colors.white.withValues(alpha: 0.16)
            : status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: inverted
              ? Colors.white.withValues(alpha: 0.24)
              : status.color.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: inverted ? Colors.white : status.color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
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
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((subtitle ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
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

class ExpandableSectionCard extends StatelessWidget {
  const ExpandableSectionCard({
    super.key,
    required this.storageKey,
    required this.expanded,
    required this.onToggle,
    required this.title,
    required this.child,
    required this.icon,
    required this.collapsedSummary,
    this.subtitle,
  });

  final String storageKey;
  final bool expanded;
  final VoidCallback onToggle;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final String collapsedSummary;

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
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((subtitle ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (collapsedSummary.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              collapsedSummary,
                              maxLines: expanded ? null : 2,
                              overflow: expanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: child,
              ),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 220),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailWarmupShell extends StatelessWidget {
  const _DetailWarmupShell({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF102542), Color(0xFF0F7B6C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22102542),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Detalle operativo',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message ??
                    'La vista local del modulo se prepara mientras la sincronizacion continua en segundo plano.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _PlaceholderChip(label: 'Sincronizacion silenciosa'),
                  _PlaceholderChip(label: 'Datos locales'),
                  _PlaceholderChip(label: 'Actualizacion en segundo plano'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _DetailPlaceholderCard(
          title: 'Estado operativo',
          subtitle: 'Recuperando la informacion principal de la orden.',
          icon: Icons.tune_rounded,
          lineCount: 3,
        ),
        const SizedBox(height: 18),
        const _DetailPlaceholderCard(
          title: 'Referencia',
          subtitle: 'Mostrando el contexto disponible sin bloquear la vista.',
          icon: Icons.forum_rounded,
          lineCount: 3,
        ),
        const SizedBox(height: 18),
        const _DetailPlaceholderCard(
          title: 'Reporte tecnico',
          subtitle: 'Los datos nuevos llegan cuando termina la sincronizacion.',
          icon: Icons.description_outlined,
          lineCount: 2,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'La sincronizacion sigue en segundo plano para no interrumpir el trabajo.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusHistorySection extends StatelessWidget {
  const _StatusHistorySection({required this.order});

  final ServiceOrderModel order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = order.statusHistory;

    if (entries.isEmpty) {
      final fallbackAt = order.lastStatusChangedAt ?? order.updatedAt;
      return Text(
        'Último estado: ${order.status.label} · ${_formatDateTime(fallbackAt)}',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: entry.nextStatus.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.previousStatus == null
                            ? '${entry.nextStatus.label} (estado inicial)'
                            : '${entry.previousStatus!.label} → ${entry.nextStatus.label}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDateTime(entry.changedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if ((entry.changedByUserName ?? '').trim().isNotEmpty)
                        Text(
                          'Por: ${entry.changedByUserName!.trim()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if ((entry.note ?? '').trim().isNotEmpty)
                        Text(
                          'Nota: ${entry.note!.trim()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DetailPlaceholderCard extends StatelessWidget {
  const _DetailPlaceholderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.lineCount,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int lineCount;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      icon: icon,
      title: title,
      subtitle: subtitle,
      child: Column(
        children: List.generate(
          lineCount,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: index == lineCount - 1 ? 0 : 12),
            child: _PlaceholderLine(
              widthFactor: index == lineCount - 1 ? 0.56 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderLine extends StatelessWidget {
  const _PlaceholderLine({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF102542).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _PlaceholderChip extends StatelessWidget {
  const _PlaceholderChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum EvidenceCardVariant { reference, technical }

class _EvidenceCollection extends StatelessWidget {
  const _EvidenceCollection({required this.items, required this.variant});

  static const double _compactCardWidth = 228;
  static const double _compactCarouselHeight = 286;

  final List<ServiceOrderEvidenceModel> items;
  final EvidenceCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final imageItems = items
        .where((item) => item.type.isImage)
        .toList(growable: false);
    final otherItems = items
        .where((item) => !item.type.isImage)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (imageItems.isNotEmpty) ...[
          SizedBox(
            height: _compactCarouselHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imageItems.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final evidence = imageItems[index];
                return SizedBox(
                  width: _compactCardWidth,
                  child: _FadeSlideIn(
                    delayMs: 30 * index,
                    child: EvidenceCard(
                      evidence: evidence,
                      variant: variant,
                      compactMedia: true,
                    ),
                  ),
                );
              },
            ),
          ),
          if (otherItems.isNotEmpty) const SizedBox(height: 14),
        ],
        if (otherItems.isNotEmpty)
          Column(
            children: otherItems
                .asMap()
                .entries
                .map(
                  (entry) => Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == otherItems.length - 1 ? 0 : 12,
                    ),
                    child: _FadeSlideIn(
                      delayMs: 40 * entry.key,
                      child: EvidenceCard(
                        evidence: entry.value,
                        variant: variant,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class EvidenceCard extends StatelessWidget {
  const EvidenceCard({
    super.key,
    required this.evidence,
    required this.variant,
    this.compactMedia = false,
  });

  final ServiceOrderEvidenceModel evidence;
  final EvidenceCardVariant variant;
  final bool compactMedia;

  @override
  Widget build(BuildContext context) {
    final tint = variant == EvidenceCardVariant.reference
        ? const Color(0xFFF3F5FB)
        : Colors.white;
    final borderColor = variant == EvidenceCardVariant.reference
        ? const Color(0xFFE0E7F3)
        : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.8);
    final iconColor = evidence.type.isText
        ? const Color(0xFF5B5F97)
        : evidence.type.isImage
        ? const Color(0xFF0F8C6B)
        : const Color(0xFF2563EB);

    if (compactMedia && evidence.type.isImage) {
      return _CompactImageEvidenceCard(
        evidence: evidence,
        tint: tint,
        borderColor: borderColor,
        iconColor: iconColor,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    evidence.type.isText
                        ? Icons.notes_rounded
                        : evidence.type.isImage
                        ? Icons.image_outlined
                        : Icons.videocam_outlined,
                    size: 18,
                    color: iconColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    evidence.type.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  DateFormat(
                    'dd/MM h:mm a',
                    'es_DO',
                  ).format(evidence.createdAt.toLocal()),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (evidence.isPendingUpload) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ] else if (evidence.hasUploadError) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            EvidenceItemWidget(
              type: evidence.type,
              url: evidence.type.isText ? null : evidence.content,
              text: evidence.type.isText ? evidence.content : null,
              createdAt: evidence.createdAt,
              localPath: evidence.localPath,
              previewBytes: evidence.previewBytes,
              fileName: evidence.fileName,
              compact: compactMedia,
              showHeader: false,
              showSurface: false,
            ),
            if (evidence.isPendingUpload) ...[
              const SizedBox(height: 8),
              Text(
                'Subiendo al servidor en segundo plano...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (evidence.hasUploadError) ...[
              const SizedBox(height: 8),
              Text(
                'La subida fallo. Puedes reintentar agregando el archivo nuevamente.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompactImageEvidenceCard extends StatelessWidget {
  const _CompactImageEvidenceCard({
    required this.evidence,
    required this.tint,
    required this.borderColor,
    required this.iconColor,
  });

  final ServiceOrderEvidenceModel evidence;
  final Color tint;
  final Color borderColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: EvidenceItemWidget(
                  type: evidence.type,
                  url: evidence.content,
                  createdAt: evidence.createdAt,
                  localPath: evidence.localPath,
                  previewBytes: evidence.previewBytes,
                  fileName: evidence.fileName,
                  compact: true,
                  showHeader: false,
                  showSurface: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.image_outlined, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        evidence.type.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat(
                          'dd/MM/yyyy h:mm a',
                          'es_DO',
                        ).format(evidence.createdAt.toLocal()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (evidence.isPendingUpload) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ] else if (evidence.hasUploadError) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                ],
              ],
            ),
            if (evidence.isPendingUpload) ...[
              const SizedBox(height: 8),
              Text(
                'Subiendo al servidor en segundo plano...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (evidence.hasUploadError) ...[
              const SizedBox(height: 8),
              Text(
                'La subida fallo. Puedes reintentar agregando el archivo nuevamente.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent(value)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value!.trim(),
          style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 8),
        Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ],
    );
  }
}

class _QuotationSection extends StatelessWidget {
  const _QuotationSection({required this.quotation});

  final CotizacionModel quotation;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy h:mm a', 'es_DO');
    final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
    final money = rdAccountingNumberFormat();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7E4F4)),
          ),
          child: Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _QuotationMetaBlock(
                label: 'Cotización',
                value: _shortQuotationId(quotation.id),
              ),
              _QuotationMetaBlock(
                label: 'Fecha',
                value: dateFmt.format(quotation.createdAt.toLocal()),
              ),
              _QuotationMetaBlock(
                label: 'Condición fiscal',
                value: quotation.includeItbis
                    ? '${(quotation.itbisRate * 100).toStringAsFixed(0)}% ITBIS'
                    : 'Sin ITBIS',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Detalle de ventas',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD7E4F4)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 420;
              return Table(
                columnWidths: compact
                    ? const {
                        0: FlexColumnWidth(4.9),
                        1: FlexColumnWidth(1.0),
                        2: FlexColumnWidth(1.45),
                        3: FlexColumnWidth(1.45),
                      }
                    : const {
                        0: FlexColumnWidth(4.6),
                        1: FlexColumnWidth(1.1),
                        2: FlexColumnWidth(1.6),
                        3: FlexColumnWidth(1.7),
                      },
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFEAF1FF)),
                    children: [
                      _QuotationTableHeaderCell(
                        text: compact ? 'Desc.' : 'Descripción',
                        align: TextAlign.left,
                        compact: compact,
                      ),
                      _QuotationTableHeaderCell(
                        text: 'Cant.',
                        align: TextAlign.center,
                        compact: compact,
                      ),
                      _QuotationTableHeaderCell(
                        text: compact ? 'Unit.' : 'Unitario',
                        align: TextAlign.right,
                        compact: compact,
                      ),
                      _QuotationTableHeaderCell(
                        text: compact ? 'Imp.' : 'Importe',
                        align: TextAlign.right,
                        compact: compact,
                      ),
                    ],
                  ),
                  if (quotation.items.isEmpty)
                    TableRow(
                      children: [
                        _QuotationTableBodyCell(
                          text: 'No hay items registrados en esta cotización.',
                          compact: compact,
                        ),
                        _QuotationTableBodyCell(
                          text: '-',
                          align: TextAlign.center,
                          compact: compact,
                        ),
                        _QuotationTableBodyCell(
                          text: '-',
                          align: TextAlign.right,
                          compact: compact,
                        ),
                        _QuotationTableBodyCell(
                          text: money.format(0),
                          align: TextAlign.right,
                          emphasized: true,
                          compact: compact,
                        ),
                      ],
                    )
                  else
                    for (var index = 0; index < quotation.items.length; index++)
                      TableRow(
                        decoration: BoxDecoration(
                          color: index.isEven
                              ? Colors.white
                              : const Color(0xFFFAFBFD),
                        ),
                        children: [
                          _QuotationTableBodyCell(
                            text: quotation.items[index].nombre.trim(),
                            compact: compact,
                          ),
                          _QuotationTableBodyCell(
                            text: qtyFmt.format(quotation.items[index].qty),
                            align: TextAlign.center,
                            compact: compact,
                          ),
                          _QuotationTableBodyCell(
                            text: money.format(
                              quotation.items[index].unitPrice,
                            ),
                            align: TextAlign.right,
                            compact: compact,
                          ),
                          _QuotationTableBodyCell(
                            text: money.format(quotation.items[index].total),
                            align: TextAlign.right,
                            emphasized: true,
                            compact: compact,
                          ),
                        ],
                      ),
                ],
              );
            },
          ),
        ),
        if (_hasContent(quotation.note)) ...[
          const SizedBox(height: 16),
          Text(
            'Nota',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFD7E4F4)),
            ),
            child: Text(
              quotation.note.trim(),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ],
    );
  }
}

class _QuotationDialogBody extends StatelessWidget {
  const _QuotationDialogBody({required this.quotation});

  final CotizacionModel quotation;

  @override
  Widget build(BuildContext context) {
    final money = rdAccountingNumberFormat();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: _QuotationSection(quotation: quotation),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFD7E4F4))),
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFD7E4F4)),
                ),
                child: Column(
                  children: [
                    _QuotationTotalRow(
                      label: 'Subtotal',
                      value: money.format(quotation.subtotalBeforeDiscount),
                    ),
                    if (quotation.hasDiscount) ...[
                      const SizedBox(height: 8),
                      _QuotationTotalRow(
                        label: 'Descuento aplicado',
                        value: '-${money.format(quotation.discountAmount)}',
                        valueColor: const Color(0xFFB42318),
                      ),
                      const SizedBox(height: 8),
                      _QuotationTotalRow(
                        label: 'Subtotal con descuento',
                        value: money.format(quotation.subtotal),
                      ),
                    ],
                    if (quotation.includeItbis) ...[
                      const SizedBox(height: 8),
                      _QuotationTotalRow(
                        label: 'ITBIS',
                        value: money.format(quotation.itbisAmount),
                      ),
                    ],
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1),
                    ),
                    _QuotationTotalRow(
                      label: 'Total general',
                      value: money.format(quotation.total),
                      emphasized: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactQuotationDetails extends StatelessWidget {
  const _CompactQuotationDetails({
    required this.quotation,
    required this.onOpen,
    this.onEdit,
  });

  final CotizacionModel quotation;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final money = rdAccountingNumberFormat();
    final theme = Theme.of(context);
    final dateText = DateFormat(
      'dd/MM/yyyy',
      'es_DO',
    ).format(quotation.createdAt.toLocal());
    final firstItem = quotation.items.isEmpty ? null : quotation.items.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No. ${_shortQuotationId(quotation.id)} · $dateText · ${quotation.items.length} items · ${money.format(quotation.total)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (firstItem != null) ...[
          const SizedBox(height: 4),
          Text(
            '${firstItem.nombre.trim()} · ${firstItem.qty} x ${money.format(firstItem.unitPrice)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onOpen,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Ver detalle'),
            ),
            if (onEdit != null) ...[
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onEdit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _QuotationMetaBlock extends StatelessWidget {
  const _QuotationMetaBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuotationTableHeaderCell extends StatelessWidget {
  const _QuotationTableHeaderCell({
    required this.text,
    this.align = TextAlign.left,
    this.compact = false,
  });

  final String text;
  final TextAlign align;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = compact ? 6.0 : 12.0;
    final verticalPadding = compact ? 8.0 : 12.0;
    final alignment = align == TextAlign.right
        ? Alignment.centerRight
        : align == TextAlign.center
        ? Alignment.center
        : Alignment.centerLeft;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: align,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF163A63),
              fontSize: compact ? 12 : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _QuotationTableBodyCell extends StatelessWidget {
  const _QuotationTableBodyCell({
    required this.text,
    this.align = TextAlign.left,
    this.emphasized = false,
    this.compact = false,
  });

  final String text;
  final TextAlign align;
  final bool emphasized;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = compact ? 6.0 : 12.0;
    final verticalPadding = compact ? 8.0 : 12.0;
    final alignment = align == TextAlign.right
        ? Alignment.centerRight
        : align == TextAlign.center
        ? Alignment.center
        : Alignment.centerLeft;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
      fontSize: compact ? 12 : null,
    );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFD7E4F4))),
      ),
      child: Align(
        alignment: alignment,
        child: align == TextAlign.left
            ? Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                textAlign: align,
                style: style,
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: align,
                  style: style,
                ),
              ),
      ),
    );
  }
}

class _QuotationTotalRow extends StatelessWidget {
  const _QuotationTotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasized;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textStyle = emphasized
        ? Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);

    return Row(
      children: [
        Expanded(child: Text(label, style: textStyle)),
        Text(value, style: textStyle?.copyWith(color: valueColor)),
      ],
    );
  }
}

String _buildQuotationSummary(CotizacionModel? quotation) {
  if (quotation == null) {
    return 'Sin cotización vinculada.';
  }

  final money = rdAccountingNumberFormat();
  return 'Total ${money.format(quotation.total)}';
}

String _buildReportsSummary(List<ServiceOrderReportModel> reports) {
  if (reports.isEmpty) {
    return 'Sin reportes registrados.';
  }
  if (reports.length == 1) {
    return '1 reporte registrado';
  }
  return '${reports.length} reportes registrados';
}

bool _hasContent(String? value) {
  return (value ?? '').trim().isNotEmpty;
}

String _buildWhatsAppReadyOrderMessage(
  ServiceOrderModel order,
  ServiceOrderDetailState state,
) {
  final client = state.client ?? order.client;
  final quotation = state.quotation;
  final sections = <String>[
    '*DETALLE DE ORDEN ${_shortOrderId(order.id)}*',
    _buildClientWhatsappSection(client),
    _buildOrderWhatsappSection(order, state),
    _buildEvidenceWhatsappSection(
      title: 'REFERENCIAS',
      items: order.referenceItems,
    ),
    _buildEvidenceWhatsappSection(
      title: 'EVIDENCIAS TÉCNICAS',
      items: order.technicalEvidenceItems,
    ),
    _buildReportsWhatsappSection(order, state),
    _buildQuotationWhatsappSection(quotation),
  ];

  return sections.where((section) => section.trim().isNotEmpty).join('\n\n');
}

String _buildClientWhatsappSection(ClienteModel? client) {
  final lines = <String>['*CLIENTE*'];

  if (client == null) {
    lines.add('Nombre: No disponible');
    return lines.join('\n');
  }

  lines.add(
    'Nombre: ${_valueOrFallback(client.nombre, fallback: 'No disponible')}',
  );
  lines.add(
    'Teléfono: ${_valueOrFallback(client.telefono, fallback: 'No disponible')}',
  );
  if (_hasContent(client.locationUrl)) {
    lines.add('Ubicación: ${client.locationUrl!.trim()}');
  }
  if (_hasContent(client.direccion)) {
    lines.add('Dirección: ${client.direccion!.trim()}');
  }
  if (_hasContent(client.correo)) {
    lines.add('Correo: ${client.correo!.trim()}');
  }

  return lines.join('\n');
}

String _buildOrderWhatsappSection(
  ServiceOrderModel order,
  ServiceOrderDetailState state,
) {
  final technicianName = order.assignedToId == null
      ? null
      : state.usersById[order.assignedToId!]?.nombreCompleto ??
            order.assignedToId;
  final creatorName =
      state.usersById[order.createdById]?.nombreCompleto ?? order.createdById;
  final lines = <String>[
    '*ORDEN*',
    'No. orden: ${_shortOrderId(order.id)}',
    'Estado: ${order.status.label}',
    'Tipo de servicio: ${order.serviceType.label}',
    'Categoría: ${order.category.label}',
    'Creada por: ${creatorName.trim()}',
    'Fecha de creación: ${_formatDateTime(order.createdAt)}',
    'Última actualización: ${_formatDateTime(order.updatedAt)}',
  ];

  if (_hasContent(technicianName)) {
    lines.add('Técnico asignado: ${technicianName!.trim()}');
  }
  if (order.scheduledFor != null) {
    lines.add('Fecha programada: ${_formatDateTime(order.scheduledFor!)}');
  }
  if (order.finalizedAt != null) {
    lines.add('Fecha de finalización: ${_formatDateTime(order.finalizedAt!)}');
  }
  if (_hasContent(order.technicalNote)) {
    lines.add('Nota técnica: ${order.technicalNote!.trim()}');
  }
  if (_hasContent(order.extraRequirements)) {
    lines.add('Requisitos extra: ${order.extraRequirements!.trim()}');
  }

  return lines.join('\n');
}

String _buildEvidenceWhatsappSection({
  required String title,
  required List<ServiceOrderEvidenceModel> items,
}) {
  final lines = <String>['*$title*'];
  if (items.isEmpty) {
    lines.add('Sin registros');
    return lines.join('\n');
  }

  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final label = item.type.label;
    if (item.type.isText) {
      lines.add('${index + 1}. $label: ${_valueOrFallback(item.content)}');
      continue;
    }

    final link = _buildEvidenceShareLink(item);
    final fileName = (item.fileName ?? '').trim();
    final parts = <String>['${index + 1}. $label'];
    if (fileName.isNotEmpty) {
      parts.add(fileName);
    }
    if (link.isNotEmpty) {
      parts.add(link);
    }
    if (item.isPendingUpload) {
      parts.add('(pendiente de subir)');
    }
    lines.add(parts.join(' - '));
  }

  return lines.join('\n');
}

String _buildReportsWhatsappSection(
  ServiceOrderModel order,
  ServiceOrderDetailState state,
) {
  final lines = <String>['*REPORTES*'];
  if (order.reports.isEmpty) {
    lines.add('Sin reportes');
    return lines.join('\n');
  }

  for (var index = 0; index < order.reports.length; index++) {
    final report = order.reports[index];
    final authorName =
        state.usersById[report.createdById]?.nombreCompleto ??
        report.createdById;
    lines.add(
      '${index + 1}. ${report.type.label}: ${report.report.trim()} (${authorName.trim()} - ${_formatDateTime(report.createdAt)})',
    );
  }
  return lines.join('\n');
}

String _buildQuotationWhatsappSection(CotizacionModel? quotation) {
  final lines = <String>['*COTIZACIÓN*'];
  if (quotation == null) {
    lines.add('Sin cotización vinculada');
    return lines.join('\n');
  }

  final money = rdAccountingNumberFormat();
  final qtyFmt = NumberFormat('#,##0.##', 'es_DO');
  lines.add('No. cotización: ${_shortQuotationId(quotation.id)}');
  lines.add('Fecha: ${_formatDateTime(quotation.createdAt)}');

  if (quotation.items.isEmpty) {
    lines.add('Detalle: Sin items');
  } else {
    lines.add('Detalle:');
    for (var index = 0; index < quotation.items.length; index++) {
      final item = quotation.items[index];
      lines.add(
        '${index + 1}. ${item.nombre.trim()} | Cant: ${qtyFmt.format(item.qty)} | Unit: ${money.format(item.unitPrice)} | Importe: ${money.format(item.total)}',
      );
    }
  }

  if (_hasContent(quotation.note)) {
    lines.add('Observación: ${quotation.note.trim()}');
  }

  lines.add('Subtotal: ${money.format(quotation.subtotalBeforeDiscount)}');
  if (quotation.hasDiscount) {
    lines.add('Descuento aplicado: -${money.format(quotation.discountAmount)}');
    lines.add('Subtotal con descuento: ${money.format(quotation.subtotal)}');
  }
  if (quotation.includeItbis) {
    lines.add('ITBIS: ${money.format(quotation.itbisAmount)}');
  }
  lines.add('Total general: ${money.format(quotation.total)}');

  return lines.join('\n');
}

String _buildEvidenceShareLink(ServiceOrderEvidenceModel item) {
  final content = item.content.trim();
  final localPath = (item.localPath ?? '').trim();
  if (content.isNotEmpty) return content;
  if (localPath.isNotEmpty) return localPath;
  return '';
}

String _formatDateTime(DateTime value) {
  return DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(value.toLocal());
}

String _valueOrFallback(String? value, {String fallback = 'No disponible'}) {
  final normalized = (value ?? '').trim();
  return normalized.isEmpty ? fallback : normalized;
}

String _shortQuotationId(String id) {
  final normalized = id.trim().toUpperCase();
  if (normalized.length <= 8) return normalized;
  return normalized.substring(0, 8);
}

String _shortOrderId(String id) {
  final normalized = id.trim().toUpperCase();
  if (normalized.isEmpty) return 'SIN ID';
  if (normalized.length <= 10) return normalized;
  return normalized.substring(0, 10);
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.authorName});

  final ServiceOrderReportModel report;
  final String? authorName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 0, 0, 8),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: report.type.color.withValues(alpha: 0.55),
            width: 3,
          ),
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.38),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.type.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: report.type.color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            report.report,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${authorName ?? report.createdById} · ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(report.createdAt.toLocal())}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTypeAction extends StatelessWidget {
  const _ReportTypeAction({
    required this.type,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final ServiceReportType type;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
            color: theme.colorScheme.surfaceContainerLow,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: type.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message),
    );
  }
}

class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (context, value, innerChild) {
        final dy = (1 - value) * 10;
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0, dy), child: innerChild),
        );
      },
      child: child,
    );
  }
}
