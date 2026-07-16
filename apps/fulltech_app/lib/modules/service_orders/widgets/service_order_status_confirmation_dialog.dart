import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/fulltech_dialog.dart';
import '../service_order_models.dart';

Future<bool> showServiceOrderStatusConfirmationDialog({
  required BuildContext context,
  required ServiceOrderStatus status,
  DateTime? initialScheduledAt,
  required Future<void> Function(DateTime? scheduledAt) onConfirm,
}) async {
  final requiresScheduledAt = status == ServiceOrderStatus.pospuesta;
  final needsDialog = requiresScheduledAt || status.requiresUpdateConfirmation;

  if (!needsDialog) {
    await onConfirm(null);
    return true;
  }

  Object? actionError;
  StackTrace? actionStackTrace;
  var confirmed = false;
  var selectedScheduledAt = _resolveInitialScheduledAt(
    initialScheduledAt,
    requiresScheduledAt: requiresScheduledAt,
  );

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var isSubmitting = false;
      String? validationMessage;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickScheduledAt() async {
            final now = DateTime.now();
            final initial =
                selectedScheduledAt ?? now.add(const Duration(hours: 1));

            final pickedDate = await showDatePicker(
              context: dialogContext,
              initialDate: initial,
              firstDate: DateTime(now.year, now.month, now.day),
              lastDate: DateTime(now.year + 2),
            );
            if (pickedDate == null || !dialogContext.mounted) {
              return;
            }

            final pickedTime = await showTimePicker(
              context: dialogContext,
              initialTime: TimeOfDay.fromDateTime(initial),
            );
            if (pickedTime == null || !dialogContext.mounted) {
              return;
            }

            setState(() {
              selectedScheduledAt = DateTime(
                pickedDate.year,
                pickedDate.month,
                pickedDate.day,
                pickedTime.hour,
                pickedTime.minute,
              );
              validationMessage = null;
            });
          }

          Future<void> handleConfirm() async {
            if (isSubmitting) {
              return;
            }

            if (requiresScheduledAt) {
              final scheduledAt = selectedScheduledAt;
              if (scheduledAt == null) {
                setState(() {
                  validationMessage = 'Selecciona la nueva fecha y hora.';
                });
                return;
              }

              if (!scheduledAt.isAfter(DateTime.now())) {
                setState(() {
                  validationMessage =
                      'La nueva fecha debe ser posterior a la actual.';
                });
                return;
              }
            }

            setState(() {
              isSubmitting = true;
              validationMessage = null;
            });

            try {
              await onConfirm(selectedScheduledAt);
              confirmed = true;
            } catch (error, stackTrace) {
              actionError = error;
              actionStackTrace = stackTrace;
            } finally {
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            }
          }

          return PopScope(
            canPop: !isSubmitting,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): handleConfirm,
                const SingleActivator(LogicalKeyboardKey.numpadEnter):
                    handleConfirm,
              },
              child: Focus(
                autofocus: true,
                child: FullTechDialog(
                  title: requiresScheduledAt
                      ? 'Reprogramar orden'
                      : 'Aplicar cambio',
                  maxWidth: FullTechDialogTokens.maxWidthSmall,
                  actions: [
                    DialogSecondaryButton(
                      label: 'Cancelar',
                      onPressed: isSubmitting
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                    ),
                    if (requiresScheduledAt)
                      OutlinedButton.icon(
                        onPressed: isSubmitting ? null : pickScheduledAt,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: const Text('Cambiar fecha'),
                      ),
                    DialogPrimaryButton(
                      label: requiresScheduledAt
                          ? 'Guardar fecha'
                          : 'Guardar cambio',
                      onPressed: isSubmitting ? null : handleConfirm,
                      isLoading: isSubmitting,
                    ),
                  ],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requiresScheduledAt
                            ? 'Marca la nueva fecha de esta orden pospuesta y presiona Enter para guardar.'
                            : '¿Estás seguro de que deseas marcar esta orden como ${status.confirmationLabel}?',
                      ),
                      if (requiresScheduledAt) ...[
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: isSubmitting ? null : pickScheduledAt,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Nueva fecha y hora',
                              border: const OutlineInputBorder(),
                              errorText: validationMessage,
                              suffixIcon: const Icon(
                                Icons.edit_calendar_outlined,
                              ),
                            ),
                            child: Text(
                              selectedScheduledAt == null
                                  ? 'Seleccionar fecha'
                                  : DateFormat(
                                      'dd/MM/yyyy h:mm a',
                                      'es_DO',
                                    ).format(selectedScheduledAt!.toLocal()),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Debes elegir una fecha futura.',
                          style: Theme.of(dialogContext).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  dialogContext,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  if (actionError != null && actionStackTrace != null) {
    Error.throwWithStackTrace(actionError!, actionStackTrace!);
  }

  return confirmed;
}

DateTime? _resolveInitialScheduledAt(
  DateTime? initialScheduledAt, {
  required bool requiresScheduledAt,
}) {
  if (!requiresScheduledAt) {
    return initialScheduledAt;
  }

  final now = DateTime.now();
  final candidate = initialScheduledAt?.isAfter(now) == true
      ? initialScheduledAt!
      : now.add(const Duration(hours: 1));

  return DateTime(
    candidate.year,
    candidate.month,
    candidate.day,
    candidate.hour,
    candidate.minute,
  );
}
