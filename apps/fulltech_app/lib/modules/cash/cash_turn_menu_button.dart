import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide GestureDetector;
import 'package:daleventa_pos/core/widgets/app_gesture_detector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/debug/app_error_reporter.dart';
import '../../core/debug/trace_log.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/refined_topbar_controls.dart';
import '../../core/time/business_time.dart';
import '../../core/utils/money_formatters.dart';
import 'cash_close_ticket_printer.dart';
import 'cash_dialogs.dart';
import 'cash_models.dart';
import 'cash_providers.dart';
import 'cash_repository.dart';

class CashTurnMenuButton extends ConsumerWidget {
  const CashTurnMenuButton({
    super.key,
    this.compact = false,
    this.refined = false,
  });

  final bool refined;

  static const _navigatorSettleDelay = Duration(milliseconds: 220);

  /// Copy única para el estado válido "sin turno abierto" (no es un error).
  static const _noOpenTurnMessage = 'No tienes un turno abierto actualmente.';

  final bool compact;

  void _runAfterNavigatorSettles(
    BuildContext context,
    Future<void> Function() action,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        Future<void>.delayed(_navigatorSettleDelay).then((_) async {
          if (!context.mounted) return;
          await action();
        }),
      );
    });
  }

  Future<void> _openCash(BuildContext context, WidgetRef ref) async {
    try {
      final opened = await showOpenCashDialog(
        context,
        onOpenShift: (amount) async {
          // Releer el notifier en el punto de uso: el provider puede haberse
          // recreado mientras el diálogo estuvo abierto, y usar una referencia
          // vieja lanzaría 'Tried to use ActiveCashSessionController after
          // dispose was called'.
          final controller = ref.read(
            activeCashSessionControllerProvider.notifier,
          );
          await controller.open(amount);
        },
      );
      if (!context.mounted) return;
      if (opened == true) {
        final controller = ref.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        if (!context.mounted) return;
        // El aviso de éxito solo se da si el estado autoritativo confirma el
        // turno: nunca se anuncia "Caja abierta" mientras el selector sigue en
        // "Cerrado".
        if (ref.read(activeCashSessionControllerProvider).valueOrNull == null) {
          showCashToast(
            context,
            'La caja no quedó abierta en el servidor. Intenta de nuevo.',
            isError: true,
          );
          return;
        }
        showCashToast(
          context,
          'Turno abierto',
          detail: 'La caja está lista para operar.',
        );
      }
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Abrir caja desde menu de turno',
        notifyUser: false,
      );
      if (!context.mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  Future<void> _closeCash(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(cashRepositoryProvider);
    try {
      final summary = await repository.summary();
      if (!context.mounted) return;
      final result = await showCloseShiftDialog(
        context,
        expectedCash: summary.expectedCash,
        onCloseShift: (amount) {
          final controller = ref.read(
            activeCashSessionControllerProvider.notifier,
          );
          return controller.close(amount);
        },
      );
      if (!context.mounted) return;
      if (result?.success != true) return;
      final controller = ref.read(activeCashSessionControllerProvider.notifier);
      await controller.refresh();
      if (!context.mounted) return;
      final printResult = result?.printResult;
      // Título corto + detalle útil: el resultado de impresión no expone
      // detalles técnicos, solo el desenlace para el cajero.
      final detail = printResult == null
          ? 'Efectivo contado y cierre registrado correctamente.'
          : printResult.success
          ? 'Cierre registrado y ticket enviado a la impresora.'
          : 'Cierre registrado. ${printResult.message}';
      showCashToast(context, 'Turno cerrado', detail: detail);
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Cerrar caja desde menu de turno',
        notifyUser: false,
      );
      if (!context.mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  /// Registra una entrada o salida manual de efectivo desde el selector.
  ///
  /// Reutiliza EXACTAMENTE la misma implementación que la pantalla de Caja y el
  /// historial de movimientos: `showCashMovementDialog` (un único formulario) y
  /// `ActiveCashSessionController.addMovement` (un único camino al endpoint
  /// `POST /cash/movements`, con su `operationId`, `sessionId`, cola offline y
  /// validaciones intactas). No hay formulario ni endpoint alternativo.
  Future<void> _addMovement(
    BuildContext context,
    WidgetRef ref,
    String type,
  ) async {
    final controller = ref.read(activeCashSessionControllerProvider.notifier);
    // El backend rechaza un movimiento sin turno abierto. La acción se muestra
    // siempre en el selector, pero sin turno no se abre un formulario que no
    // puede guardarse: se informa con el mensaje normal de estado.
    final active = ref.read(activeCashSessionControllerProvider).valueOrNull;
    if (active == null) {
      showCashToast(context, _noOpenTurnMessage);
      return;
    }
    final input = await showCashMovementDialog(context, type: type);
    if (input == null) return;
    try {
      await controller.addMovement(
        type: type,
        amount: input.amount,
        reason: input.reason,
        movementType: input.movementType,
        affectsProfit: input.affectsProfit,
      );
      if (!context.mounted) return;
      showCashToast(context, 'Movimiento guardado');
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Registrar movimiento desde menu de turno',
        notifyUser: false,
      );
      if (!context.mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  Future<void> _showCurrentTurn(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(cashRepositoryProvider);
    try {
      var active = ref.read(activeCashSessionControllerProvider).valueOrNull;
      if (active == null) {
        // Estado válido y esperado: NO hay turno abierto.
        //
        // Se revalida contra el backend (el snapshot local pudo quedar
        // desactualizado) y se informa con UI normal. Nunca se pide el corte de
        // un turno inexistente: `GET /cash/summary` exige turno abierto y
        // responde 404, que antes se propagaba como error no capturado.
        await ref
            .read(activeCashSessionControllerProvider.notifier)
            .refresh(silent: true);
        if (!context.mounted) return;
        active = ref.read(activeCashSessionControllerProvider).valueOrNull;
        if (active == null) {
          showCashToast(context, _noOpenTurnMessage);
          return;
        }
      }
      final unverified = ref.read(cashStateUnverifiedProvider);
      final summary = unverified
          ? (await repository.cachedSummary()) ?? await repository.summary()
          : await repository.summary();
      if (!context.mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => _CurrentTurnDialog(
          active: active,
          summary: summary,
          unverified: unverified,
          onCloseTurn: () {
            Navigator.of(dialogContext).pop('close');
          },
          onOpenHistory: () {
            Navigator.of(dialogContext).pop('history');
          },
        ),
      );

      if (!context.mounted) return;
      if (action == 'close') {
        _runAfterNavigatorSettles(context, () => _closeCash(context, ref));
      } else if (action == 'history') {
        _runAfterNavigatorSettles(context, () => _showHistory(context, ref));
      }
    } catch (error, stack) {
      // Acción recuperable: el error se comunica en la UI de caja y NUNCA se
      // escala al sistema global de errores (que mostraría el banner general).
      if (isCashNoOpenSessionError(error)) {
        // Carrera con caché/otro dispositivo: el servidor confirma que no hay
        // turno abierto. Converger el estado local y avisar sin lenguaje de
        // error técnico.
        TraceLog.log('cash', 'cash.turn_view.no_open_session');
        if (!context.mounted) return;
        await ref
            .read(activeCashSessionControllerProvider.notifier)
            .refresh(silent: true);
        if (!context.mounted) return;
        showCashToast(context, _noOpenTurnMessage);
        return;
      }
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Ver turno actual desde menu de turno',
        notifyUser: false,
      );
      if (!context.mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
    }
  }

  Future<void> _showHistory(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(cashRepositoryProvider);
    final printer = ref.read(cashCloseTicketPrinterProvider);
    final List<CashSessionHistoryModel> rows;
    try {
      rows = await repository.closedSessions();
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Ver historial de turnos desde menu de turno',
        notifyUser: false,
      );
      if (!context.mounted) return;
      showCashToast(context, resolveCashError(error), isError: true);
      return;
    }
    if (!context.mounted) return;
    final rootContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _TurnHistoryDialog(
        rows: rows,
        onPrint: (row) async {
          final result = await printer.printHistoryTicket(row);
          if (!rootContext.mounted) return;
          showCashToast(
            rootContext,
            result.success
                ? 'Ticket de cierre impreso'
                : 'No se pudo imprimir: ${result.message}',
            isError: !result.success,
          );
        },
      ),
    );
  }

  void _activateMenuItem(
    BuildContext rootContext,
    BuildContext menuContext,
    Future<void> Function() action,
  ) {
    Navigator.of(menuContext).pop();
    _runAfterNavigatorSettles(rootContext, action);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activeCashSessionControllerProvider);
    final active = session.valueOrNull;
    final unverified = ref.watch(cashStateUnverifiedProvider);
    final requiresReview = ref.watch(cashStateRequiresReviewProvider);
    final reviewMessage = ref.watch(cashStateReviewMessageProvider);

    return PopupMenuButton<String>(
      tooltip: 'Estado del turno',
      offset: const Offset(0, 42),
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: const Color(0xFF0F172A).withValues(alpha: 0.10),
      constraints: const BoxConstraints(minWidth: 292),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (menuContext) => [
        if (requiresReview)
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _TurnMenuNotice(
              icon: Icons.report_gmailerrorred_rounded,
              label: 'Requiere revisión de caja',
              helpText:
                  reviewMessage ??
                  'El servidor detectó un estado de turno que necesita '
                      'revisión. No abras una caja nueva hasta resolverlo.',
            ),
          )
        else if (unverified)
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: const _TurnMenuNotice(
              icon: Icons.cloud_off_rounded,
              label: 'Estado no sincronizado',
              helpText:
                  'Sin conexión: el estado del turno no está confirmado con '
                  'el servidor y se actualizará al recuperar conexión.',
            ),
          ),
        // ─────────────────── TURNO ABIERTO (5 opciones) ───────────────────
        // Orden fijo del contrato: 1) Cerrar turno  2) Turno actual
        // 3) Registrar entrada  4) Registrar salida  5) Historial de caja.
        if (active != null && !requiresReview) ...[
          // 1. Cierre DIRECTO: abre el diálogo de corte existente
          //    (`showCloseShiftDialog`) sin pasar antes por "Turno actual".
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 44,
            child: _TurnMenuItem(
              icon: Icons.price_check_rounded,
              tone: AppColors.primary,
              emphasized: true,
              highlight: true,
              label: 'Cerrar turno',
              helpText:
                  'Abre el corte del turno activo y pide el efectivo contado. Es el mismo cierre de siempre: registra el corte y emite el ticket según la configuración de impresión.',
              onTap: () => _activateMenuItem(
                context,
                menuContext,
                () => _closeCash(context, ref),
              ),
            ),
          ),
          // 2. Detalle informativo del turno en curso.
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 44,
            child: _TurnMenuItem(
              icon: Icons.point_of_sale_rounded,
              tone: AppColors.primary,
              emphasized: true,
              label: 'Turno actual',
              helpText:
                  'Muestra el resumen del turno activo, total vendido, efectivo esperado, tickets y composición del corte sin salir de la pantalla de ventas.',
              onTap: () => _activateMenuItem(context, menuContext, () async {
                await _showCurrentTurn(context, ref);
              }),
            ),
          ),
          // Separador: bloque primario → operaciones de efectivo.
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 7,
            child: _TurnMenuDivider(width: _turnMenuRowWidth(menuContext)),
          ),
          // 3./4. Movimientos manuales: solo con turno abierto confirmado. Sin
          // turno el backend rechaza el movimiento, así que la opción no se
          // ofrece (el bloqueo real sigue en el backend).
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 44,
            child: _TurnMenuItem(
              icon: Icons.south_west_rounded,
              tone: AppColors.success,
              label: 'Registrar entrada',
              helpText:
                  'Registra efectivo que entra a la caja fuera de una venta (fondo adicional, reposición, cobro no facturado).',
              onTap: () => _activateMenuItem(
                context,
                menuContext,
                () => _addMovement(context, ref, 'IN'),
              ),
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 44,
            child: _TurnMenuItem(
              icon: Icons.north_east_rounded,
              tone: AppColors.error,
              label: 'Registrar salida',
              helpText:
                  'Registra efectivo que sale de la caja (gasto, retiro del dueño o transferencia). No permite dejar la caja en negativo.',
              onTap: () => _activateMenuItem(
                context,
                menuContext,
                () => _addMovement(context, ref, 'OUT'),
              ),
            ),
          ),
          // Separador: operaciones de efectivo → consultas.
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 7,
            child: _TurnMenuDivider(width: _turnMenuRowWidth(menuContext)),
          ),
        ],
        // ─────────────────── TURNO CERRADO (2 opciones) ───────────────────
        // Contrato: exactamente "Abrir turno" y "Historial de caja". No se
        // muestran "Turno actual", entradas/salidas ni cierre.
        //
        // Abrir otra caja mientras el estado del servidor no está confirmado
        // podría crear un segundo turno sobre un estado ambiguo/legacy.
        if (active == null && !unverified && !requiresReview)
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 44,
            child: _TurnMenuItem(
              icon: Icons.lock_open_rounded,
              emphasized: true,
              highlight: true,
              label: 'Abrir turno',
              helpText:
                  'Inicia un turno de caja registrando el fondo inicial de efectivo. Habilita ventas, entradas, salidas y cierre del día.',
              onTap: () => _activateMenuItem(
                context,
                menuContext,
                () => _openCash(context, ref),
              ),
            ),
          ),
        // 5. Historial de caja: disponible siempre (también sin turno abierto).
        // Turnos cerrados y movimientos en un solo panel con selector interno.
        if (!requiresReview)
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 44,
            child: _TurnMenuItem(
              icon: Icons.history_rounded,
              tone: AppColors.textSecondary,
              emphasized: true,
              label: 'Historial de caja',
              helpText:
                  'Consulta los turnos cerrados y los movimientos de efectivo en un solo lugar. Cambia entre ambas vistas con el selector del panel. Solo lectura.',
              onTap: () => _activateMenuItem(
                context,
                menuContext,
                () => _showHistory(context, ref),
              ),
            ),
          ),
      ],
      child: _TurnTopbarButton(
        open: active != null,
        unverified: unverified,
        compact: compact,
        refined: refined,
      ),
    );
  }
}

class _TurnTopbarButton extends StatefulWidget {
  const _TurnTopbarButton({
    required this.open,
    required this.unverified,
    required this.compact,
    required this.refined,
  });

  final bool open;
  final bool unverified;
  final bool compact;
  final bool refined;

  @override
  State<_TurnTopbarButton> createState() => _TurnTopbarButtonState();
}

class _TurnTopbarButtonState extends State<_TurnTopbarButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final CurvedAnimation _pulse;
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    final open = widget.open;
    if (widget.refined) {
      return RefinedTurnChip(
        open: open,
        unverified: widget.unverified,
        activity: open
            ? _TurnLiveDot(animation: _pulse, compact: true)
            : const _TurnClosedDot(
                color: AppColors.textSecondary,
                background: AppColors.surfaceAlt,
                compact: true,
              ),
      );
    }
    final accent = open ? const Color(0xFF1957E6) : const Color(0xFF64748B);
    final accentSoft = open ? const Color(0xFFE4F8FF) : const Color(0xFFF1F5F9);
    final borderColor = open
        ? const Color(0xFF9FB6C8)
        : const Color(0xFF9FB6C8);
    final label = open ? 'Abierto' : 'Cerrado';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerCancel: (_) => setState(() => _pressed = false),
        onPointerUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.012 : 1),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 36,
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 8 : 9,
              4,
              widget.compact ? 8 : 9,
              4,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE4F8FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active ? const Color(0xFF8EDBFF) : borderColor,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF0D5EA6,
                  ).withValues(alpha: active ? 0.12 : 0.055),
                  blurRadius: active ? 16 : 10,
                  spreadRadius: -5,
                  offset: Offset(0, active ? 7 : 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!widget.compact) ...[
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Turno',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w700,
                          fontSize: 9.5,
                          height: 1,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (open)
                            _TurnLiveDot(animation: _pulse, compact: true)
                          else
                            _TurnClosedDot(
                              color: accent,
                              background: accentSoft,
                              compact: true,
                            ),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: open ? const Color(0xFF0D5EA6) : accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              height: 1,
                              letterSpacing: 0,
                            ),
                          ),
                          if (widget.unverified) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 13,
                              color: const Color(0xFFF59E0B),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ] else ...[
                  if (open)
                    _TurnLiveDot(animation: _pulse)
                  else
                    _TurnClosedDot(color: accent, background: accentSoft),
                ],
                const SizedBox(width: 5),
                AnimatedRotation(
                  turns: _pressed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF0D5EA6),
                    size: 18,
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

class _TurnLiveDot extends StatelessWidget {
  const _TurnLiveDot({required this.animation, this.compact = false});

  final Animation<double> animation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final boxSize = compact ? 8.0 : 18.0;
    final dotSize = compact ? 6.0 : 8.0;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return SizedBox(
          width: boxSize,
          height: boxSize,
          child: Center(
            child: Transform.scale(
              scale: 0.78 + (t * 0.34),
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF1957E6),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF1957E6,
                      ).withValues(alpha: 0.18 + (0.12 * t)),
                      blurRadius: compact ? 5 : 8,
                      spreadRadius: compact ? 0 : 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TurnClosedDot extends StatelessWidget {
  const _TurnClosedDot({
    required this.color,
    required this.background,
    this.compact = false,
  });

  final Color color;
  final Color background;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final boxSize = compact ? 8.0 : 18.0;
    final dotSize = compact ? 6.0 : 7.0;
    return Container(
      width: boxSize,
      height: boxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: compact ? Colors.transparent : background,
        shape: BoxShape.circle,
      ),
      child: Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Ancho de las filas del menú «Turno».
///
/// En escritorio apunta a ~332 px para que «Historial de movimientos» se lea
/// completo sin elipsis (icono 36 + hueco 12 + texto + ayuda 32 + chevron 18 +
/// padding). En pantallas estrechas se acota al ancho disponible menos los
/// márgenes del popup, de modo que nunca haya recorte ni overflow horizontal.
double _turnMenuRowWidth(BuildContext context) {
  final screenWidth = MediaQuery.sizeOf(context).width;
  return math.min(332.0, math.max(232.0, screenWidth - 56.0));
}

class _TurnMenuItem extends StatefulWidget {
  const _TurnMenuItem({
    required this.icon,
    required this.label,
    required this.helpText,
    required this.onTap,
    this.tone = AppColors.primary,
    this.emphasized = false,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String helpText;
  final VoidCallback onTap;

  /// Color semántico del glifo (token del sistema de diseño).
  final Color tone;

  /// Acción principal: tipografía y contraste reforzados.
  final bool emphasized;

  /// Destino principal del menú: superficie resaltada de forma sutil.
  final bool highlight;

  @override
  State<_TurnMenuItem> createState() => _TurnMenuItemState();
}

class _TurnMenuItemState extends State<_TurnMenuItem> {
  bool _showHelp = false;

  /// Acción clave del menú (apertura, cierre, historial): recibe superficie
  /// tonal y tipografía reforzada frente a las acciones secundarias.
  bool get _isPrimary => widget.emphasized || widget.highlight;

  @override
  Widget build(BuildContext context) {
    // Jerarquía en tres niveles, todos con el mismo lenguaje visual:
    //   highlight  → velo azul suave + borde tenue (acción principal)
    //   emphasized → velo azul muy discreto (acciones clave secundarias)
    //   normal     → sin superficie (movimientos manuales)
    final surface = widget.highlight
        ? AppColors.primarySoft.withValues(alpha: 0.66)
        : widget.emphasized
        ? AppColors.primarySoft.withValues(alpha: 0.34)
        : Colors.transparent;
    final iconSurface = widget.tone.withValues(
      alpha: widget.highlight
          ? 0.14
          : widget.emphasized
          ? 0.10
          : 0.055,
    );
    final labelColor = widget.highlight
        ? AppColors.primaryDark
        : AppColors.textPrimary;

    return Container(
      width: _turnMenuRowWidth(context),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: widget.highlight
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.13))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AppColors.primary.withValues(alpha: 0.05),
          splashColor: AppColors.primary.withValues(alpha: 0.07),
          highlightColor: AppColors.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      // Squircle tintado: da vida al glifo sin bloques grandes.
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: iconSurface,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: widget.tone.withValues(
                              alpha: _isPrimary ? 0.16 : 0.10,
                            ),
                          ),
                        ),
                        child: Icon(widget.icon, color: widget.tone, size: 17),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: TextStyle(
                            color: labelColor,
                            fontWeight: _isPrimary
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 14,
                            letterSpacing: 0,
                            height: 1.35,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _showHelp ? 'Ocultar ayuda' : 'Ayuda',
                        onPressed: () => setState(() => _showHelp = !_showHelp),
                        icon: Icon(
                          _showHelp
                              ? Icons.help_rounded
                              : Icons.help_outline_rounded,
                        ),
                        iconSize: 16,
                        color: _showHelp
                            ? AppColors.primary
                            : AppColors.textMuted.withValues(alpha: 0.85),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        splashRadius: 15,
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: widget.highlight
                            ? AppColors.primary.withValues(alpha: 0.55)
                            : AppColors.textMuted.withValues(alpha: 0.45),
                        size: 15,
                      ),
                    ],
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _TurnInlineMenuHelp(text: widget.helpText),
                  crossFadeState: _showHelp
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 150),
                  sizeCurve: Curves.easeOutCubic,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Separador sutil entre bloques del menú (primario / efectivo / historial).
///
/// No añade encabezados ni ruido: solo agrupa visualmente sin sumar altura.
class _TurnMenuDivider extends StatelessWidget {
  const _TurnMenuDivider({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: math.max(0, width - 16),
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 8),
        color: AppColors.border.withValues(alpha: 0.75),
      ),
    );
  }
}

class _TurnInlineMenuHelp extends StatelessWidget {
  const _TurnInlineMenuHelp({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(46, 0, 8, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11.8,
          height: 1.35,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Aviso de que el estado del turno NO está confirmado contra el backend
/// (fallo de red transitorio o error de revalidación). Regla #32/#39: la caché
/// local nunca es autoridad; se muestra como "estado no sincronizado".
class _TurnMenuNotice extends StatelessWidget {
  const _TurnMenuNotice({
    required this.icon,
    required this.label,
    required this.helpText,
  });

  final IconData icon;
  final String label;
  final String helpText;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _turnMenuRowWidth(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E6),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFF4D9A6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFB54708)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF7A4D04),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    helpText,
                    style: const TextStyle(
                      color: Color(0xFF7A4D04),
                      fontSize: 11.5,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentTurnDialog extends StatelessWidget {
  const _CurrentTurnDialog({
    required this.active,
    required this.summary,
    required this.unverified,
    required this.onCloseTurn,
    required this.onOpenHistory,
  });

  final ActiveCashSession? active;
  final CashSummaryModel summary;
  final bool unverified;
  final VoidCallback onCloseTurn;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final openedAt = active == null ? null : toBusinessTime(active!.openedAt);
    final activeDuration = openedAt == null
        ? 'Turno actual'
        : _formatDuration(
            DateTime.now().toUtc().difference(active!.openedAt.toUtc()),
          );
    final dateText = openedAt == null
        ? active?.businessDate ?? ''
        : DateFormat('dd/MM HH:mm', 'es_DO').format(openedAt);

    final media = MediaQuery.sizeOf(context);
    final isPhone = media.width < 520;
    final panelWidth = media.width < 720 ? media.width : 560.0;

    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      backgroundColor: const Color(0xFFEFF6FA),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SizedBox(
        width: panelWidth,
        height: media.height,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: const Color(0xFF1957E6),
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Regresar',
                            onPressed: () => Navigator.pop(context),
                            color: Colors.white,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const Expanded(
                            child: Text(
                              'Turno actual',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Historial de turnos',
                            onPressed: onOpenHistory,
                            color: Colors.white,
                            icon: const Icon(Icons.history_rounded),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(0xFFEAF1FF),
                              child: Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 17,
                                color: Color(0xFF1957E6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: const Color(0xFFDDEAFF),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${active?.userName ?? 'Usuario'} · $activeDuration',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateText,
                        style: const TextStyle(
                          color: Color(0xFF52667C),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isPhone ? 12 : 18,
                      12,
                      isPhone ? 12 : 18,
                      88,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (unverified) ...[
                          const _TurnOfflineNotice(),
                          const SizedBox(height: 10),
                        ],
                        _TurnHero(summary: summary, compact: isPhone),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniTurnCard(
                                icon: Icons.radio_button_checked_rounded,
                                value: formatRdCurrencyAccounting(
                                  summary.openingAmount,
                                ),
                                label: 'Fondo',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniTurnCard(
                                icon: Icons.account_balance_wallet_outlined,
                                value: formatRdCurrencyAccounting(
                                  summary.expectedCash,
                                ),
                                label: 'Esperado',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniTurnCard(
                                icon: Icons.receipt_long_outlined,
                                value: summary.totalTickets.toString(),
                                label: 'Tickets',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _TurnComposition(summary: summary, compact: isPhone),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: onCloseTurn,
                          icon: const Icon(Icons.lock_rounded),
                          label: const Text('Cerrar turno'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1957E6),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) return '0m activos';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours <= 0) return '${minutes}m activos';
    return '${hours}h ${minutes}m activos';
  }
}

class _MiniTurnCard extends StatelessWidget {
  const _MiniTurnCard({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1957E6)),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF52667C), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TurnOfflineNotice extends StatelessWidget {
  const _TurnOfflineNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFAC515)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFFB54708)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mostrando datos locales. Se actualizarán al volver la conexión.',
              style: TextStyle(
                color: Color(0xFF7A4D04),
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnHero extends StatelessWidget {
  const _TurnHero({required this.summary, required this.compact});

  final CashSummaryModel summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total vendido',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            formatRdCurrencyAccounting(summary.totalSales),
            style: TextStyle(
              fontSize: compact ? 27 : 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Efectivo esperado  ${formatRdCurrencyAccounting(summary.expectedCash)}',
            style: const TextStyle(
              color: Color(0xFF1957E6),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnComposition extends StatelessWidget {
  const _TurnComposition({required this.summary, required this.compact});

  final CashSummaryModel summary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 14,
        vertical: compact ? 12 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Detalle del cierre',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          if (!compact) ...[
            const SizedBox(height: 3),
            const Text(
              'Ventas, fondo, entradas y salidas del turno activo.',
              style: TextStyle(color: Color(0xFF52667C), fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          _Line(
            'Fondo de caja',
            summary.openingAmount,
            icon: Icons.savings_outlined,
            color: Color(0xFF1957E6),
          ),
          _Line(
            'Total vendido',
            summary.totalSales,
            icon: Icons.point_of_sale_rounded,
            color: Color(0xFF1957E6),
          ),
          _Line(
            'Ventas efectivo',
            summary.salesCashTotal,
            icon: Icons.payments_outlined,
            color: Color(0xFF16A34A),
          ),
          _Line(
            'Transferencias',
            summary.salesTransferTotal,
            icon: Icons.sync_alt_rounded,
            color: Color(0xFF1957E6),
          ),
          if (summary.creditPaymentCash > 0)
            _Line(
              'Abonos efectivo',
              summary.creditPaymentCash,
              icon: Icons.payments_outlined,
              color: Color(0xFF16A34A),
            ),
          if (summary.creditPaymentTransfer > 0)
            _Line(
              'Abonos transf.',
              summary.creditPaymentTransfer,
              icon: Icons.sync_alt_rounded,
              color: Color(0xFF1957E6),
            ),
          _Line(
            'Créditos',
            summary.creditSalesTotal,
            icon: Icons.account_balance_wallet_outlined,
            color: Color(0xFFB45309),
          ),
          if (summary.creditBalanceTotal > 0)
            _Line(
              'Balance crédito',
              summary.creditBalanceTotal,
              icon: Icons.pending_actions_outlined,
              color: Color(0xFFB45309),
            ),
          _Line(
            'Entradas de dinero',
            summary.cashInManual,
            icon: Icons.add_circle_outline_rounded,
            color: Color(0xFF16A34A),
          ),
          _Line(
            'Salidas de dinero',
            summary.cashOutManual,
            negative: true,
            icon: Icons.remove_circle_outline_rounded,
            color: Color(0xFFDC2626),
          ),
          _Line(
            'Efectivo esperado',
            summary.expectedCash,
            icon: Icons.account_balance_wallet_outlined,
            color: Color(0xFF1957E6),
          ),
          if (summary.categorySummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),
            const Text(
              'Categorías',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
            const SizedBox(height: 6),
            for (final item in summary.categorySummary.take(compact ? 3 : 5))
              _CategoryLine(item: item),
          ],
        ],
      ),
    );
  }
}

class _CategoryLine extends StatelessWidget {
  const _CategoryLine({required this.item});

  final CashCategorySummaryModel item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF52667C),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${formatRdCurrencyAccounting(item.totalSold)} · ${formatRdCurrencyAccounting(item.totalProfit)}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(
    this.label,
    this.value, {
    this.negative = false,
    required this.icon,
    required this.color,
  });

  final String label;
  final double value;
  final bool negative;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            formatRdCurrencyAccounting(value),
            style: TextStyle(
              color: negative ? const Color(0xFFDC2626) : color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnHistoryDialog extends ConsumerStatefulWidget {
  const _TurnHistoryDialog({required this.rows, required this.onPrint});

  final List<CashSessionHistoryModel> rows;
  final Future<void> Function(CashSessionHistoryModel row) onPrint;

  @override
  ConsumerState<_TurnHistoryDialog> createState() => _TurnHistoryDialogState();
}

/// Vistas del panel único de historial.
enum _HistoryTab { turns, movements }

class _TurnHistoryDialogState extends ConsumerState<_TurnHistoryDialog> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCashier;
  String? _selectedStatus;
  String? _selectedBusinessDate;

  _HistoryTab _tab = _HistoryTab.turns;
  List<CashMovementModel> _movements = const [];
  bool _movementsLoading = false;
  bool _movementsLoaded = false;
  Object? _movementsError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectTab(_HistoryTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    if (tab == _HistoryTab.movements) {
      unawaited(_loadMovements());
    }
  }

  /// Carga diferida: los movimientos solo se piden cuando el usuario abre esa
  /// vista, reutilizando `CashRepository.movementHistory` (misma fuente de
  /// datos y misma política offline que la pantalla de movimientos).
  Future<void> _loadMovements() async {
    if (_movementsLoading || _movementsLoaded) return;
    setState(() {
      _movementsLoading = true;
      _movementsError = null;
    });
    try {
      final rows = await ref
          .read(cashRepositoryProvider)
          .movementHistory(take: 200);
      if (!mounted) return;
      setState(() {
        _movements = rows;
        _movementsLoaded = true;
        _movementsLoading = false;
      });
    } catch (error, stack) {
      if (!mounted) return;
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Cargar movimientos en panel de historial',
        notifyUser: false,
      );
      setState(() {
        _movementsError = error;
        _movementsLoading = false;
      });
    }
  }

  void _retryMovements() {
    setState(() => _movementsLoaded = false);
    unawaited(_loadMovements());
  }

  List<String> get _cashiers {
    final values =
        widget.rows.map((row) => row.userName.trim()).toSet().toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  List<String> get _statuses {
    final values = widget.rows.map((row) => row.status.trim()).toSet().toList()
      ..sort();
    return values.where((value) => value.isNotEmpty).toList();
  }

  List<String> get _dates {
    final values =
        widget.rows.map((row) => row.businessDate.trim()).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
    return values.where((value) => value.isNotEmpty).toList();
  }

  List<CashSessionHistoryModel> get _filteredRows {
    final query = _searchController.text.trim().toLowerCase();
    return widget.rows
        .where((row) {
          if ((_selectedCashier ?? '').isNotEmpty &&
              row.userName != _selectedCashier) {
            return false;
          }
          if ((_selectedStatus ?? '').isNotEmpty &&
              row.status != _selectedStatus) {
            return false;
          }
          if ((_selectedBusinessDate ?? '').isNotEmpty &&
              row.businessDate != _selectedBusinessDate) {
            return false;
          }
          if (query.isEmpty) return true;
          final haystack = [
            row.id,
            row.userName,
            row.status,
            row.businessDate,
            row.initialAmount.toStringAsFixed(2),
            row.closingAmount.toStringAsFixed(2),
            row.expectedAmount.toStringAsFixed(2),
            row.difference.toStringAsFixed(2),
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedCashier = null;
      _selectedStatus = null;
      _selectedBusinessDate = null;
    });
  }

  String _headerSubtitle(int visibleTurns) {
    if (_tab == _HistoryTab.turns) {
      return '$visibleTurns de ${widget.rows.length} turnos registrados';
    }
    if (_movementsLoading) return 'Cargando movimientos...';
    if (_movementsError != null && _movements.isEmpty) {
      return 'No se pudieron cargar los movimientos';
    }
    return '${_movements.length} movimientos registrados';
  }

  Widget _buildBody({required bool isPhone}) {
    if (_tab == _HistoryTab.movements) {
      return _buildMovementsBody(isPhone: isPhone);
    }
    final rows = _filteredRows;
    if (rows.isEmpty) return const _HistoryEmptyState();
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        isPhone ? 10 : 14,
        12,
        isPhone ? 10 : 14,
        18,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _HistoryTurnCard(
          row: rows[index],
          onPrint: () => widget.onPrint(rows[index]),
          isPhone: isPhone,
        );
      },
    );
  }

  Widget _buildMovementsBody({required bool isPhone}) {
    if (_movementsLoading && _movements.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_movementsError != null && _movements.isEmpty) {
      return _HistoryEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudieron cargar los movimientos',
        detail: resolveCashError(_movementsError!),
        actionLabel: 'Reintentar',
        onAction: _retryMovements,
      );
    }
    if (_movements.isEmpty) {
      return const _HistoryEmptyState(
        icon: Icons.swap_vert_rounded,
        title: 'Sin movimientos',
        detail: 'No hay entradas ni salidas de efectivo registradas.',
      );
    }
    final entries = _movements
        .where((row) => row.isIn)
        .fold<double>(0, (sum, row) => sum + row.amount);
    final exits = _movements
        .where((row) => !row.isIn)
        .fold<double>(0, (sum, row) => sum + row.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isPhone ? 10 : 14,
            10,
            isPhone ? 10 : 14,
            0,
          ),
          child: _HistoryMovementsSummary(
            entries: entries,
            exits: exits,
            count: _movements.length,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              isPhone ? 10 : 14,
              10,
              isPhone ? 10 : 14,
              18,
            ),
            itemCount: _movements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) =>
                _HistoryMovementCard(row: _movements[index]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final isPhone = media.width < 620;
    final panelWidth = isPhone
        ? media.width
        : (media.width * 0.38).clamp(520.0, 660.0).toDouble();
    final rows = _filteredRows;

    return Dialog(
      alignment: Alignment.centerRight,
      insetPadding: EdgeInsets.zero,
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: panelWidth,
        height: media.height,
        child: Material(
          color: const Color(0xFFF8FAFC),
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HistoryPanelHeader(
                  subtitle: _headerSubtitle(rows.length),
                  onClose: () => Navigator.pop(context),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isPhone ? 10 : 14,
                    10,
                    isPhone ? 10 : 14,
                    0,
                  ),
                  child: _HistoryTabSwitch(value: _tab, onChanged: _selectTab),
                ),
                // Los filtros (cajero / día / estado) pertenecen solo a la vista
                // de turnos: los movimientos tienen su propio resumen.
                if (_tab == _HistoryTab.turns)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      isPhone ? 10 : 14,
                      10,
                      isPhone ? 10 : 14,
                      8,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 42,
                                child: TextField(
                                  controller: _searchController,
                                  decoration: InputDecoration(
                                    hintText: 'Buscar turno...',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      size: 19,
                                    ),
                                    suffixIcon:
                                        _searchController.text.trim().isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Limpiar',
                                            onPressed: () =>
                                                _searchController.clear(),
                                            icon: const Icon(
                                              Icons.close_rounded,
                                              size: 18,
                                            ),
                                          ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFD6E3F5),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFD6E3F5),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isPhone)
                              SizedBox(
                                width: 132,
                                child: _HistoryFilterDropdown(
                                  label: 'Cajero',
                                  value: _selectedCashier,
                                  values: _cashiers,
                                  onChanged: (value) =>
                                      setState(() => _selectedCashier = value),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _HistoryFilterDropdown(
                                label: 'Día',
                                value: _selectedBusinessDate,
                                values: _dates,
                                onChanged: (value) => setState(
                                  () => _selectedBusinessDate = value,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (!isPhone) ...[
                              SizedBox(
                                width: 142,
                                child: _HistoryFilterDropdown(
                                  label: 'Estado',
                                  value: _selectedStatus,
                                  values: _statuses,
                                  onChanged: (value) =>
                                      setState(() => _selectedStatus = value),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            SizedBox(
                              width: 46,
                              height: 42,
                              child: Tooltip(
                                message: 'Limpiar filtros',
                                child: OutlinedButton(
                                  onPressed: _clearFilters,
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    foregroundColor: const Color(0xFF334155),
                                    side: const BorderSide(
                                      color: Color(0xFFD6E3F5),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.filter_alt_off_rounded,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isPhone) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _HistoryFilterDropdown(
                                  label: 'Cajero',
                                  value: _selectedCashier,
                                  values: _cashiers,
                                  onChanged: (value) =>
                                      setState(() => _selectedCashier = value),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _HistoryFilterDropdown(
                                  label: 'Estado',
                                  value: _selectedStatus,
                                  values: _statuses,
                                  onChanged: (value) =>
                                      setState(() => _selectedStatus = value),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                const Divider(height: 1, color: Color(0xFFDDE7EE)),
                Expanded(child: _buildBody(isPhone: isPhone)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryPanelHeader extends StatelessWidget {
  const _HistoryPanelHeader({required this.subtitle, required this.onClose});

  final String subtitle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFDDE7EE))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Color(0xFFDDEAFF)),
            ),
            child: const Icon(Icons.history_rounded, color: Color(0xFF1957E6)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Historial',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF52667C),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Selector interno del panel de historial: Turnos / Movimientos.
///
/// Mismo lenguaje visual que el resto del panel (blanco, borde suave, radio
/// pequeño) y sin color de acento en el segmento inactivo.
class _HistoryTabSwitch extends StatelessWidget {
  const _HistoryTabSwitch({required this.value, required this.onChanged});

  final _HistoryTab value;
  final ValueChanged<_HistoryTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF3F9),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        children: [
          _HistoryTabSegment(
            label: 'Turnos',
            icon: Icons.history_rounded,
            selected: value == _HistoryTab.turns,
            onTap: () => onChanged(_HistoryTab.turns),
          ),
          _HistoryTabSegment(
            label: 'Movimientos',
            icon: Icons.swap_vert_rounded,
            selected: value == _HistoryTab.movements,
            onTap: () => onChanged(_HistoryTab.movements),
          ),
        ],
      ),
    );
  }
}

class _HistoryTabSegment extends StatelessWidget {
  const _HistoryTabSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF1957E6) : const Color(0xFF52667C);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      height: 1.2,
                    ),
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

/// Resumen compacto de la vista de movimientos (entradas / salidas / total).
class _HistoryMovementsSummary extends StatelessWidget {
  const _HistoryMovementsSummary({
    required this.entries,
    required this.exits,
    required this.count,
  });

  final double entries;
  final double exits;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _HistoryAmount(
              'Entradas',
              entries,
              color: const Color(0xFF16A34A),
            ),
          ),
          Expanded(
            child: _HistoryAmount(
              'Salidas',
              exits,
              color: const Color(0xFFDC2626),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Movimientos',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 11,
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

/// Etiqueta legible del tipo de movimiento (única fuente de la copia).
String _movementTypeLabel(CashMovementModel movement) {
  return switch (movement.movementType) {
    'expense' => 'Gasto',
    'owner_draw' => 'Retiro',
    'transfer' => movement.isIn ? 'Entrada' : 'Transfer.',
    _ => movement.isIn ? 'Entrada' : 'Salida',
  };
}

/// Fila de movimiento para el panel de historial (densidad compacta).
class _HistoryMovementCard extends StatelessWidget {
  const _HistoryMovementCard({required this.row});

  final CashMovementModel row;

  @override
  Widget build(BuildContext context) {
    final isIn = row.isIn;
    final color = isIn ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final date = DateFormat(
      'dd/MM/yyyy HH:mm',
      'es_DO',
    ).format(toBusinessTime(row.createdAt));

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 15,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _movementTypeLabel(row),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                if (row.reason.trim().isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    row.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF52667C),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  row.userName == null || row.userName!.trim().isEmpty
                      ? date
                      : '$date · ${row.userName!.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7C8DA1),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isIn ? '+' : '-'}${formatRdCurrencyAccounting(row.amount)}',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFilterDropdown extends StatelessWidget {
  const _HistoryFilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> values;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE7EE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDDE7EE)),
          ),
        ),
        items: [
          const DropdownMenuItem<String>(value: '', child: Text('Todos')),
          ...values.map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (next) => onChanged((next ?? '').isEmpty ? null : next),
      ),
    );
  }
}

class _HistoryTurnCard extends ConsumerStatefulWidget {
  const _HistoryTurnCard({
    required this.row,
    required this.onPrint,
    required this.isPhone,
  });

  final CashSessionHistoryModel row;
  final Future<void> Function() onPrint;
  final bool isPhone;

  @override
  ConsumerState<_HistoryTurnCard> createState() => _HistoryTurnCardState();
}

class _HistoryTurnCardState extends ConsumerState<_HistoryTurnCard> {
  bool _expanded = false;
  bool _loading = false;
  String? _error;
  CashSessionDetailModel? _detail;

  Future<void> _loadDetail() async {
    final repository = ref.read(cashRepositoryProvider);
    try {
      final detail = await repository.sessionDetail(widget.row.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _error = null;
      });
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Cargar detalle de turno en historial',
        notifyUser: false,
      );
      if (!mounted) return;
      setState(() {
        _error = resolveCashError(error);
        _loading = false;
      });
    }
  }

  Future<void> _toggleDetails() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }
    setState(() {
      _expanded = true;
      _loading = _detail == null;
      _error = null;
    });
    if (_detail != null) return;
    await _loadDetail();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm', 'es_DO');
    final opened = fmt.format(toBusinessTime(widget.row.openedAt));
    final closed = widget.row.closedAt == null
        ? 'Sin cierre'
        : fmt.format(toBusinessTime(widget.row.closedAt!));
    final differenceColor = widget.row.difference.abs() < 0.01
        ? const Color(0xFF64748B)
        : widget.row.difference > 0
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Color(0xFFE2E8F0)),
                ),
                child: const Icon(
                  Icons.point_of_sale_rounded,
                  color: Color(0xFF334155),
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.row.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Turno ${widget.row.businessDate}',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _HistoryStatusPill(status: widget.row.status),
              const SizedBox(width: 2),
              if (!widget.isPhone) ...[
                IconButton(
                  tooltip: _expanded ? 'Ocultar detalles' : 'Ver detalles',
                  onPressed: _toggleDetails,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    foregroundColor: _expanded
                        ? const Color(0xFF1957E6)
                        : const Color(0xFF52667C),
                    backgroundColor: _expanded
                        ? const Color(0xFFEAF1FF)
                        : const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  icon: Icon(
                    _expanded
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: 'Reimprimir ticket',
                onPressed: widget.onPrint,
                constraints: const BoxConstraints.tightFor(
                  width: 34,
                  height: 34,
                ),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFF1957E6),
                  backgroundColor: const Color(0xFFEAF1FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                icon: const Icon(Icons.print_rounded, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _HistoryAmount('Inicial', widget.row.initialAmount),
              ),
              Expanded(
                child: _HistoryAmount('Esperado', widget.row.expectedAmount),
              ),
              Expanded(
                child: _HistoryAmount('Cierre', widget.row.closingAmount),
              ),
              Expanded(
                child: _HistoryAmount(
                  'Dif.',
                  widget.row.difference,
                  color: differenceColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Row(
                children: [
                  Expanded(
                    child: _HistoryDateChip(
                      icon: Icons.login_rounded,
                      text: opened,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _HistoryDateChip(
                      icon: Icons.logout_rounded,
                      text: closed,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) _buildDetails(),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    final detail = _detail;
    if (detail == null) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _error ?? 'No se pudieron cargar los detalles.',
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadDetail();
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reintentar'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB45309),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final summary = detail.summary;
    final note = (detail.note ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),
        const SizedBox(height: 10),
        _HistoryDetailSection(
          title: 'Resumen de ventas',
          rows: [
            _HistoryDetailEntry(
              label: 'Base inicial',
              display: formatRdCurrencyAccounting(detail.initialAmount),
            ),
            _HistoryDetailEntry(
              label: 'Total vendido',
              display: formatRdCurrencyAccounting(summary.totalSales),
            ),
            _HistoryDetailEntry(
              label: 'Ventas efectivo',
              display: formatRdCurrencyAccounting(summary.salesCashTotal),
            ),
            _HistoryDetailEntry(
              label: 'Transferencias',
              display: formatRdCurrencyAccounting(summary.salesTransferTotal),
            ),
            _HistoryDetailEntry(
              label: 'Entradas de dinero',
              display: formatRdCurrencyAccounting(summary.cashInManual),
              color: const Color(0xFF16A34A),
            ),
            _HistoryDetailEntry(
              label: 'Salidas de dinero',
              display: formatRdCurrencyAccounting(summary.cashOutManual),
              color: const Color(0xFFDC2626),
            ),
            _HistoryDetailEntry(
              label: 'Gastos',
              display: formatRdCurrencyAccounting(summary.totalExpenses),
              color: const Color(0xFFDC2626),
            ),
            _HistoryDetailEntry(
              label: 'Retiros',
              display: formatRdCurrencyAccounting(summary.totalWithdrawals),
              color: const Color(0xFFDC2626),
            ),
            _HistoryDetailEntry(
              label: 'Devoluciones',
              display: formatRdCurrencyAccounting(summary.refundsCash),
              color: const Color(0xFFDC2626),
            ),
          ],
        ),
        if (summary.creditSalesTotal > 0 ||
            summary.creditPaymentCash > 0 ||
            summary.creditPaymentTransfer > 0) ...[
          const SizedBox(height: 8),
          _HistoryDetailSection(
            title: 'Ventas a crédito',
            rows: [
              _HistoryDetailEntry(
                label: 'Total crédito',
                display: formatRdCurrencyAccounting(summary.creditSalesTotal),
              ),
              _HistoryDetailEntry(
                label: 'Inicial efectivo',
                display: formatRdCurrencyAccounting(summary.creditInitialCash),
              ),
              _HistoryDetailEntry(
                label: 'Inicial transf.',
                display: formatRdCurrencyAccounting(
                  summary.creditInitialTransfer,
                ),
              ),
              _HistoryDetailEntry(
                label: 'Abonos efectivo',
                display: formatRdCurrencyAccounting(summary.creditPaymentCash),
              ),
              _HistoryDetailEntry(
                label: 'Abonos transf.',
                display: formatRdCurrencyAccounting(
                  summary.creditPaymentTransfer,
                ),
              ),
              _HistoryDetailEntry(
                label: 'Balance crédito',
                display: formatRdCurrencyAccounting(summary.creditBalanceTotal),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _HistoryDetailSection(
          title: 'Cuadre final',
          rows: [
            _HistoryDetailEntry(
              label: 'Efectivo esperado',
              display: formatRdCurrencyAccounting(summary.expectedCash),
            ),
            _HistoryDetailEntry(
              label: 'Efectivo contado',
              display: formatRdCurrencyAccounting(detail.closingAmount),
            ),
            _HistoryDetailEntry(
              label: 'Diferencia',
              display: formatRdCurrencyAccounting(detail.difference),
              color: detail.difference.abs() < 0.01
                  ? const Color(0xFF64748B)
                  : detail.difference > 0
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
            ),
            _HistoryDetailEntry(
              label: 'Tickets',
              display: summary.totalTickets.toString(),
            ),
            _HistoryDetailEntry(
              label: 'Devoluciones',
              display: summary.totalRefunds.toString(),
            ),
          ],
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          _HistoryDetailSection(title: 'Nota', note: note),
        ],
        if (detail.movements.isNotEmpty) ...[
          const SizedBox(height: 8),
          _HistoryMovementsSection(movements: detail.movements),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}

class _HistoryDetailEntry {
  const _HistoryDetailEntry({
    required this.label,
    required this.display,
    this.color,
  });

  final String label;
  final String display;
  final Color? color;
}

class _HistoryDetailSection extends StatelessWidget {
  const _HistoryDetailSection({
    required this.title,
    this.rows = const [],
    this.note,
  });

  final String title;
  final List<_HistoryDetailEntry> rows;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (rows.isNotEmpty) const SizedBox(height: 6),
          for (final entry in rows) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.label,
                    style: const TextStyle(
                      color: Color(0xFF52667C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.display,
                  style: TextStyle(
                    color: entry.color ?? const Color(0xFF0F172A),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          if (note != null && note!.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              note!,
              style: const TextStyle(
                color: Color(0xFF52667C),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryMovementsSection extends StatelessWidget {
  const _HistoryMovementsSection({required this.movements});

  final List<CashMovementModel> movements;

  String _movementLabel(CashMovementModel movement) =>
      _movementTypeLabel(movement);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Movimientos (${movements.length})',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          for (final movement in movements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color:
                          (movement.isIn
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626))
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      movement.isIn
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      size: 13,
                      color: movement.isIn
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _movementLabel(movement),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (movement.reason.trim().isNotEmpty)
                          Text(
                            movement.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${movement.isIn ? '+' : '-'}'
                    '${formatRdCurrencyAccounting(movement.amount)}',
                    style: TextStyle(
                      color: movement.isIn
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                      fontSize: 11,
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

class _HistoryDateChip extends StatelessWidget {
  const _HistoryDateChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFF64748B)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

class _HistoryAmount extends StatelessWidget {
  const _HistoryAmount(this.label, this.value, {this.color});

  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          formatRdCurrencyAccounting(value),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color ?? const Color(0xFF0F172A),
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _HistoryStatusPill extends StatelessWidget {
  const _HistoryStatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toUpperCase();
    final closed = normalized == 'CLOSED' || normalized == 'CERRADO';
    final color = closed ? const Color(0xFF16A34A) : const Color(0xFFF59E0B);
    final label = status.trim().isEmpty
        ? 'Turno'
        : (closed ? 'Cerrado' : status.trim());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({
    this.icon = Icons.history_toggle_off_rounded,
    this.title = 'Sin turnos para mostrar',
    this.detail =
        'Prueba cambiando los filtros o revisa cuando existan turnos cerrados.',
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Color(0xFF1957E6)),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF52667C),
                fontSize: 13,
                height: 1.35,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text(actionLabel!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1957E6),
                  side: const BorderSide(color: Color(0xFFD6E3F5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
