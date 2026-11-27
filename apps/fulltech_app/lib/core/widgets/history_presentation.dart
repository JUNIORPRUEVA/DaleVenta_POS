import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class HistoryEmptyState extends StatelessWidget {
  const HistoryEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
    this.icon = Icons.receipt_long_outlined,
  });
  final String title, message, buttonLabel;
  final VoidCallback? onPressed;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        key: const ValueKey('history-empty-content'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          if (onPressed != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.point_of_sale_outlined, size: 18),
              label: Text(buttonLabel, maxLines: 1),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.surface,
                minimumSize: const Size(140, 40),
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class HistoryMetadataLine extends StatelessWidget {
  const HistoryMetadataLine({
    super.key,
    required this.label,
    required this.value,
  });
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class HistoryAction {
  const HistoryAction(
    this.label,
    this.icon,
    this.onPressed, {
    this.danger = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
}

/// Una fila, también con texto ampliado: las acciones restantes van a «…».
class HistoryActionBar extends StatelessWidget {
  const HistoryActionBar({super.key, required this.actions});
  final List<HistoryAction> actions;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (actions.isEmpty) return const SizedBox.shrink();
      final style = Theme.of(context).textTheme.labelMedium!;
      double width(HistoryAction action) {
        final painter = TextPainter(
          text: TextSpan(text: action.label, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final result = painter.width + 48;
        painter.dispose();
        return result;
      }

      var count = 1;
      var used = width(actions.first);
      for (var i = 1; i < actions.length; i++) {
        final reserved = i == actions.length - 1 ? 0 : 48;
        if (used + 8 + width(actions[i]) + reserved > constraints.maxWidth) {
          break;
        }
        used += 8 + width(actions[i]);
        count++;
      }
      const shape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
      return Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              flex: width(actions[i]).ceil(),
              child: i == 0
                  ? FilledButton.icon(
                      onPressed: actions[i].onPressed,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: shape,
                        textStyle: style,
                      ),
                      icon: Icon(actions[i].icon, size: 18),
                      label: Text(
                        actions[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: actions[i].onPressed,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: shape,
                        textStyle: style,
                        foregroundColor: actions[i].danger
                            ? AppColors.error
                            : null,
                      ),
                      icon: Icon(actions[i].icon, size: 18),
                      label: Text(
                        actions[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          ],
          if (count < actions.length) ...[
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 40,
              child: PopupMenuButton<int>(
                tooltip: 'Más acciones',
                icon: const MobileActionIcon(
                  Icons.more_horiz_rounded,
                  size: 22,
                ),
                onSelected: (index) => actions[index].onPressed?.call(),
                itemBuilder: (_) => [
                  for (var i = count; i < actions.length; i++)
                    PopupMenuItem(
                      value: i,
                      enabled: actions[i].onPressed != null,
                      child: Row(
                        children: [
                          Icon(
                            actions[i].icon,
                            size: 18,
                            color: actions[i].danger ? AppColors.error : null,
                          ),
                          const SizedBox(width: 10),
                          Text(actions[i].label),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// Acabado compartido de los historiales; no contiene estado ni operaciones.
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    foregroundDecoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

class HistoryListHeader extends StatelessWidget {
  const HistoryListHeader({
    super.key,
    required this.label,
    required this.onRefresh,
  });
  final String label;
  final VoidCallback? onRefresh;
  @override
  Widget build(BuildContext context) => Container(
    height: 40,
    padding: const EdgeInsets.only(left: 14, right: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
        IconButton(
          tooltip: 'Actualizar',
          onPressed: onRefresh,
          icon: const MobileActionIcon(Icons.refresh_rounded, size: 18),
        ),
      ],
    ),
  );
}

class HistoryToolbar extends StatelessWidget {
  const HistoryToolbar({
    super.key,
    required this.search,
    this.actions = const [],
    this.maxSearchWidth = double.infinity,
  });
  final Widget search;
  final List<Widget> actions;
  final double maxSearchWidth;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    decoration: const BoxDecoration(
      color: AppColors.surfaceSubtle,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxSearchWidth),
            child: SizedBox(height: 36, child: search),
          ),
        ),
        for (final action in actions) ...[const SizedBox(width: 8), action],
      ],
    ),
  );
}

InputDecoration historySearchDecoration(String hint) => InputDecoration(
  hintText: hint,
  prefixIcon: const MobileActionIcon(Icons.search_rounded, size: 22),
  isDense: true,
  filled: true,
  fillColor: AppColors.surface,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.border),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: AppColors.primary, width: 1.3),
  ),
);

class HistoryMetric extends StatelessWidget {
  const HistoryMetric({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 46),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.surfaceSubtle,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9,
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Las columnas secundarias aparecen según el espacio real de la lista.
class HistoryDocumentRow extends StatelessWidget {
  const HistoryDocumentRow({
    super.key,
    required this.document,
    required this.client,
    required this.amount,
    required this.selected,
    required this.onTap,
    this.date,
    this.extra,
    this.actions = const [],
    this.preserveCompactAmount = false,
  });
  final String document;
  final String client;
  final String amount;
  final bool selected;
  final VoidCallback onTap;
  final String? date;
  final String? extra;
  final List<Widget> actions;
  final bool preserveCompactAmount;

  Widget _text(
    String value, {
    bool bold = false,
    bool muted = false,
    int lines = 1,
  }) => Text(
    value,
    maxLines: lines,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: muted ? AppColors.textMuted : AppColors.textPrimary,
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      return Material(
        color: selected ? const Color(0xFFF0F6FF) : AppColors.surface,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  Expanded(
                    flex: 18,
                    child: _text(document, bold: true, lines: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(flex: 22, child: _text(client)),
                  if (date != null && constraints.maxWidth / scale >= 580) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 15,
                      child: _text(
                        date!.replaceFirst(' ', '\n'),
                        muted: true,
                        lines: 2,
                      ),
                    ),
                  ],
                  if (extra != null &&
                      constraints.maxWidth / scale >= 1000) ...[
                    const SizedBox(width: 10),
                    Expanded(flex: 16, child: _text(extra!, muted: true)),
                  ],
                  const SizedBox(width: 10),
                  if (preserveCompactAmount &&
                      constraints.maxWidth / scale < 480)
                    _text(amount, bold: true)
                  else
                    Expanded(
                      flex: 16,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _text(amount, bold: true),
                      ),
                    ),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ...actions,
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Se limita al panel de detalle, sin alterar diálogos ni acciones del módulo.
class HistoryDetailStyle extends StatelessWidget {
  const HistoryDetailStyle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
    const style = ButtonStyle(
      shape: WidgetStatePropertyAll(shape),
      minimumSize: WidgetStatePropertyAll(Size(0, 40)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
    );
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: style.merge(theme.filledButtonTheme.style),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: style.merge(theme.outlinedButtonTheme.style),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: style.merge(theme.iconButtonTheme.style),
        ),
      ),
      child: child,
    );
  }
}
