import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/debug/app_error_reporter.dart';
import '../../core/utils/media_url.dart';
import '../../core/utils/money_formatters.dart';
import 'cash_close_ticket_printer.dart';
import 'cash_dialogs.dart';
import 'cash_models.dart';
import 'cash_providers.dart';
import 'cash_repository.dart';

class CashTurnMenuButton extends ConsumerWidget {
  const CashTurnMenuButton({super.key, this.compact = false});

  static const _navigatorSettleDelay = Duration(milliseconds: 220);

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
          await ref
              .read(activeCashSessionControllerProvider.notifier)
              .open(amount);
        },
      );
      if (!context.mounted) return;
      if (opened == true) {
        await ref.read(activeCashSessionControllerProvider.notifier).refresh();
        if (!context.mounted) return;
        showCashToast(context, 'Caja abierta');
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
    try {
      final summary = await ref.read(cashRepositoryProvider).summary();
      if (!context.mounted) return;
      final result = await showCloseShiftDialog(
        context,
        expectedCash: summary.expectedCash,
        onCloseShift: (amount) {
          return ref
              .read(activeCashSessionControllerProvider.notifier)
              .close(amount);
        },
      );
      if (!context.mounted) return;
      if (result?.success != true) return;
      await ref.read(activeCashSessionControllerProvider.notifier).refresh();
      if (!context.mounted) return;
      final printResult = result?.printResult;
      final message = printResult == null
          ? 'Turno cerrado'
          : printResult.success
          ? 'Turno cerrado e impreso'
          : 'Turno cerrado. ${printResult.message}';
      showCashToast(context, message);
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

  Future<void> _showCurrentTurn(BuildContext context, WidgetRef ref) async {
    final summary = await ref.read(cashRepositoryProvider).summary();
    if (!context.mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CurrentTurnDialog(
        active: ref.read(activeCashSessionControllerProvider).valueOrNull,
        summary: summary,
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
  }

  Future<void> _showHistory(BuildContext context, WidgetRef ref) async {
    final rows = await ref.read(cashRepositoryProvider).closedSessions();
    if (!context.mounted) return;
    final rootContext = context;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _TurnHistoryDialog(
        rows: rows,
        onPrint: (row) async {
          final result = await ref
              .read(cashCloseTicketPrinterProvider)
              .printHistoryTicket(row);
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
    final user = ref.watch(authStateProvider).user;

    return PopupMenuButton<String>(
      tooltip: 'Turno actual',
      offset: const Offset(0, 44),
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      constraints: const BoxConstraints(minWidth: 292),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFDDE7EE)),
      ),
      itemBuilder: (menuContext) => [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _TurnMenuUserHeader(
            name: (user?.nombreCompleto ?? '').trim(),
            email: (user?.email ?? '').trim(),
            roleLabel: user?.appRole.label ?? 'Usuario',
            photoUrl: resolvePublicMediaUrl(user?.fotoPersonalUrl),
          ),
        ),
        if (active == null)
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _TurnMenuItem(
              icon: Icons.lock_open_rounded,
              label: 'Abrir caja',
              helpText:
                  'Inicia un turno de caja registrando la base inicial de efectivo. Esto habilita el control de ventas, entradas, salidas y cierre del día.',
              onTap: () => _activateMenuItem(
                context,
                menuContext,
                () => _openCash(context, ref),
              ),
            ),
          )
        else ...[
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _TurnMenuItem(
              icon: Icons.receipt_long_outlined,
              label: 'Turno actual',
              helpText:
                  'Muestra el resumen del turno activo, total vendido, efectivo esperado, tickets y composición del corte sin salir de la pantalla de ventas.',
              onTap: () => _activateMenuItem(context, menuContext, () async {
                await _showCurrentTurn(context, ref);
              }),
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _TurnMenuItem(
              icon: Icons.point_of_sale_rounded,
              label: 'Hacer corte de turno',
              helpText:
                  'Cierra el turno activo confirmando el efectivo real de caja. Al finalizar queda registrado el corte y puede imprimirse el comprobante.',
              onTap: () => _activateMenuItem(
                context,
                menuContext,
                () => _closeCash(context, ref),
              ),
            ),
          ),
        ],
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _TurnMenuItem(
            icon: Icons.history_rounded,
            label: 'Historial de turnos',
            helpText:
                'Consulta los turnos cerrados anteriormente, revisa sus montos y reimprime el ticket de cierre cuando sea necesario.',
            onTap: () => _activateMenuItem(
              context,
              menuContext,
              () => _showHistory(context, ref),
            ),
          ),
        ),
      ],
      child: _TurnTopbarButton(
        icon: active == null
            ? Icons.point_of_sale_outlined
            : Icons.store_rounded,
        compact: compact,
      ),
    );
  }
}

class _TurnTopbarButton extends StatefulWidget {
  const _TurnTopbarButton({required this.icon, required this.compact});

  final IconData icon;
  final bool compact;

  @override
  State<_TurnTopbarButton> createState() => _TurnTopbarButtonState();
}

class _TurnTopbarButtonState extends State<_TurnTopbarButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;

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
            height: 40,
            padding: EdgeInsets.fromLTRB(
              widget.compact ? 9 : 10,
              5,
              widget.compact ? 9 : 11,
              5,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: active
                    ? const [Color(0xFFFFFFFF), Color(0xFFEAF1FF)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF7FAFC)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? const Color(0xFF9FBCFF)
                    : const Color(0xFFCFE0FF),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF1957E6,
                  ).withValues(alpha: active ? 0.14 : 0.08),
                  blurRadius: active ? 18 : 10,
                  offset: Offset(0, active ? 7 : 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    widget.icon,
                    color: active
                        ? const Color(0xFF1957E6)
                        : const Color(0xFF123A75),
                    size: 16,
                  ),
                ),
                if (!widget.compact) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Turno actual',
                    style: TextStyle(
                      color: active
                          ? const Color(0xFF1957E6)
                          : const Color(0xFF123A75),
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                      letterSpacing: 0,
                    ),
                  ),
                ],
                const SizedBox(width: 5),
                AnimatedRotation(
                  turns: _pressed ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: active
                        ? const Color(0xFF1957E6)
                        : const Color(0xFF123A75),
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

class _TurnMenuUserHeader extends StatelessWidget {
  const _TurnMenuUserHeader({
    required this.name,
    required this.email,
    required this.roleLabel,
    required this.photoUrl,
  });

  final String name;
  final String email;
  final String roleLabel;
  final String photoUrl;

  String get _safeName => name.isEmpty ? 'Usuario' : name;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (roleLabel.trim().isNotEmpty) roleLabel.trim(),
      if (email.isNotEmpty) email,
    ].join(' · ');
    final hasPhoto = photoUrl.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFCFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4ECF3)),
      ),
      child: Row(
        children: [
          if (hasPhoto) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 30,
                height: 30,
                child: Image.network(
                  photoUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _safeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF102235),
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 0,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF607187),
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TurnMenuItem extends StatefulWidget {
  const _TurnMenuItem({
    required this.icon,
    required this.label,
    required this.helpText,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String helpText;
  final VoidCallback onTap;

  @override
  State<_TurnMenuItem> createState() => _TurnMenuItemState();
}

class _TurnMenuItemState extends State<_TurnMenuItem> {
  bool _showHelp = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 258,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAFC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFDDE7EE)),
                        ),
                        child: Icon(
                          widget.icon,
                          color: const Color(0xFF1957E6),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF183548),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            letterSpacing: 0,
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
                        iconSize: 17,
                        color: _showHelp
                            ? const Color(0xFF1957E6)
                            : const Color(0xFF7C8DA1),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        splashRadius: 17,
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                        size: 18,
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

class _TurnInlineMenuHelp extends StatelessWidget {
  const _TurnInlineMenuHelp({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(42, 0, 4, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF52667C),
          fontSize: 11.6,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _CurrentTurnDialog extends StatelessWidget {
  const _CurrentTurnDialog({
    required this.active,
    required this.summary,
    required this.onCloseTurn,
    required this.onOpenHistory,
  });

  final ActiveCashSession? active;
  final CashSummaryModel summary;
  final VoidCallback onCloseTurn;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final openedAt = active?.openedAt.toLocal();
    final activeDuration = openedAt == null
        ? 'Turno actual'
        : _formatDuration(DateTime.now().difference(openedAt));
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
            Positioned(
              right: 14,
              bottom: 14 + MediaQuery.viewPaddingOf(context).bottom,
              child: FloatingActionButton(
                heroTag: 'current_turn_history',
                tooltip: 'Historial de turnos',
                onPressed: onOpenHistory,
                backgroundColor: const Color(0xFF1957E6),
                foregroundColor: Colors.white,
                child: const Icon(Icons.history_rounded),
              ),
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

class _TurnHistoryDialog extends StatefulWidget {
  const _TurnHistoryDialog({required this.rows, required this.onPrint});

  final List<CashSessionHistoryModel> rows;
  final Future<void> Function(CashSessionHistoryModel row) onPrint;

  @override
  State<_TurnHistoryDialog> createState() => _TurnHistoryDialogState();
}

class _TurnHistoryDialogState extends State<_TurnHistoryDialog> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedCashier;
  String? _selectedStatus;
  String? _selectedBusinessDate;

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
                  total: widget.rows.length,
                  visible: rows.length,
                  onClose: () => Navigator.pop(context),
                ),
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
                              onChanged: (value) =>
                                  setState(() => _selectedBusinessDate = value),
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
                Expanded(
                  child: rows.isEmpty
                      ? const _HistoryEmptyState()
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            isPhone ? 10 : 14,
                            12,
                            isPhone ? 10 : 14,
                            18,
                          ),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            return _HistoryTurnCard(
                              row: rows[index],
                              onPrint: () => widget.onPrint(rows[index]),
                              isPhone: isPhone,
                            );
                          },
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

class _HistoryPanelHeader extends StatelessWidget {
  const _HistoryPanelHeader({
    required this.total,
    required this.visible,
    required this.onClose,
  });

  final int total;
  final int visible;
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
                  '$visible de $total turnos registrados',
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
    try {
      final detail = await ref
          .read(cashRepositoryProvider)
          .sessionDetail(widget.row.id);
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
    final opened = fmt.format(widget.row.openedAt.toLocal());
    final closed = widget.row.closedAt == null
        ? 'Sin cierre'
        : fmt.format(widget.row.closedAt!.toLocal());
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
        if (summary.creditSalesTotal > 0) ...[
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

  String _movementLabel(CashMovementModel movement) {
    return switch (movement.movementType) {
      'expense' => 'Gasto',
      'owner_draw' => 'Retiro',
      'transfer' => movement.isIn ? 'Entrada' : 'Transfer.',
      _ => movement.isIn ? 'Entrada' : 'Salida',
    };
  }

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
  const _HistoryEmptyState();

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
              child: const Icon(
                Icons.history_toggle_off_rounded,
                color: Color(0xFF1957E6),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Sin turnos para mostrar',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Prueba cambiando los filtros o revisa cuando existan turnos cerrados.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF52667C),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
