import 'package:flutter/material.dart';

import '../../../../core/design_system/icons/app_icon.dart';
import '../../../../core/design_system/icons/app_icons.dart';
import '../../../../core/theme/app_colors.dart';

/// Presentación del footer. Los borradores y sus acciones pertenecen al editor.
class SalesTicketBar extends StatelessWidget {
  const SalesTicketBar({
    super.key,
    required this.ticketCount,
    required this.ticketBuilder,
    required this.onCreateTicket,
    this.activeTicketIndex = 0,
  });

  static const addIconAsset = 'assets/image/ticket-add.png';

  final int ticketCount;
  final IndexedWidgetBuilder ticketBuilder;
  final VoidCallback onCreateTicket;
  final int activeTicketIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return SizedBox(
      height: 46,
      child: Material(
        color: AppColors.surfaceAlt,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: _TicketStrip(
                        ticketCount: ticketCount,
                        activeTicketIndex: activeTicketIndex,
                        ticketBuilder: ticketBuilder,
                      ),
                    ),
                    Tooltip(
                      message: 'Nuevo ticket',
                      excludeFromSemantics: true,
                      child: Semantics(
                        button: true,
                        label: 'Nuevo ticket',
                        onTap: onCreateTicket,
                        child: SizedBox(
                          width: 44,
                          child: Material(
                            color: AppColors.surfaceAlt,
                            child: InkWell(
                              onTap: onCreateTicket,
                              excludeFromSemantics: true,
                              child: Center(
                                child: ImageIcon(
                                  const AssetImage(addIconAsset),
                                  size: 18,
                                  color: primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(left: BorderSide(color: AppColors.border)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    child: Text(
                      '$ticketCount ${ticketCount == 1 ? 'ticket' : 'tickets'}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

class _TicketStrip extends StatefulWidget {
  const _TicketStrip({
    required this.ticketCount,
    required this.activeTicketIndex,
    required this.ticketBuilder,
  });

  final int ticketCount;
  final int activeTicketIndex;
  final IndexedWidgetBuilder ticketBuilder;

  @override
  State<_TicketStrip> createState() => _TicketStripState();
}

class _TicketStripState extends State<_TicketStrip> {
  final GlobalKey _activeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _revealActiveTicket();
  }

  @override
  void didUpdateWidget(covariant _TicketStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTicketIndex != widget.activeTicketIndex ||
        oldWidget.ticketCount != widget.ticketCount) {
      _revealActiveTicket();
    }
  }

  void _revealActiveTicket() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final activeContext = _activeKey.currentContext;
      if (activeContext == null) return;
      Scrollable.ensureVisible(
        activeContext,
        alignment: 0.5,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < widget.ticketCount; index++) ...[
          KeyedSubtree(
            key: index == widget.activeTicketIndex ? _activeKey : null,
            child: widget.ticketBuilder(context, index),
          ),
        ],
      ],
    ),
  );
}

class SalesTicketTab extends StatelessWidget {
  static const cartIconAsset = 'assets/image/ticket-cart.png';

  const SalesTicketTab({
    super.key,
    required this.label,
    required this.itemCount,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final String label;
  final int itemCount;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final foreground = selected ? primary : AppColors.textPrimary;
    return SizedBox(
      width: 148,
      height: 46,
      child: Material(
        color: selected ? AppColors.surface : AppColors.surfaceAlt,
        shape: const Border(
          right: BorderSide(color: AppColors.border),
        ),
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    child: Semantics(
                      button: true,
                      selected: selected,
                      label: itemCount > 0
                          ? '$label, $itemCount ${itemCount == 1 ? 'línea' : 'líneas'}'
                          : label,
                      child: ExcludeSemantics(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10, right: 2),
                          child: Row(
                            children: [
                              ImageIcon(
                                const AssetImage(cartIconAsset),
                                size: 16,
                                color: foreground,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Tooltip(
                                  message: label,
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: foreground,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                  ),
                                ),
                              ),
                              if (itemCount > 0) ...[
                                const SizedBox(width: 8),
                                const _TicketActivityDot(),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (selected)
                  SizedBox(
                    width: 30,
                    child: PopupMenuButton<_TicketAction>(
                      tooltip: 'Opciones de $label',
                      padding: EdgeInsets.zero,
                      position: PopupMenuPosition.over,
                      icon: AppIcon(
                        AppIcons.moreVertical,
                        size: 17,
                        color: foreground,
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _TicketAction.rename:
                            onRename();
                            return;
                          case _TicketAction.delete:
                            onDelete();
                            return;
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _TicketAction.rename,
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 12),
                              Text('Editar'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: _TicketAction.delete,
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18),
                              SizedBox(width: 12),
                              Text('Eliminar'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (selected)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 2,
                child: IgnorePointer(
                  child: ColoredBox(
                    key: const ValueKey('ticket-active-line'),
                    color: primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _TicketAction { rename, delete }

class _TicketActivityDot extends StatefulWidget {
  const _TicketActivityDot();

  @override
  State<_TicketActivityDot> createState() => _TicketActivityDotState();
}

class _TicketActivityDotState extends State<_TicketActivityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox.square(
      dimension: 10,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) {
            final progress = Curves.easeInOutSine.transform(_controller.value);
            return Transform.scale(
              key: const ValueKey('ticket-activity-pulse'),
              scale: 1 + 0.35 * progress,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    primary.withValues(alpha: 0.45),
                    primary,
                    progress,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
