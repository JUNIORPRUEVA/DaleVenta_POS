import 'package:flutter/material.dart';

import '../marketing_campaign_models.dart';

/// Campaign wizard step
class CampaignWizardStep {
  final int index;
  final String label;
  final IconData icon;
  final String tooltip;

  const CampaignWizardStep({
    required this.index,
    required this.label,
    required this.icon,
    required this.tooltip,
  });
}

/// Visual state of a wizard step
enum WizardStepState { locked, current, completed, error }

/// Premium wizard header showing campaign phases
class CampaignWizardHeader extends StatelessWidget {
  final MarketingCampaignPhase currentPhase;
  final MarketingCampaignStatus status;
  final bool hasError;

  /// List of wizard steps
  static const List<CampaignWizardStep> steps = [
    CampaignWizardStep(
      index: 0,
      label: 'Diseño',
      icon: Icons.image_rounded,
      tooltip: 'Selecciona y confirma imagen base',
    ),
    CampaignWizardStep(
      index: 1,
      label: 'Copy',
      icon: Icons.edit_rounded,
      tooltip: 'Redacción: headline, textos, CTA',
    ),
    CampaignWizardStep(
      index: 2,
      label: 'Segmentación',
      icon: Icons.people_rounded,
      tooltip: 'Define audiencia y presupuesto',
    ),
    CampaignWizardStep(
      index: 3,
      label: 'Publicación',
      icon: Icons.send_rounded,
      tooltip: 'Envía a Meta Ads',
    ),
    CampaignWizardStep(
      index: 4,
      label: 'Activa',
      icon: Icons.play_circle_rounded,
      tooltip: 'Monitorea la campaña activa',
    ),
  ];

  const CampaignWizardHeader({
    required this.currentPhase,
    required this.status,
    this.hasError = false,
    super.key,
  });

  /// Get the wizard step state for a given index
  WizardStepState _getStepState(int index) {
    if (hasError && currentPhase.index == index) {
      return WizardStepState.error;
    }

    if (index < currentPhase.index) {
      return WizardStepState.completed;
    } else if (index == currentPhase.index) {
      return WizardStepState.current;
    } else {
      return WizardStepState.locked;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Flujo de Campaña',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sigue los pasos para crear y publicar tu campaña',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Status badge
              _StatusBadge(status: status, hasError: hasError),
            ],
          ),
          const SizedBox(height: 14),
          // Steps
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < steps.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _StepConnector(state: _getStepState(i)),
                    ),
                  _StepItem(step: steps[i], state: _getStepState(i)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual step item in the wizard
class _StepItem extends StatefulWidget {
  final CampaignWizardStep step;
  final WizardStepState state;

  const _StepItem({required this.step, required this.state});

  @override
  State<_StepItem> createState() => _StepItemState();
}

class _StepItemState extends State<_StepItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void didUpdateWidget(_StepItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isActive = widget.state == WizardStepState.current;
    final isCompleted = widget.state == WizardStepState.completed;
    final isError = widget.state == WizardStepState.error;
    final isLocked = widget.state == WizardStepState.locked;

    Color bgColor;
    Color borderColor;
    Color iconColor;

    if (isError) {
      bgColor = scheme.errorContainer;
      borderColor = scheme.error;
      iconColor = scheme.error;
    } else if (isActive) {
      bgColor = scheme.primaryContainer;
      borderColor = scheme.primary;
      iconColor = scheme.onPrimaryContainer;
    } else if (isCompleted) {
      bgColor = scheme.primaryContainer.withValues(alpha: 0.5);
      borderColor = scheme.primary.withValues(alpha: 0.5);
      iconColor = scheme.onPrimaryContainer.withValues(alpha: 0.7);
    } else {
      bgColor = scheme.surfaceContainer.withValues(alpha: 0.5);
      borderColor = scheme.outlineVariant.withValues(alpha: 0.3);
      iconColor = scheme.onSurfaceVariant.withValues(alpha: 0.5);
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Tooltip(
        message: widget.step.tooltip,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bgColor,
                border: Border.all(color: borderColor, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (isCompleted)
                    Icon(Icons.check_rounded, size: 24, color: scheme.primary)
                  else if (isError)
                    Icon(Icons.error_rounded, size: 24, color: scheme.error)
                  else
                    Icon(widget.step.icon, size: 20, color: iconColor),
                  if (isActive)
                    SizedBox.expand(
                      child: Material(
                        color: Colors.transparent,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 60,
              child: Text(
                widget.step.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isLocked
                      ? Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                      : null,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Connector line between steps
class _StepConnector extends StatelessWidget {
  final WizardStepState state;

  const _StepConnector({required this.state});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isCompleted = state == WizardStepState.completed;

    return Container(
      width: 20,
      height: 3,
      decoration: BoxDecoration(
        color: isCompleted
            ? scheme.primary
            : scheme.outlineVariant.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Status badge showing campaign state
class _StatusBadge extends StatelessWidget {
  final MarketingCampaignStatus status;
  final bool hasError;

  const _StatusBadge({required this.status, required this.hasError});

  String _getStatusLabel(MarketingCampaignStatus status) {
    switch (status) {
      case MarketingCampaignStatus.draft:
        return 'Borrador';
      case MarketingCampaignStatus.ready:
        return 'Lista';
      case MarketingCampaignStatus.publishing:
        return 'Publicando...';
      case MarketingCampaignStatus.active:
        return 'Activa';
      case MarketingCampaignStatus.paused:
        return 'Pausada';
      case MarketingCampaignStatus.error:
        return 'Error';
      case MarketingCampaignStatus.rejected:
        return 'Rechazada';
    }
  }

  Color _getStatusColor(BuildContext context, MarketingCampaignStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case MarketingCampaignStatus.active:
        return scheme.tertiaryContainer;
      case MarketingCampaignStatus.publishing:
      case MarketingCampaignStatus.ready:
        return scheme.primaryContainer;
      case MarketingCampaignStatus.error:
      case MarketingCampaignStatus.rejected:
        return scheme.errorContainer;
      case MarketingCampaignStatus.paused:
        return scheme.secondaryContainer;
      default:
        return scheme.surfaceContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _getStatusLabel(status);
    final bgColor = _getStatusColor(context, status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == MarketingCampaignStatus.publishing)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(scheme.primary),
                ),
              ),
            ),
          if (status == MarketingCampaignStatus.active)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.tertiary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
