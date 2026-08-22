import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/debug/app_error_reporter.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../core/widgets/fulltech_dialog.dart';

double? parseDominicanAmount(String raw) {
  var value = raw
      .trim()
      .replaceAll('RD\$', '')
      .replaceAll('rd\$', '')
      .replaceAll(' ', '');
  if (value.isEmpty) return null;
  if (value.startsWith('-')) return null;

  final commaCount = ','.allMatches(value).length;
  final dotCount = '.'.allMatches(value).length;
  if (commaCount > 0 && dotCount > 0) {
    value = value.replaceAll(',', '');
  } else if (commaCount > 0) {
    final parts = value.split(',');
    final last = parts.last;
    final allGroupsAreThousands =
        parts.length > 1 &&
        parts.skip(1).every((part) => RegExp(r'^\d{3}$').hasMatch(part));
    if (allGroupsAreThousands || last.length == 3) {
      value = value.replaceAll(',', '');
    } else if (commaCount == 1 && last.length <= 2) {
      value = value.replaceAll(',', '.');
    } else {
      return null;
    }
  } else if (dotCount > 1) {
    final parts = value.split('.');
    final allGroupsAreThousands =
        parts.length > 1 &&
        parts.skip(1).every((part) => RegExp(r'^\d{3}$').hasMatch(part));
    if (!allGroupsAreThousands) return null;
    value = value.replaceAll('.', '');
  }
  final parsed = double.tryParse(value);
  if (parsed == null || parsed < 0 || parsed.isNaN || parsed.isInfinite) {
    return null;
  }
  return double.parse(parsed.toStringAsFixed(2));
}

String resolveCashError(Object error) {
  final text = error.toString().replaceFirst('Exception: ', '').trim();
  if (text.isEmpty) return 'No se pudo completar la operación de caja.';
  return text;
}

OverlayEntry? _cashToastEntry;

/// Notificación flotante en la esquina superior derecha, con el mismo patrón
/// que las demás notificaciones superiores de FULLPOS. Se inserta en el overlay
/// raíz para quedar por encima de drawers/paneles, auto-cierra y no bloquea la
/// interacción.
void showCashToast(
  BuildContext context,
  String message, {
  bool isError = false,
  String? detail,
  OverlayState? overlay,
}) {
  if (!context.mounted) return;
  // `Overlay.maybeOf(..., rootOverlay: true)` solo busca ancestros. Cuando el
  // contexto es el del Navigator raíz (cuyo propio Overlay es un descendiente),
  // se puede pasar el overlay capturado previamente para que el toast se
  // muestre igualmente por encima de drawers/paneles.
  final targetOverlay = overlay ?? Overlay.maybeOf(context, rootOverlay: true);
  if (targetOverlay == null) return;

  // Reemplazar un toast anterior aún visible (su State cancela su timer al
  // desmontarse).
  _cashToastEntry?.remove();
  _cashToastEntry = null;

  final topPadding = MediaQuery.viewPaddingOf(context).top + 14;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) {
      return Positioned(
        top: topPadding,
        right: 18,
        child: _CashTopToast(
          title: message,
          message: detail,
          isError: isError,
          onClose: () {
            entry.remove();
            if (_cashToastEntry == entry) _cashToastEntry = null;
          },
        ),
      );
    },
  );
  _cashToastEntry = entry;
  targetOverlay.insert(entry);
}

class _CashTopToast extends StatefulWidget {
  const _CashTopToast({
    required this.title,
    required this.message,
    required this.isError,
    required this.onClose,
  });

  final String title;
  final String? message;
  final bool isError;
  final VoidCallback onClose;

  @override
  State<_CashTopToast> createState() => _CashTopToastState();
}

class _CashTopToastState extends State<_CashTopToast> {
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _autoCloseTimer =
        Timer(const Duration(milliseconds: 3200), widget.onClose);
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isError
        ? const Color(0xFFB42318)
        : const Color(0xFF059669);
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, minWidth: 300),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.38)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 3, color: accent),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.isError
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          color: accent,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              maxLines: widget.message == null ? 3 : 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            if (widget.message != null &&
                                widget.message!.trim().isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                widget.message!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: const Color(0xFF94A3B8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
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

Future<bool?> showOpenCashDialog(
  BuildContext context, {
  required Future<void> Function(double openingAmount) onOpenShift,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: FullTechDialogTokens.overlayColor,
    builder: (_) => _OpenCashDialog(onOpenShift: onOpenShift),
  );
}

Future<double?> showCashAmountDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String hint = '0.00',
}) {
  final controller = TextEditingController(text: hint);

  return FullTechFormDialog.show<double>(
    context,
    title: title,
    subtitle: 'Ingresa el monto para continuar',
    confirmText: actionLabel,
    cancelText: 'Cancelar',
    maxWidth: FullTechDialogTokens.maxWidthSmall,
    showCloseButton: false,
    content: FullTechDialogField(
      label: 'Monto',
      hintText: '0.00',
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      prefixIcon: const Padding(
        padding: EdgeInsets.only(left: 16, right: 8),
        child: Text(
          r'RD$ ',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: FullTechDialogTokens.titleColor,
          ),
        ),
      ),
    ),
    onCancel: () => Navigator.of(context).pop(),
    onConfirm: () {
      final value = parseDominicanAmount(controller.text);
      Navigator.of(context).pop(value);
    },
  ).whenComplete(() => controller.dispose());
}

class CloseShiftResult {
  const CloseShiftResult._({required this.success, this.printResult});

  final bool success;
  final PrintTicketResult? printResult;

  factory CloseShiftResult.success(PrintTicketResult? printResult) {
    return CloseShiftResult._(success: true, printResult: printResult);
  }
}

Future<CloseShiftResult?> showCloseShiftDialog(
  BuildContext context, {
  required double expectedCash,
  required Future<PrintTicketResult?> Function(double countedAmount)
  onCloseShift,
}) {
  return showDialog<CloseShiftResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: FullTechDialogTokens.overlayColor,
    builder: (_) => CloseShiftDialog(
      expectedCash: expectedCash,
      onCloseShift: onCloseShift,
    ),
  );
}

class CloseShiftDialog extends StatefulWidget {
  const CloseShiftDialog({
    super.key,
    required this.expectedCash,
    required this.onCloseShift,
  });

  final double expectedCash;
  final Future<PrintTicketResult?> Function(double countedAmount) onCloseShift;

  @override
  State<CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<CloseShiftDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final FocusNode _amountFocusNode;
  bool _isSubmitting = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    debugPrint('[CloseShiftDialog] initState');
    _amountController = TextEditingController(
      text: widget.expectedCash.toStringAsFixed(2),
    );
    _amountFocusNode = FocusNode();
  }

  @override
  void dispose() {
    debugPrint('[CloseShiftDialog] dispose');
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    debugPrint('[CloseShiftDialog] submit start');
    FocusManager.instance.primaryFocus?.unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final countedAmount = parseDominicanAmount(_amountController.text)!;
    debugPrint('[CloseShiftDialog] amount=$countedAmount');
    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    try {
      debugPrint('[CloseShiftDialog] request start');
      final printResult = await widget.onCloseShift(countedAmount);
      debugPrint('[CloseShiftDialog] request success');
      if (!mounted) return;
      debugPrint('[CloseShiftDialog] pop');
      Navigator.of(
        context,
        rootNavigator: true,
      ).pop(CloseShiftResult.success(printResult));
    } catch (error, stack) {
      if (!mounted) return;
      setState(() => _inlineError = resolveCashError(error));
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Cerrar turno',
        notifyUser: false,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _dismiss() {
    if (_isSubmitting) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSubmitting,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): _submit,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
          const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFBFDBFE),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 32,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cerrar turno',
                                  style: TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 21,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'Ingresa el efectivo contado para hacer el corte.',
                                  style: TextStyle(
                                    color: Color(0xFF52667C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: _isSubmitting ? null : _dismiss,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      const SizedBox(height: 24),
                      const Text(
                        'Efectivo contado',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amountController,
                        focusNode: _amountFocusNode,
                        autofocus: true,
                        enabled: !_isSubmitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        validator: (value) {
                          final amount = parseDominicanAmount(value ?? '');
                          if (amount == null) {
                            return 'Ingresa un monto válido. Ej: RD\$ 1,200.00';
                          }
                          return null;
                        },
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: InputDecoration(
                          errorText: _inlineError,
                          prefixIcon: Container(
                            width: 64,
                            alignment: Alignment.center,
                            margin: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF1FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              r'RD$',
                              style: TextStyle(
                                color: Color(0xFF1957E6),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          hintText: '0.00',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                              width: 1.4,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                              width: 1.4,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                              width: 1.8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isSubmitting ? null : _dismiss,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isSubmitting ? null : _submit,
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.lock_rounded, size: 18),
                              label: Text(
                                _isSubmitting ? 'Cerrando...' : 'Cerrar turno',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _isSubmitting
                            ? 'Procesando cierre e impresión...'
                            : 'Enter para cerrar · Esc para cancelar',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenCashDialog extends StatefulWidget {
  const _OpenCashDialog({required this.onOpenShift});

  final Future<void> Function(double openingAmount) onOpenShift;

  @override
  State<_OpenCashDialog> createState() => _OpenCashDialogState();
}

class _OpenCashDialogState extends State<_OpenCashDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final FocusNode _amountFocusNode;
  bool _isSubmitting = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    debugPrint('[OpenShiftDialog] initState');
    _amountController = TextEditingController(text: '0.00');
    _amountFocusNode = FocusNode();
  }

  @override
  void dispose() {
    debugPrint('[OpenShiftDialog] dispose');
    _amountController.dispose();
    _amountFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    debugPrint('[OpenShiftDialog] submit start');
    FocusManager.instance.primaryFocus?.unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final openingAmount = parseDominicanAmount(_amountController.text)!;
    setState(() {
      _isSubmitting = true;
      _inlineError = null;
    });

    try {
      debugPrint('[OpenShiftDialog] API request');
      await widget.onOpenShift(openingAmount);
      debugPrint('[OpenShiftDialog] API success');
      if (!mounted) return;
      debugPrint('[OpenShiftDialog] pop');
      Navigator.of(context).pop(true);
    } catch (error, stack) {
      if (!mounted) return;
      setState(() => _inlineError = resolveCashError(error));
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Abrir turno',
        notifyUser: false,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Abrir caja',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Registra el fondo inicial para comenzar a trabajar.',
                style: TextStyle(
                  color: Color(0xFF52667C),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),
              const SizedBox(height: 24),
              const Text(
                'Fondo inicial',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  autofocus: true,
                  enabled: !_isSubmitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    final amount = parseDominicanAmount(value ?? '');
                    if (amount == null || amount < 0) {
                      return 'Ingresa un fondo inicial válido';
                    }
                    return null;
                  },
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    errorText: _inlineError,
                    prefixIcon: Container(
                      width: 64,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        r'RD$',
                        style: TextStyle(
                          color: Color(0xFF1957E6),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    hintText: '0.00',
                    hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w800,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.4,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.4,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.8,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _submit,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_open_rounded, size: 18),
                label: Text(_isSubmitting ? 'Abriendo...' : 'Abrir caja'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CashMovementInput {
  const CashMovementInput({
    required this.amount,
    required this.reason,
    required this.movementType,
    required this.affectsProfit,
  });

  final double amount;
  final String reason;
  final String movementType;
  final bool affectsProfit;
}

Future<CashMovementInput?> showCashMovementDialog(
  BuildContext context, {
  required String type,
}) {
  final isOut = type == 'OUT';
  return showGeneralDialog<CashMovementInput>(
    context: context,
    barrierDismissible: false,
    barrierLabel: isOut ? 'Registrar salida' : 'Registrar ingreso',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
            ),
          ),
          Center(child: _CashMovementDialog(type: type)),
        ],
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
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _CashMovementDialog extends StatefulWidget {
  const _CashMovementDialog({required this.type});

  final String type;

  @override
  State<_CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<_CashMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _reasonController;
  late final FocusNode _amountFocusNode;
  late final FocusNode _reasonFocusNode;
  bool _isSubmitting = false;

  bool get _isOut => widget.type == 'OUT';

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _reasonController = TextEditingController();
    _amountFocusNode = FocusNode();
    _reasonFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    _amountFocusNode.dispose();
    _reasonFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);
    final amount = parseDominicanAmount(_amountController.text)!;
    final typedReason = _reasonController.text.trim();
    final reason = typedReason.isEmpty
        ? (_isOut ? 'Salida de efectivo' : 'Ingreso de efectivo')
        : typedReason;
    Navigator.of(context).pop(
      CashMovementInput(
        amount: amount,
        reason: reason,
        movementType: _isOut ? 'expense' : 'transfer',
        affectsProfit: _isOut,
      ),
    );
  }

  void _dismiss() {
    if (_isSubmitting) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final color = _isOut ? const Color(0xFFDC2626) : const Color(0xFF1957E6);
    final softColor = _isOut
        ? const Color(0xFFFFEEF0)
        : const Color(0xFFEAF1FF);
    final title = _isOut ? 'Registrar salida' : 'Registrar ingreso';
    final subtitle = _isOut
        ? 'Registra una salida manual de efectivo'
        : 'Registra un ingreso manual de efectivo';
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 24, 20, 18),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    subtitle,
                                    style: const TextStyle(
                                      color: Color(0xFF52667C),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar',
                              onPressed: _isSubmitting ? null : _dismiss,
                              icon: const Icon(Icons.close_rounded),
                              color: const Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFE2E8F0)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                        child: TextFormField(
                          controller: _amountController,
                          focusNode: _amountFocusNode,
                          autofocus: true,
                          enabled: !_isSubmitting,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _reasonFocusNode.requestFocus(),
                          validator: (value) {
                            final amount = parseDominicanAmount(value ?? '');
                            if (amount == null || amount <= 0) {
                              return 'Ingresa un monto válido mayor que cero';
                            }
                            return null;
                          },
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: _cashMovementInputDecoration(
                            'Monto',
                            prefixIcon: Container(
                              width: 64,
                              alignment: Alignment.center,
                              margin: const EdgeInsets.fromLTRB(0, 0, 10, 0),
                              decoration: BoxDecoration(
                                color: softColor,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(11),
                                  bottomLeft: Radius.circular(11),
                                ),
                                border: const Border(
                                  right: BorderSide(color: Color(0xFFE2E8F0)),
                                ),
                              ),
                              child: Text(
                                r'RD$',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: TextFormField(
                          controller: _reasonController,
                          focusNode: _reasonFocusNode,
                          enabled: !_isSubmitting,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: _cashMovementInputDecoration(
                            'Motivo (opcional)',
                            hint: _isOut
                                ? 'Ej: Pago de proveedor, gastos...'
                                : 'Ej: Cambio adicional, ajuste...',
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 26, 28, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isSubmitting ? null : _dismiss,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF1F2937),
                                  minimumSize: const Size.fromHeight(44),
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _isSubmitting ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: color,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(44),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                child: Text(
                                  _isOut
                                      ? 'Registrar salida'
                                      : 'Registrar ingreso',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          'Enter para guardar · Esc para cerrar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(
                              0xFF64748B,
                            ).withValues(alpha: 0.84),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _cashMovementInputDecoration(
  String label, {
  String? hint,
  Widget? prefixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    prefixIconConstraints: const BoxConstraints(minWidth: 64, minHeight: 48),
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    labelStyle: const TextStyle(
      color: Color(0xFF52667C),
      fontWeight: FontWeight.w700,
    ),
    hintStyle: const TextStyle(
      color: Color(0xFF94A3B8),
      fontWeight: FontWeight.w600,
    ),
    errorStyle: const TextStyle(fontWeight: FontWeight.w700),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
    ),
  );
}
