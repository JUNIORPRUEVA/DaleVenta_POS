import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../service_order_models.dart';
import '../application/service_order_card_actions_controller.dart';
import 'evidence_item_widget.dart';
import 'service_order_status_confirmation_dialog.dart';

enum _EvidencePickType { image, video }

enum _ActionTone { primary, secondary, neutral }

enum ServiceOrderQuickActionsPresentation { bottomSheet, mobileRightPanel }

class ServiceOrderQuickActionsConfig {
  const ServiceOrderQuickActionsConfig({
    this.clientCallUri,
    this.clientWhatsAppUri,
    this.locationUri,
    this.sellerConversationUri,
    this.supportConversationUri,
  });

  final Uri? clientCallUri;
  final Uri? clientWhatsAppUri;
  final Uri? locationUri;
  final Uri? sellerConversationUri;
  final Uri? supportConversationUri;
}

Future<void> showServiceOrderQuickActionsModal({
  required BuildContext context,
  required WidgetRef ref,
  required String orderId,
  required ServiceOrderModel order,
  required VoidCallback onOrderUpdated,
  ServiceOrderQuickActionsPresentation presentation =
      ServiceOrderQuickActionsPresentation.bottomSheet,
  ServiceOrderQuickActionsConfig actionConfig =
      const ServiceOrderQuickActionsConfig(),
}) async {
  if (presentation == ServiceOrderQuickActionsPresentation.mobileRightPanel) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Panel de gestión',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (sheetContext, animation, secondaryAnimation) {
        return _ServiceOrderQuickActionsSheet(
          orderId: orderId,
          order: order,
          parentContext: context,
          onOrderUpdated: onOrderUpdated,
          actionConfig: actionConfig,
          presentation: presentation,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.12, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (sheetContext) {
      return _ServiceOrderQuickActionsSheet(
        orderId: orderId,
        order: order,
        parentContext: context,
        onOrderUpdated: onOrderUpdated,
        actionConfig: actionConfig,
        presentation: presentation,
      );
    },
  );
}

class _ServiceOrderQuickActionsSheet extends ConsumerWidget {
  const _ServiceOrderQuickActionsSheet({
    required this.orderId,
    required this.order,
    required this.parentContext,
    required this.onOrderUpdated,
    required this.actionConfig,
    required this.presentation,
  });

  final String orderId;
  final ServiceOrderModel order;
  final BuildContext parentContext;
  final VoidCallback onOrderUpdated;
  final ServiceOrderQuickActionsConfig actionConfig;
  final ServiceOrderQuickActionsPresentation presentation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serviceOrderCardActionsProvider(orderId));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final isMobileRightPanel =
        presentation == ServiceOrderQuickActionsPresentation.mobileRightPanel;
    final targetWidth = screenSize.width >= 900
        ? 336.0
        : screenSize.width >= 600
        ? 322.0
        : (screenSize.width * 0.82).clamp(286.0, 332.0);
    final isPhoneWidth = screenSize.width < 600;
    final isTechnicianMobilePanel = isMobileRightPanel;
    final allowedStatuses = order.status.nextStatusesForRole(
      canFinalizeDirectly: true,
    );
    final statusSequence = isTechnicianMobilePanel
        ? <ServiceOrderStatus>[
            ServiceOrderStatus.enProceso,
            ServiceOrderStatus.enPausa,
            ServiceOrderStatus.finalizado,
          ]
        : <ServiceOrderStatus>[
            ServiceOrderStatus.pendiente,
            ServiceOrderStatus.enProceso,
            ServiceOrderStatus.enPausa,
            ServiceOrderStatus.finalizado,
            ServiceOrderStatus.pospuesta,
            ServiceOrderStatus.cancelado,
          ];
    final visibleStatusOptions = statusSequence
        .where((status) {
          return status == order.status || allowedStatuses.contains(status);
        })
        .toList(growable: false);
    final reportActionCards = <_ActionButton>[
      if (isTechnicianMobilePanel)
        _ActionButton(
          icon: Icons.notes_rounded,
          label: 'Texto',
          tone: _ActionTone.secondary,
          isLoading: state.loading,
          minHeight: 44,
          compact: true,
          onTap: state.loading ? null : () => _addTextEvidence(context, ref),
        )
      else
        _ActionButton(
          icon: Icons.description_outlined,
          label: 'Reporte final',
          tone: _ActionTone.secondary,
          isLoading: state.loading,
          minHeight: 52,
          onTap: state.loading ? null : () => _addFinalReport(context, ref),
        ),
      _ActionButton(
        icon: Icons.perm_media_outlined,
        label: 'Medias',
        tone: _ActionTone.secondary,
        isLoading: state.loading,
        minHeight: isTechnicianMobilePanel ? 44 : 52,
        compact: isTechnicianMobilePanel,
        onTap: state.loading ? null : () => _openMediaManager(context, ref),
      ),
    ];
    final contactActionCards = <_ActionButton>[
      if (actionConfig.clientCallUri != null)
        _ActionButton(
          icon: Icons.call_outlined,
          label: 'Llamar cliente',
          isLoading: state.loading,
          minHeight: isTechnicianMobilePanel ? 44 : 52,
          compact: isTechnicianMobilePanel,
          onTap: () => _openExternalAction(
            context,
            actionConfig.clientCallUri!,
            copiedMessage: 'No se pudo iniciar la llamada. Numero copiado.',
          ),
        ),
      if (actionConfig.clientWhatsAppUri != null)
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          label: 'WhatsApp cliente',
          isLoading: state.loading,
          minHeight: isTechnicianMobilePanel ? 44 : 52,
          compact: isTechnicianMobilePanel,
          onTap: () => _openExternalAction(
            context,
            actionConfig.clientWhatsAppUri!,
            isWhatsApp: true,
            copiedMessage: 'No se pudo abrir WhatsApp. Enlace copiado.',
          ),
        ),
      if (actionConfig.locationUri != null)
        _ActionButton(
          icon: Icons.location_searching_rounded,
          label: 'Ir al GPS',
          isLoading: state.loading,
          minHeight: isTechnicianMobilePanel ? 44 : 52,
          compact: isTechnicianMobilePanel,
          onTap: () => _openExternalAction(
            context,
            actionConfig.locationUri!,
            copiedMessage: 'No se pudo abrir el GPS. Enlace copiado.',
          ),
        ),
      if (actionConfig.sellerConversationUri != null)
        _ActionButton(
          icon: Icons.support_agent_rounded,
          label: 'Vendedor',
          isLoading: state.loading,
          minHeight: isTechnicianMobilePanel ? 44 : 52,
          compact: isTechnicianMobilePanel,
          onTap: () => _openExternalAction(
            context,
            actionConfig.sellerConversationUri!,
            copiedMessage:
                'No se pudo abrir el contacto del vendedor. Enlace copiado.',
          ),
        ),
      if (actionConfig.supportConversationUri != null)
        _ActionButton(
          icon: Icons.headset_mic_outlined,
          label: 'Servicio al cliente',
          isLoading: state.loading,
          minHeight: isTechnicianMobilePanel ? 44 : 52,
          compact: isTechnicianMobilePanel,
          onTap: () => _openExternalAction(
            context,
            actionConfig.supportConversationUri!,
            copiedMessage:
                'No se pudo abrir servicio al cliente. Enlace copiado.',
          ),
        ),
    ];
    final clientName = (order.client?.nombre ?? 'Cliente ${order.clientId}')
        .trim();
    final serviceSummary =
        '${order.serviceType.label} · ${order.category.label}';
    final scheduledAtLabel = _formatScheduledAt(order.scheduledFor);

    final statusSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: Icons.sync_alt_rounded, title: 'Cambiar estado'),
        const SizedBox(height: 8),
        for (var index = 0; index < visibleStatusOptions.length; index++) ...[
          _ActionButton(
            icon: _statusIcon(visibleStatusOptions[index]),
            label: visibleStatusOptions[index].label,
            tone: _statusTone(visibleStatusOptions[index]),
            isLoading: state.loading,
            selected: visibleStatusOptions[index] == order.status,
            minHeight: 58,
            onTap: state.loading || visibleStatusOptions[index] == order.status
                ? null
                : () => _changeStatusDirect(
                    context,
                    ref,
                    visibleStatusOptions[index],
                    successMessage:
                        'Orden marcada ${visibleStatusOptions[index].confirmationLabel}',
                    requireDetailedConfirmation: isTechnicianMobilePanel,
                    clientName: clientName,
                  ),
          ),
          if (index < visibleStatusOptions.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Divider(
                height: 1,
                thickness: 0.8,
                color: colorScheme.outlineVariant.withValues(alpha: 0.22),
              ),
            ),
        ],
      ],
    );

    final quickActionsSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          icon: isTechnicianMobilePanel
              ? Icons.assignment_outlined
              : Icons.flash_on_rounded,
          title: isTechnicianMobilePanel ? 'Reportes' : 'Acciones rápidas',
        ),
        const SizedBox(height: 8),
        if (isTechnicianMobilePanel)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.52,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.75),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video: 1 a 2 videos · Imagen: 3 a 5 imágenes · Texto: obligatorio',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.58),
            ),
          ),
          child: Column(
            children: [
              for (
                var index = 0;
                index < reportActionCards.length;
                index++
              ) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: reportActionCards[index],
                ),
                if (index < reportActionCards.length - 1)
                  Divider(
                    height: 1,
                    thickness: 0.8,
                    indent: 12,
                    endIndent: 12,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.24),
                  ),
              ],
            ],
          ),
        ),
        if (contactActionCards.isNotEmpty) ...[
          const SizedBox(height: 10),
          _SectionTitle(icon: Icons.hub_outlined, title: 'Soporte'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surface.withValues(alpha: 0.86),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.58),
              ),
            ),
            child: Column(
              children: [
                for (
                  var index = 0;
                  index < contactActionCards.length;
                  index++
                ) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: contactActionCards[index],
                  ),
                  if (index < contactActionCards.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.8,
                      indent: 12,
                      endIndent: 12,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.24),
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    if (isMobileRightPanel) {
      final panelWidth = isPhoneWidth
          ? (screenSize.width * 0.56).clamp(220.0, 320.0)
          : (screenSize.width * 0.82).clamp(
              screenSize.width * 0.78,
              screenSize.width * 0.86,
            );
      return SafeArea(
        top: false,
        bottom: false,
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.surface,
                      colorScheme.surfaceContainerLow.withValues(alpha: 0.98),
                    ],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(26),
                    bottomLeft: Radius.circular(26),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2A102A43),
                      blurRadius: 28,
                      offset: Offset(-8, 0),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        isPhoneWidth
                            ? MediaQuery.paddingOf(context).top + 8
                            : 12,
                        8,
                        8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        clientName.isEmpty
                                            ? 'Cliente sin nombre'
                                            : clientName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.15,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: order.status.color.withValues(
                                          alpha: 0.16,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: Text(
                                        order.status.label,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                              fontSize: 10.8,
                                              color: order.status.color,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.48),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    scheduledAtLabel == null
                                        ? serviceSummary
                                        : "$serviceSummary · $scheduledAtLabel",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          fontSize: 11.4,
                                          color: colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.34),
                    ),
                    if (state.error != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.error!,
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        primary: false,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            statusSection,
                            const SizedBox(height: 14),
                            quickActionsSection,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Align(
          alignment: Alignment.bottomRight,
          child: ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: targetWidth),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.surface.withValues(alpha: 0.98),
                    const Color(0xFFF7FBFD),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.58),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18102542),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 34,
                        height: 3,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.58,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (state.error != null) ...[
                      Container(
                        margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.error!,
                          style: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    statusSection,
                    const SizedBox(height: 10),
                    quickActionsSection,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeStatusDirect(
    BuildContext sheetContext,
    WidgetRef ref,
    ServiceOrderStatus selected, {
    required String successMessage,
    required bool requireDetailedConfirmation,
    required String clientName,
  }) async {
    if (selected == order.status) {
      return;
    }

    if (requireDetailedConfirmation &&
        selected == ServiceOrderStatus.finalizado &&
        order.serviceType == ServiceOrderType.instalacion) {
      final hasIncomplete =
          _validateTechnicianCommitmentBeforeFinalize() != null;
      if (hasIncomplete) {
        if (!sheetContext.mounted) return;
        final proceed = await _showInstallationFinalizeWarningDialog(
          sheetContext,
        );
        if (!proceed) return;
      }
    }

    try {
      if (!sheetContext.mounted) return;
      final didChange = requireDetailedConfirmation
          ? await _showTechnicianStatusConfirmDialog(
              // ignore: use_build_context_synchronously
              sheetContext,
              current: order.status,
              selected: selected,
              clientName: clientName,
              onConfirm: () => ref
                  .read(serviceOrderCardActionsProvider(orderId).notifier)
                  .changeStatus(selected),
            )
          : await showServiceOrderStatusConfirmationDialog(
              // ignore: use_build_context_synchronously
              context: sheetContext,
              status: selected,
              initialScheduledAt: order.scheduledFor,
              onConfirm: (scheduledAt) => ref
                  .read(serviceOrderCardActionsProvider(orderId).notifier)
                  .changeStatus(selected, scheduledAt: scheduledAt),
            );

      if (!didChange) {
        return;
      }

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, successMessage);
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo cambiar el estado',
      );
    }
  }

  Future<bool> _showTechnicianStatusConfirmDialog(
    BuildContext context, {
    required ServiceOrderStatus current,
    required ServiceOrderStatus selected,
    required String clientName,
    required Future<void> Function() onConfirm,
  }) async {
    var confirmed = false;
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> handleConfirm() async {
              if (isSubmitting) return;
              setState(() => isSubmitting = true);
              try {
                await onConfirm();
                confirmed = true;
              } finally {
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }
            }

            return AlertDialog(
              title: const Text('Confirmar cambio de estado'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¿Estás seguro de marcar esta orden como ${selected.confirmationLabel.toUpperCase()}?',
                  ),
                  const SizedBox(height: 10),
                  Text('Cliente: $clientName'),
                  const SizedBox(height: 4),
                  Text('Estado actual: ${current.label}'),
                  const SizedBox(height: 2),
                  Text('Estado nuevo: ${selected.label}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : handleConfirm,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );

    return confirmed;
  }

  Future<void> _openMediaManager(
    BuildContext sheetContext,
    WidgetRef ref,
  ) async {
    var selectedType = _EvidencePickType.image;
    var isUploading = false;
    var feedbackMessage =
        'Aquí verás al instante las imágenes y videos que subas.';
    var feedbackIsError = false;
    var mediaItems =
        order.evidences
            .where(
              (item) =>
                  item.type.isTechnicalEvidence &&
                  (item.type.isImage || item.type.isVideo),
            )
            .toList(growable: true)
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    await showModalBottomSheet<void>(
      context: sheetContext,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (mediaContext) {
        final theme = Theme.of(mediaContext);
        final colorScheme = theme.colorScheme;
        final bottomInset = MediaQuery.viewInsetsOf(mediaContext).bottom;

        Future<void> uploadSelectedFiles(StateSetter setModalState) async {
          if (isUploading) {
            return;
          }

          final isVideo = selectedType == _EvidencePickType.video;
          final result = await FilePicker.platform.pickFiles(
            allowMultiple: !isVideo,
            type: isVideo ? FileType.video : FileType.image,
            withData: true,
          );

          final selectedFiles = result?.files ?? const <PlatformFile>[];
          if (selectedFiles.isEmpty) {
            return;
          }

          setModalState(() {
            isUploading = true;
            feedbackIsError = false;
            feedbackMessage = isVideo
                ? 'Subiendo video...'
                : 'Subiendo imágenes...';
          });

          final uploadedItems = <ServiceOrderEvidenceModel>[];
          var failedCount = 0;
          String? lastError;
          final controller = ref.read(
            serviceOrderCardActionsProvider(orderId).notifier,
          );

          for (final file in selectedFiles) {
            final bytes = file.bytes;
            final path = kIsWeb ? null : file.path;

            if ((bytes == null || bytes.isEmpty) &&
                (path == null || path.trim().isEmpty)) {
              failedCount++;
              lastError = 'No se pudo leer uno de los archivos seleccionados';
              continue;
            }

            try {
              final uploadedEvidence = isVideo
                  ? await controller.addVideoEvidence(
                      fileName: file.name,
                      bytes: bytes ?? const <int>[],
                      path: path,
                    )
                  : await controller.addImageEvidence(
                      fileName: file.name,
                      bytes: bytes ?? const <int>[],
                      path: path,
                    );

              uploadedItems.add(
                uploadedEvidence.copyWith(
                  localPath: (path ?? '').trim().isEmpty ? null : path,
                  previewBytes: bytes == null || bytes.isEmpty
                      ? null
                      : Uint8List.fromList(bytes),
                  fileName: file.name,
                ),
              );
            } catch (_) {
              failedCount++;
              lastError =
                  ref.read(serviceOrderCardActionsProvider(orderId)).error ??
                  (isVideo
                      ? 'No se pudo subir el video'
                      : 'No se pudo subir una de las imágenes');
            }
          }

          if (uploadedItems.isNotEmpty) {
            onOrderUpdated();
          }

          setModalState(() {
            isUploading = false;
            if (uploadedItems.isNotEmpty) {
              mediaItems = [...uploadedItems.reversed, ...mediaItems];
              final uploadedCount = uploadedItems.length;
              feedbackIsError = false;
              feedbackMessage = isVideo
                  ? 'Video subido y mostrado correctamente.'
                  : uploadedCount == 1
                  ? 'Imagen subida y mostrada correctamente.'
                  : '$uploadedCount imágenes subidas y mostradas correctamente.';
              if (failedCount > 0) {
                feedbackMessage =
                    '$feedbackMessage $failedCount archivo(s) no se pudieron subir.';
              }
            } else {
              feedbackIsError = true;
              feedbackMessage =
                  lastError ??
                  (isVideo
                      ? 'No se pudo subir el video.'
                      : 'No se pudo subir ninguna imagen.');
            }
          });
        }

        return SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              height: MediaQuery.sizeOf(mediaContext).height * 0.88,
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  final imageCount = mediaItems
                      .where((item) => item.type.isImage)
                      .length;
                  final videoCount = mediaItems
                      .where((item) => item.type.isVideo)
                      .length;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Subir imágenes o videos',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Selecciona el tipo de media, súbela y aquí mismo se mostrará al instante.',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar',
                              onPressed: () => Navigator.pop(mediaContext),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _MediaTypeChip(
                                label: 'Imágenes',
                                icon: Icons.image_outlined,
                                selected:
                                    selectedType == _EvidencePickType.image,
                                onTap: isUploading
                                    ? null
                                    : () {
                                        setModalState(() {
                                          selectedType =
                                              _EvidencePickType.image;
                                        });
                                      },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MediaTypeChip(
                                label: 'Videos',
                                icon: Icons.videocam_outlined,
                                selected:
                                    selectedType == _EvidencePickType.video,
                                onTap: isUploading
                                    ? null
                                    : () {
                                        setModalState(() {
                                          selectedType =
                                              _EvidencePickType.video;
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: feedbackIsError
                                ? colorScheme.errorContainer.withValues(
                                    alpha: 0.92,
                                  )
                                : colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: feedbackIsError
                                  ? colorScheme.error.withValues(alpha: 0.28)
                                  : colorScheme.outlineVariant.withValues(
                                      alpha: 0.7,
                                    ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                feedbackIsError
                                    ? Icons.error_outline_rounded
                                    : Icons.cloud_done_outlined,
                                size: 18,
                                color: feedbackIsError
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  feedbackMessage,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: feedbackIsError
                                        ? colorScheme.onErrorContainer
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _MediaCountPill(
                              icon: Icons.image_outlined,
                              label: '$imageCount imágenes',
                            ),
                            const SizedBox(width: 8),
                            _MediaCountPill(
                              icon: Icons.videocam_outlined,
                              label: '$videoCount videos',
                            ),
                            const Spacer(),
                            FilledButton.icon(
                              onPressed: isUploading
                                  ? null
                                  : () async {
                                      await uploadSelectedFiles(setModalState);
                                    },
                              icon: isUploading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      selectedType == _EvidencePickType.video
                                          ? Icons.upload_file_rounded
                                          : Icons.add_photo_alternate_outlined,
                                      size: 18,
                                    ),
                              label: Text(
                                selectedType == _EvidencePickType.video
                                    ? 'Subir video'
                                    : 'Subir imágenes',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: mediaItems.isEmpty
                              ? Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.collections_outlined,
                                        size: 40,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Todavía no has subido medias',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Sube una imagen o un video y se mostrará aquí mismo para que el técnico confirme lo que agregó.',
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: mediaItems.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) {
                                    final item = mediaItems[index];
                                    return EvidenceItemWidget(
                                      type: item.type,
                                      url: item.content,
                                      text: item.content,
                                      createdAt: item.createdAt,
                                      previewBytes: item.previewBytes,
                                      localPath: item.localPath,
                                      fileName: item.fileName,
                                      compact: true,
                                      surfaceColor: colorScheme.surface,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _addFinalReport(BuildContext sheetContext, WidgetRef ref) async {
    const reportType = ServiceReportType.servicioFinalizado;
    if (!sheetContext.mounted) return;

    final reportText = await _promptMultilineInput(
      sheetContext,
      ref: ref,
      title: 'Reporte final',
      hintText: _reportHintText(reportType),
      confirmLabel: 'Guardar reporte',
    );

    if (reportText == null || reportText.trim().isEmpty) {
      return;
    }

    try {
      await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .addTechnicalReport(reportType, reportText.trim());

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, 'Reporte final guardado');
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo guardar el reporte',
      );
    }
  }

  Future<void> _addTextEvidence(
    BuildContext sheetContext,
    WidgetRef ref,
  ) async {
    if (!sheetContext.mounted) return;

    final textValue = await _promptMultilineInput(
      sheetContext,
      ref: ref,
      title: 'Texto de compromiso',
      hintText:
          'Escribe la evidencia en texto obligatoria para completar la orden.',
      confirmLabel: 'Guardar texto',
    );

    if (textValue == null || textValue.trim().isEmpty) {
      return;
    }

    try {
      await ref
          .read(serviceOrderCardActionsProvider(orderId).notifier)
          .addTextEvidence(textValue.trim());

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);

      if (!parentContext.mounted) return;
      await AppFeedback.showInfo(parentContext, 'Texto guardado correctamente');
      onOrderUpdated();
    } catch (_) {
      if (!sheetContext.mounted) return;
      final error = ref.read(serviceOrderCardActionsProvider(orderId)).error;
      await AppFeedback.showError(
        sheetContext,
        error ?? 'No se pudo guardar el texto',
      );
    }
  }

  Future<void> _openExternalAction(
    BuildContext sheetContext,
    Uri uri, {
    bool isWhatsApp = false,
    required String copiedMessage,
  }) {
    if (isWhatsApp) {
      return safeOpenWhatsApp(sheetContext, uri, copiedMessage: copiedMessage);
    }
    return safeOpenUrl(sheetContext, uri, copiedMessage: copiedMessage);
  }

  static String _reportHintText(ServiceReportType type) {
    switch (type) {
      case ServiceReportType.requerimientoCliente:
        return 'Escribe el requerimiento del cliente, solicitud adicional o necesidad detectada';
      case ServiceReportType.servicioFinalizado:
        return 'Resume el trabajo realizado, materiales usados y resultado final del servicio';
      case ServiceReportType.otros:
        return 'Escribe cualquier observación, hallazgo o nota importante de la orden';
    }
  }

  Future<String?> _promptMultilineInput(
    BuildContext context, {
    required WidgetRef ref,
    required String title,
    required String hintText,
    required String confirmLabel,
  }) async {
    final formKey = GlobalKey<FormState>();
    final textController = TextEditingController();
    final textFocusNode = FocusNode();
    final speech = stt.SpeechToText();
    var isListening = false;
    var voiceSeedText = '';
    var voiceSessionText = '';
    var voiceSessionClosed = false;
    var voiceStopRequested = false;
    var voiceCaption = 'Toca el microfono para dictar por voz';
    String? voiceLocaleId;
    var heardAudioDuringSession = false;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (modalContext) {
        final theme = Theme.of(modalContext);
        final colorScheme = theme.colorScheme;
        final screenHeight = MediaQuery.sizeOf(modalContext).height;
        final bottomInset = MediaQuery.viewInsetsOf(modalContext).bottom;

        Future<void> applyVoiceTranscript(
          StateSetter setModalState, {
          String? sourceText,
          String successCaption = 'Texto colocado en el campo',
        }) async {
          final currentValue = (sourceText ?? textController.text).trim();
          if (currentValue.isEmpty) {
            return;
          }
          textController.value = TextEditingValue(
            text: currentValue,
            selection: TextSelection.collapsed(offset: currentValue.length),
          );
          voiceSeedText = currentValue;
          setModalState(() {
            voiceCaption = successCaption;
          });
          await Future<void>.delayed(const Duration(milliseconds: 32));
          if (!modalContext.mounted) return;
          textFocusNode.requestFocus();
        }

        String mergeVoiceText(String sessionTranscript) {
          return [
            voiceSeedText,
            sessionTranscript.trim(),
          ].where((item) => item.isNotEmpty).join('\n');
        }

        Future<String?> resolveVoiceLocaleId() async {
          if (voiceLocaleId != null) {
            return voiceLocaleId;
          }

          final systemLocale = await speech.systemLocale();
          final locales = await speech.locales();

          stt.LocaleName? preferredLocale;
          final normalizedSystemLocale = systemLocale?.localeId.toLowerCase();

          if (normalizedSystemLocale != null &&
              normalizedSystemLocale.startsWith('es')) {
            for (final locale in locales) {
              if (locale.localeId.toLowerCase() == normalizedSystemLocale) {
                preferredLocale = locale;
                break;
              }
            }
          }

          if (preferredLocale == null && normalizedSystemLocale != null) {
            final systemLanguage = normalizedSystemLocale.split('_').first;
            for (final locale in locales) {
              if (locale.localeId.toLowerCase().split('_').first ==
                  systemLanguage) {
                preferredLocale = locale;
                break;
              }
            }
          }

          if (preferredLocale == null) {
            for (final locale in locales) {
              if (locale.localeId.toLowerCase().startsWith('es')) {
                preferredLocale = locale;
                break;
              }
            }
          }

          voiceLocaleId = systemLocale?.localeId ?? preferredLocale?.localeId;
          return voiceLocaleId;
        }

        Future<bool> ensureMicrophonePermission(
          StateSetter setModalState,
        ) async {
          var status = await Permission.microphone.status;
          if (!status.isGranted) {
            status = await Permission.microphone.request();
          }

          if (status.isGranted) {
            return true;
          }

          if (!modalContext.mounted) {
            return false;
          }

          setModalState(() {
            voiceCaption = status.isPermanentlyDenied
                ? 'El microfono esta bloqueado en Android. Habilitalo en ajustes de la app.'
                : 'No se otorgo permiso al microfono. Sin ese permiso no se puede escuchar el audio.';
          });
          return false;
        }

        Future<void> finalizeVoiceSession(
          StateSetter setModalState, {
          String completedCaption = 'Dictado finalizado',
        }) async {
          if (voiceSessionClosed) {
            return;
          }
          voiceSessionClosed = true;

          if (!modalContext.mounted) {
            return;
          }

          final transcriptToApply = voiceSessionText.trim();

          if (transcriptToApply.isEmpty) {
            setModalState(() {
              isListening = false;
              voiceCaption = heardAudioDuringSession
                  ? 'Se detecto audio, pero no se reconocio texto. Habla mas cerca y mas claro.'
                  : 'No se detecto audio del microfono. Revisa el permiso del microfono y vuelve a intentarlo.';
            });
            return;
          }

          setModalState(() {
            isListening = false;
            voiceCaption = completedCaption;
          });

          await applyVoiceTranscript(
            setModalState,
            sourceText: mergeVoiceText(transcriptToApply),
            successCaption: 'Texto dictado convertido y colocado en el campo',
          );
        }

        Future<void> discardDraftAndClose() async {
          voiceSessionClosed = true;
          if (speech.isListening) {
            try {
              await speech.cancel();
            } catch (_) {}
          }
          textFocusNode.unfocus();
          if (!modalContext.mounted) {
            return;
          }
          Navigator.pop(modalContext);
        }

        Future<void> requestClose() async {
          final hasDraft = textController.text.trim().isNotEmpty;
          if (!hasDraft) {
            await discardDraftAndClose();
            return;
          }

          final shouldDiscard = await showDialog<bool>(
            context: modalContext,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('Descartar reporte'),
                content: const Text(
                  '¿Estas seguro? Esto borrara el texto que ya agregaste.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Seguir editando'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Borrar y cerrar'),
                  ),
                ],
              );
            },
          );

          if (shouldDiscard == true) {
            await discardDraftAndClose();
          }
        }

        Future<void> stopVoice(StateSetter setModalState) async {
          if (!isListening && !speech.isListening) {
            debugPrint(
              '[service-order-voice] stopVoice ignored; isListening=$isListening speech.isListening=${speech.isListening}',
            );
            return;
          }
          debugPrint('[service-order-voice] stopVoice requested');
          voiceStopRequested = true;
          setModalState(() {
            voiceCaption = 'Deteniendo grabacion...';
          });
          try {
            await speech.stop();
          } catch (_) {}
          await finalizeVoiceSession(setModalState);
          voiceStopRequested = false;
        }

        Future<void> startVoice(StateSetter setModalState) async {
          debugPrint('[service-order-voice] startVoice tapped');
          FocusScope.of(modalContext).unfocus();
          textFocusNode.unfocus();
          await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
          await Future<void>.delayed(const Duration(milliseconds: 160));
          if (speech.isListening) {
            try {
              await speech.stop();
            } catch (_) {}
          }

          final hasMicrophonePermission = await ensureMicrophonePermission(
            setModalState,
          );
          debugPrint(
            '[service-order-voice] microphone permission granted=$hasMicrophonePermission',
          );
          if (!hasMicrophonePermission) {
            return;
          }

          final available = await speech.initialize(
            onStatus: (status) {
              debugPrint('[service-order-voice] onStatus=$status');
              if (!modalContext.mounted) return;
              if (status == 'done' || status == 'notListening') {
                if (voiceStopRequested) {
                  return;
                }
                if (!isListening) {
                  return;
                }
                setModalState(() {
                  isListening = false;
                  voiceCaption = voiceSessionText.trim().isNotEmpty
                      ? 'La grabacion se detuvo. Ya puedes detener y procesar o guardar.'
                      : 'La grabacion se detuvo sin texto reconocido. Intenta hablar mas cerca del microfono.';
                });
              }
            },
            onError: (error) {
              debugPrint(
                '[service-order-voice] onError errorMsg=${error.errorMsg} permanent=${error.permanent}',
              );
              if (!modalContext.mounted) return;
              voiceSessionClosed = true;
              setModalState(() {
                isListening = false;
                voiceCaption =
                    'No se pudo usar el reconocimiento de voz (${error.errorMsg}).';
              });
            },
            debugLogging: kDebugMode,
          );

          final speechHasPermission = await speech.hasPermission;
          debugPrint(
            '[service-order-voice] initialize available=$available isAvailable=${speech.isAvailable} hasPermission=$speechHasPermission',
          );
          if (!available || !speech.isAvailable || !speechHasPermission) {
            if (!modalContext.mounted) return;
            setModalState(() {
              voiceCaption =
                  'El reconocimiento de voz no esta disponible o no tiene permiso en este dispositivo.';
            });
            return;
          }

          voiceSeedText = textController.text.trim();
          voiceSessionText = '';
          voiceSessionClosed = false;
          voiceStopRequested = false;
          heardAudioDuringSession = false;

          final localeId = await resolveVoiceLocaleId();
          debugPrint('[service-order-voice] resolved localeId=$localeId');
          if (!modalContext.mounted) return;

          setModalState(() {
            isListening = true;
            voiceCaption = 'Grabando... usa detener y procesar cuando termines';
          });
          debugPrint('[service-order-voice] invoking listen');

          await speech.listen(
            localeId: localeId,
            pauseFor: const Duration(minutes: 5),
            listenFor: const Duration(minutes: 5),
            listenOptions: stt.SpeechListenOptions(
              partialResults: true,
              cancelOnError: true,
            ),
            onSoundLevelChange: (level) {
              debugPrint(
                '[service-order-voice] onSoundLevelChange level=$level',
              );
              if (!modalContext.mounted) return;
              if (level > 0) {
                heardAudioDuringSession = true;
              }
              setModalState(() {
                if (voiceSessionText.trim().isNotEmpty) {
                  voiceCaption =
                      'Grabando... audio detectado y texto reconocido';
                } else if (level > 0) {
                  voiceCaption = 'Grabando... audio detectado, sigue hablando';
                } else {
                  voiceCaption = 'Grabando... esperando audio del microfono';
                }
              });
            },
            onResult: (result) {
              debugPrint(
                '[service-order-voice] onResult final=${result.finalResult} words="${result.recognizedWords}"',
              );
              if (!modalContext.mounted) return;
              final recognized = result.recognizedWords.trim();
              if (recognized.isEmpty) {
                return;
              }

              voiceSessionText = recognized;
              setModalState(() {
                voiceCaption = result.finalResult
                    ? 'Texto reconocido. Pulsa detener y procesar.'
                    : 'Grabando... texto reconocido, sigue hablando';
              });
            },
          );
        }

        return SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SizedBox(
              height: screenHeight * 0.9,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: StatefulBuilder(
                  builder: (statefulContext, setModalState) {
                    return Form(
                      key: formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  'Escribe o dicta tu reporte',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Cerrar',
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  await requestClose();
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            voiceCaption,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: TextFormField(
                              controller: textController,
                              focusNode: textFocusNode,
                              minLines: null,
                              maxLines: null,
                              expands: true,
                              autofocus: false,
                              readOnly: isListening,
                              canRequestFocus: !isListening,
                              keyboardType: TextInputType.multiline,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                hintText: hintText,
                                alignLabelWithHint: true,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  14,
                                  16,
                                  14,
                                  16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                filled: true,
                                fillColor: colorScheme.surface,
                              ),
                              validator: (value) {
                                if ((value ?? '').trim().isEmpty) {
                                  return 'Este campo es obligatorio';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isListening
                                      ? null
                                      : () async {
                                          await startVoice(setModalState);
                                        },
                                  icon: const Icon(Icons.mic_rounded),
                                  label: const Text('Iniciar grabacion'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: !isListening
                                      ? null
                                      : () async {
                                          await stopVoice(setModalState);
                                        },
                                  icon: const Icon(Icons.stop_circle_rounded),
                                  label: const Text('Detener y procesar'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () async {
                                    await requestClose();
                                  },
                                  child: const Text('Cancelar'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    if (isListening) {
                                      await stopVoice(setModalState);
                                    }
                                    textFocusNode.unfocus();
                                    if (!modalContext.mounted) return;
                                    Navigator.pop(
                                      modalContext,
                                      textController.text.trim(),
                                    );
                                  },
                                  child: Text(confirmLabel),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 32));
    textFocusNode.dispose();
    textController.dispose();

    return result;
  }

  IconData _statusIcon(ServiceOrderStatus status) {
    switch (status) {
      case ServiceOrderStatus.pendiente:
        return Icons.schedule_send_rounded;
      case ServiceOrderStatus.enProceso:
        return Icons.play_circle_outline_rounded;
      case ServiceOrderStatus.enPausa:
        return Icons.pause_circle_outline_rounded;
      case ServiceOrderStatus.finalizado:
        return Icons.task_alt_rounded;
      case ServiceOrderStatus.pospuesta:
        return Icons.event_busy_rounded;
      case ServiceOrderStatus.cancelado:
        return Icons.cancel_outlined;
    }
  }

  _ActionTone _statusTone(ServiceOrderStatus status) {
    switch (status) {
      case ServiceOrderStatus.enProceso:
      case ServiceOrderStatus.finalizado:
        return _ActionTone.primary;
      case ServiceOrderStatus.enPausa:
      case ServiceOrderStatus.pospuesta:
        return _ActionTone.secondary;
      case ServiceOrderStatus.pendiente:
      case ServiceOrderStatus.cancelado:
        return _ActionTone.neutral;
    }
  }

  String? _formatScheduledAt(DateTime? scheduledAt) {
    if (scheduledAt == null) {
      return null;
    }
    final local = scheduledAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year} · $hour:$minute';
  }

  Future<bool> _showInstallationFinalizeWarningDialog(
    BuildContext context,
  ) async {
    var proceed = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colorScheme = theme.colorScheme;
        return AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.tertiary,
            size: 32,
          ),
          title: const Text('Antes de finalizar'),
          content: const Text(
            'Asegúrate de haber subido el reporte y las evidencias '
            '(fotos y videos) de la instalación.\n\n'
            '¿Deseas finalizar la orden de todas formas?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton.tonal(
              onPressed: () {
                proceed = true;
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Finalizar de todas formas'),
            ),
          ],
        );
      },
    );
    return proceed;
  }

  String? _validateTechnicianCommitmentBeforeFinalize() {
    final technicalEvidences = order.evidences
        .where((item) => item.type.isTechnicalEvidence)
        .toList(growable: false);
    final imageCount = technicalEvidences
        .where((item) => item.type.isImage)
        .length;
    final videoCount = technicalEvidences
        .where((item) => item.type.isVideo)
        .length;
    final hasTextEvidence = technicalEvidences.any(
      (item) => item.type.isText && item.content.trim().isNotEmpty,
    );
    final hasReportText = order.reports.any(
      (item) => item.report.trim().isNotEmpty,
    );

    final textComplete = hasTextEvidence || hasReportText;
    final imagesComplete = imageCount >= 3 && imageCount <= 5;
    final videosComplete = videoCount >= 1 && videoCount <= 2;

    if (textComplete && imagesComplete && videosComplete) {
      return null;
    }

    return 'Para finalizar esta orden debes completar el compromiso: texto obligatorio, 3 a 5 imágenes y 1 a 2 videos.';
  }
}

class _MediaTypeChip extends StatelessWidget {
  const _MediaTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.48)
                : colorScheme.outlineVariant.withValues(alpha: 0.58),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaCountPill extends StatelessWidget {
  const _MediaCountPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isLoading,
    required this.onTap,
    this.tone = _ActionTone.neutral,
    this.selected = false,
    this.minHeight = 52,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool isLoading;
  final VoidCallback? onTap;
  final _ActionTone tone;
  final bool selected;
  final double minHeight;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = onTap != null;
    final isPrimary = tone == _ActionTone.primary;
    final isSecondary = tone == _ActionTone.secondary;
    final tileColor = isPrimary
        ? const Color(0xFFF0F7FB)
        : isSecondary
        ? const Color(0xFFF8FBFD)
        : colorScheme.surface.withValues(alpha: 0.01);
    final leadingColor = isPrimary
        ? const Color(0xFF155E82)
        : isSecondary
        ? const Color(0xFF4B7E98)
        : colorScheme.primary;
    final iconContainerColor = isPrimary
        ? const Color(0xFF155E82).withValues(alpha: 0.10)
        : isSecondary
        ? const Color(0xFF4B7E98).withValues(alpha: 0.08)
        : colorScheme.primary.withValues(alpha: 0.08);
    final selectedColor = colorScheme.primary.withValues(alpha: 0.09);
    final compactPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final compactIconSize = compact ? 28.0 : 30.0;
    final compactGlyphSize = compact ? 15.0 : 16.0;
    final compactFontSize = compact ? 13.0 : 15.0;
    final compactChevronSize = compact ? 15.0 : 16.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled && !isLoading ? onTap : null,
        splashColor: leadingColor.withValues(alpha: 0.08),
        highlightColor: leadingColor.withValues(alpha: 0.05),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? selectedColor : tileColor,
              borderRadius: BorderRadius.circular(12),
              border: selected
                  ? Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.26),
                    )
                  : null,
            ),
            padding: compactPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 2.5,
                  height: minHeight - 24,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary
                        : isPrimary
                        ? const Color(0xFF155E82)
                        : isSecondary
                        ? const Color(0xFFB7D0DE)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: compactIconSize,
                  height: compactIconSize,
                  decoration: BoxDecoration(
                    color: iconContainerColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: isLoading
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(leadingColor),
                            ),
                          )
                        : Icon(
                            icon,
                            color: leadingColor,
                            size: compactGlyphSize,
                          ),
                  ),
                ),
                SizedBox(width: compact ? 8 : 9),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: compactFontSize,
                      letterSpacing: -0.1,
                      color: enabled
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                selected
                    ? Icon(
                        Icons.check_circle_rounded,
                        size: compact ? 17 : 18,
                        color: colorScheme.primary,
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        size: compactChevronSize,
                        color: leadingColor.withValues(
                          alpha: enabled ? 0.72 : 0.4,
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}
