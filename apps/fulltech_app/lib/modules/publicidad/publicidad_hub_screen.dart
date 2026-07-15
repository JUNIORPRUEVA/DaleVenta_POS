import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'marketing_models.dart';
import 'publicidad_screen.dart';

class PublicidadHubScreen extends ConsumerWidget {
  const PublicidadHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final isAdmin =
        user != null &&
        hasPermission(user.appRole, AppPermission.viewPublicidad);
    final state = ref.watch(publicidadControllerProvider);
    final controller = ref.read(publicidadControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    if (!isAdmin) {
      return Scaffold(
        appBar: const CustomAppBar(title: 'Publicidad', showLogo: false),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final pendingStories = state.dailyStories
        .where((story) => story.status != MarketingStoryStatus.approved)
        .length;
    final now = DateTime.now();

    final campaignActiveOrFuture = state.publishedAssets.where((item) {
      final marker = '${item.platform} ${item.status} ${item.storyType}'
          .toLowerCase();
      final hasCampaignTag =
          marker.contains('campaign') ||
          marker.contains('ads') ||
          marker.contains('paid');
      return hasCampaignTag &&
          (item.publishedAt == null || item.publishedAt!.isAfter(now));
    }).length;

    final marketplaceFuture = state.publishedAssets.where((item) {
      final marker = '${item.platform} ${item.status} ${item.storyType}'
          .toLowerCase();
      return marker.contains('marketplace') &&
          (item.publishedAt == null || item.publishedAt!.isAfter(now));
    }).length;

    final latestResearchDate =
        state.latestResearch?.createdAt ?? state.latestResearch?.date;
    final latestResearchLabel = state.latestResearch == null
        ? 'Sin investigacion registrada'
        : state.latestResearch!.mainFocus.isEmpty
        ? 'Investigacion sin tema'
        : state.latestResearch!.mainFocus;
    final nextResearchAt = state.dashboard?.nextAutoResearch;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const CustomAppBar(title: 'Publicidad'),
      backgroundColor: scheme.surfaceContainerLowest,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.surface, scheme.surfaceContainerLowest],
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 980;
                    final panelWidth = constraints.maxWidth >= 1400
                        ? 380.0
                        : 340.0;

                    final leftColumn = _HubMainColumn(
                      researchCount: state.researchHistory.length,
                      pendingStories: pendingStories,
                      campaignsCount: campaignActiveOrFuture,
                      marketplaceCount: marketplaceFuture,
                    );

                    final sidePanel = _HubSidePanel(
                      latestResearch: latestResearchLabel,
                      latestResearchDate: _formatDate(latestResearchDate),
                      pendingStories: pendingStories,
                      campaignsCount: campaignActiveOrFuture,
                      marketplaceCount: marketplaceFuture,
                      nextResearchAt: _formatDateTime(nextResearchAt),
                      onNewResearch: () =>
                          context.go(Routes.publicidadInvestigacion),
                      onOpenInvestigacion: () =>
                          context.go(Routes.publicidadInvestigacion),
                      onOpenEstados: () => context.go(Routes.publicidadEstados),
                      onRefresh: controller.refresh,
                    );

                    if (!isDesktop) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CompactHeader(
                            onNewResearch: () =>
                                context.go(Routes.publicidadInvestigacion),
                          ),
                          const SizedBox(height: 12),
                          leftColumn,
                          const SizedBox(height: 12),
                          sidePanel,
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _CompactHeader(
                          onNewResearch: () =>
                              context.go(Routes.publicidadInvestigacion),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: leftColumn),
                            const SizedBox(width: 12),
                            SizedBox(width: panelWidth, child: sidePanel),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/${value.year} $hour:$minute';
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({required this.onNewResearch});

  final VoidCallback onNewResearch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Publicidad',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Centro compacto para investigacion, estados, campanas y marketplace.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onNewResearch,
            icon: const Icon(Icons.addchart_rounded, size: 18),
            label: const Text('Nueva investigacion'),
          ),
        ],
      ),
    );
  }
}

class _HubMainColumn extends StatelessWidget {
  const _HubMainColumn({
    required this.researchCount,
    required this.pendingStories,
    required this.campaignsCount,
    required this.marketplaceCount,
  });

  final int researchCount;
  final int pendingStories;
  final int campaignsCount;
  final int marketplaceCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ModuleRowItem(
          title: 'Investigacion',
          description: 'Base de contenido e historial de aprendizaje.',
          summary: '$researchCount en historial',
          icon: Icons.travel_explore_rounded,
          onEnter: () => context.go(Routes.publicidadInvestigacion),
        ),
        const SizedBox(height: 8),
        _ModuleRowItem(
          title: 'Estados',
          description: 'Flujo actual de estados diarios y aprobaciones.',
          summary: '$pendingStories pendientes',
          icon: Icons.auto_awesome_motion_rounded,
          onEnter: () => context.go(Routes.publicidadEstados),
        ),
        const SizedBox(height: 8),
        _ModuleRowItem(
          title: 'Campanas',
          description: 'Contenido para anuncios pagados y crecimiento.',
          summary: '$campaignsCount activas/futuras',
          icon: Icons.campaign_rounded,
          onEnter: () => context.go(Routes.publicidadCampanas),
        ),
        const SizedBox(height: 8),
        _ModuleRowItem(
          title: 'Marketplace',
          description: 'Publicaciones optimizadas para Facebook Marketplace.',
          summary: '$marketplaceCount futuras',
          icon: Icons.storefront_rounded,
          onEnter: () => context.go(Routes.publicidadMarketplace),
        ),
        const SizedBox(height: 8),
        _ModuleRowItem(
          title: 'Galería de Contenido',
          description:
              'Centro multimedia: productos, uploads, y fuente global.',
          summary: 'Multimedia hub',
          icon: Icons.collections_rounded,
          onEnter: () => context.go(Routes.publicidadGaleria),
        ),
      ],
    );
  }
}

class _ModuleRowItem extends StatefulWidget {
  const _ModuleRowItem({
    required this.title,
    required this.description,
    required this.summary,
    required this.icon,
    required this.onEnter,
  });

  final String title;
  final String description;
  final String summary;
  final IconData icon;
  final VoidCallback onEnter;

  @override
  State<_ModuleRowItem> createState() => _ModuleRowItemState();
}

class _ModuleRowItemState extends State<_ModuleRowItem>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _pressController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: const Duration(milliseconds: 130),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 0.985).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handlePointerDown() => _pressController.forward();
  void _handlePointerUp() => _pressController.reverse();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = _hovered ? scheme.surfaceContainerLow : scheme.surface;
    final borderColor = _hovered
        ? scheme.primary.withValues(alpha: 0.45)
        : scheme.outlineVariant.withValues(alpha: 0.32);
    final iconColor = _hovered ? scheme.primary : scheme.onSurfaceVariant;

    return SizedBox(
      height: 86,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Listener(
          onPointerDown: (_) => _handlePointerDown(),
          onPointerUp: (_) => _handlePointerUp(),
          onPointerCancel: (_) => _handlePointerUp(),
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onEnter,
                borderRadius: BorderRadius.circular(14),
                splashColor: scheme.primary.withValues(alpha: 0.12),
                highlightColor: scheme.primary.withValues(alpha: 0.06),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _hovered ? 0.045 : 0.02,
                        ),
                        blurRadius: _hovered ? 14 : 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(
                            alpha: 0.55,
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 18,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withValues(
                            alpha: 0.45,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          widget.summary,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 170),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _hovered
                              ? scheme.primaryContainer.withValues(alpha: 0.75)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 19,
                          color: iconColor,
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

class _HubSidePanel extends StatelessWidget {
  const _HubSidePanel({
    required this.latestResearch,
    required this.latestResearchDate,
    required this.pendingStories,
    required this.campaignsCount,
    required this.marketplaceCount,
    required this.nextResearchAt,
    required this.onNewResearch,
    required this.onOpenInvestigacion,
    required this.onOpenEstados,
    required this.onRefresh,
  });

  final String latestResearch;
  final String latestResearchDate;
  final int pendingStories;
  final int campaignsCount;
  final int marketplaceCount;
  final String nextResearchAt;
  final VoidCallback onNewResearch;
  final VoidCallback onOpenInvestigacion;
  final VoidCallback onOpenEstados;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen y acciones',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _PanelMetric(
              label: 'Ultima investigacion',
              value: '$latestResearch · $latestResearchDate',
              icon: Icons.history_edu_rounded,
            ),
            _PanelMetric(
              label: 'Estados pendientes',
              value: '$pendingStories',
              icon: Icons.pending_actions_rounded,
            ),
            _PanelMetric(
              label: 'Campanas activas',
              value: '$campaignsCount',
              icon: Icons.track_changes_rounded,
            ),
            _PanelMetric(
              label: 'Marketplace futuras',
              value: '$marketplaceCount',
              icon: Icons.schedule_rounded,
            ),
            _PanelMetric(
              label: 'Proxima investigacion',
              value: nextResearchAt,
              icon: Icons.update_rounded,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNewResearch,
                icon: const Icon(Icons.addchart_rounded, size: 18),
                label: const Text('Nueva investigacion'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Acciones rapidas',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenInvestigacion,
                  icon: const Icon(Icons.travel_explore_rounded, size: 16),
                  label: const Text('Investigacion'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenEstados,
                  icon: const Icon(Icons.auto_awesome_motion_rounded, size: 16),
                  label: const Text('Estados'),
                ),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelMetric extends StatelessWidget {
  const _PanelMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
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
