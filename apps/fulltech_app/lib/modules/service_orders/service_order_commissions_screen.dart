import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import 'application/service_order_commissions_controller.dart';
import 'commissions_models.dart';

class ServiceOrderCommissionsScreen extends ConsumerWidget {
  const ServiceOrderCommissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;
    final state = ref.watch(
      serviceOrderCommissionsControllerProvider(currentUser?.id),
    );
    final controller = ref.read(
      serviceOrderCommissionsControllerProvider(currentUser?.id).notifier,
    );
    final theme = Theme.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final currency = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
    final dateFormat = DateFormat('dd/MM/yyyy', 'es_DO');

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: AppBar(
        title: const Text('Comisiones'),
        actions: [
          if (isMobile)
            IconButton(
              tooltip: 'Filtros',
              onPressed: () => _showMobileFiltersSheet(
                context,
                selectedPeriod: state.selectedPeriod,
                onSelected: controller.changePeriod,
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: state.refreshing ? null : () => controller.refresh(),
            icon: state.refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (!isMobile)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primaryContainer,
                        theme.colorScheme.surface,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumen de comisiones',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        state.range?.label.isNotEmpty == true
                            ? state.range!.label
                            : 'Cargando periodo...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ServiceOrderCommissionPeriod.values
                            .map(
                              (period) => ChoiceChip(
                                label: Text(period.label),
                                selected: state.selectedPeriod == period,
                                onSelected: (_) =>
                                    controller.changePeriod(period),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ),
                )
              else
                _MobilePeriodBanner(rangeLabel: state.range?.label),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final useCompactCards = constraints.maxWidth < 700;

                  if (useCompactCards) {
                    final List<Widget> compactCards = [];
                    if (state.summary.totalServices > 0) {
                      compactCards.add(
                        Expanded(
                          child: _SummaryCard(
                            title: 'Servicios',
                            value: '${state.summary.totalServices}',
                            subtitle: 'Finalizados',
                            icon: Icons.assignment_turned_in_outlined,
                            compact: true,
                            onTap: () => _showSummaryCardDialog(
                              context,
                              title: 'Servicios finalizados',
                              value: '${state.summary.totalServices}',
                              subtitle:
                                  'Órdenes cerradas en el período activo.',
                              icon: Icons.assignment_turned_in_outlined,
                            ),
                          ),
                        ),
                      );
                    }
                    if (state.summary.totalSold > 0) {
                      compactCards.add(
                        Expanded(
                          child: _SummaryCard(
                            title: 'Vendido',
                            value: currency.format(state.summary.totalSold),
                            subtitle: 'Periodo',
                            icon: Icons.payments_outlined,
                            compact: true,
                            onTap: () => _showSummaryCardDialog(
                              context,
                              title: 'Monto total vendido',
                              value: currency.format(state.summary.totalSold),
                              subtitle:
                                  'Suma total vendida dentro de la quincena seleccionada.',
                              icon: Icons.payments_outlined,
                            ),
                          ),
                        ),
                      );
                    }
                    if (state.summary.visibleCommissionTotal > 0) {
                      compactCards.add(
                        Expanded(
                          child: _SummaryCard(
                            title: 'Comisión',
                            value: currency.format(
                              state.summary.visibleCommissionTotal,
                            ),
                            subtitle: 'Visible',
                            icon: Icons.account_balance_wallet_outlined,
                            compact: true,
                            onTap: () => _showSummaryCardDialog(
                              context,
                              title: 'Comisión estimada',
                              value: currency.format(
                                state.summary.visibleCommissionTotal,
                              ),
                              subtitle:
                                  'Total de comisión visible según el rol actual.',
                              icon: Icons.account_balance_wallet_outlined,
                            ),
                          ),
                        ),
                      );
                    }
                    if (compactCards.isEmpty) return const SizedBox.shrink();
                    final List<Widget> rowChildren = [];
                    for (var i = 0; i < compactCards.length; i++) {
                      if (i > 0) {
                        rowChildren.add(const SizedBox(width: spacing));
                      }
                      rowChildren.add(compactCards[i]);
                    }
                    return Row(children: rowChildren);
                  }

                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (state.summary.totalServices > 0)
                        _SummaryCard(
                          title: 'Total servicios',
                          value: '${state.summary.totalServices}',
                          subtitle: 'Órdenes finalizadas en el periodo',
                          icon: Icons.assignment_turned_in_outlined,
                          onTap: () => _showSummaryCardDialog(
                            context,
                            title: 'Servicios finalizados',
                            value: '${state.summary.totalServices}',
                            subtitle: 'Órdenes cerradas en el período activo.',
                            icon: Icons.assignment_turned_in_outlined,
                          ),
                        ),
                      if (state.summary.totalSold > 0)
                        _SummaryCard(
                          title: 'Monto total vendido',
                          value: currency.format(state.summary.totalSold),
                          subtitle: 'Suma de cotizaciones asociadas',
                          icon: Icons.payments_outlined,
                          onTap: () => _showSummaryCardDialog(
                            context,
                            title: 'Monto total vendido',
                            value: currency.format(state.summary.totalSold),
                            subtitle:
                                'Suma total vendida dentro de la quincena seleccionada.',
                            icon: Icons.payments_outlined,
                          ),
                        ),
                      if (state.summary.visibleCommissionTotal > 0)
                        _SummaryCard(
                          title: 'Comisión estimada',
                          value: currency.format(
                            state.summary.visibleCommissionTotal,
                          ),
                          subtitle: 'Según tu visibilidad actual',
                          icon: Icons.account_balance_wallet_outlined,
                          onTap: () => _showSummaryCardDialog(
                            context,
                            title: 'Comisión estimada',
                            value: currency.format(
                              state.summary.visibleCommissionTotal,
                            ),
                            subtitle:
                                'Total de comisión visible según el rol actual.',
                            icon: Icons.account_balance_wallet_outlined,
                          ),
                        ),
                      if (state.summary.averageSold > 0)
                        _SummaryCard(
                          title: 'Promedio por servicio',
                          value: currency.format(state.summary.averageSold),
                          subtitle: 'Promedio de venta por orden',
                          icon: Icons.analytics_outlined,
                          onTap: () => _showSummaryCardDialog(
                            context,
                            title: 'Promedio por servicio',
                            value: currency.format(state.summary.averageSold),
                            subtitle:
                                'Promedio vendido por cada orden del período.',
                            icon: Icons.analytics_outlined,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Órdenes filtradas',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${state.pagination.totalItems} resultados',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (state.loading) const LinearProgressIndicator(minHeight: 2),
              if (state.error != null && state.items.isEmpty)
                _StateMessageCard(
                  icon: Icons.error_outline_rounded,
                  title: 'No se pudieron cargar las comisiones',
                  message: state.error!,
                  actionLabel: 'Reintentar',
                  onAction: controller.refresh,
                )
              else if (state.items.isEmpty)
                const _StateMessageCard(
                  icon: Icons.inbox_outlined,
                  title: 'Sin resultados',
                  message:
                      'No hay órdenes finalizadas para esta quincena con los filtros de comisión aplicados.',
                )
              else ...[
                for (final item in state.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CommissionOrderCard(
                      item: item,
                      currency: currency,
                      dateFormat: dateFormat,
                      compact: isMobile,
                    ),
                  ),
                if (state.pagination.hasMore)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton.tonalIcon(
                      onPressed: state.loadingMore ? null : controller.loadMore,
                      icon: state.loadingMore
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded),
                      label: const Text('Cargar más'),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.compact = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 16 : 20),
        child: Container(
          padding: EdgeInsets.all(compact ? 10 : 16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(compact ? 16 : 20),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: theme.colorScheme.primary,
                size: compact ? 16 : 24,
              ),
              SizedBox(height: compact ? 6 : 12),
              Text(
                title,
                style:
                    (compact
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelLarge)
                        ?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: compact ? 4 : 8),
              Text(
                value,
                style:
                    (compact
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.headlineSmall)
                        ?.copyWith(fontWeight: FontWeight.w900),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: compact ? 2 : 6),
              Text(
                subtitle,
                style:
                    (compact
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.bodySmall)
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommissionOrderCard extends StatelessWidget {
  const _CommissionOrderCard({
    required this.item,
    required this.currency,
    required this.dateFormat,
    required this.compact,
  });

  final ServiceOrderCommissionItem item;
  final NumberFormat currency;
  final DateFormat dateFormat;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => context.go(Routes.serviceOrderById(item.id)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useCompactLayout = compact || constraints.maxWidth < 680;
            final useStackedMeta = constraints.maxWidth < 680;

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: useCompactLayout ? 12 : 16,
                vertical: useCompactLayout ? 12 : 14,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (useStackedMeta) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.clientName.isEmpty
                                ? 'Cliente sin nombre'
                                : item.clientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (useCompactLayout
                                        ? theme.textTheme.titleSmall
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusBadge(compact: true),
                        Text(
                          item.serviceType.isEmpty
                              ? 'Servicio'
                              : item.serviceType,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          item.finalizedAt == null
                              ? 'Sin fecha'
                              : dateFormat.format(item.finalizedAt!.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          currency.format(item.totalAmount),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.clientName.isEmpty
                                ? 'Cliente sin nombre'
                                : item.clientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                (useCompactLayout
                                        ? theme.textTheme.titleSmall
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(compact: useCompactLayout),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            item.serviceType.isEmpty
                                ? 'Servicio'
                                : item.serviceType,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            item.finalizedAt == null
                                ? 'Sin fecha'
                                : dateFormat.format(
                                    item.finalizedAt!.toLocal(),
                                  ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Text(
                            currency.format(item.totalAmount),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F8EF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Finalizada',
        style: TextStyle(
          color: const Color(0xFF197A3E),
          fontWeight: FontWeight.w800,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }
}

class _MobilePeriodBanner extends StatelessWidget {
  const _MobilePeriodBanner({required this.rangeLabel});

  final String? rangeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.date_range_rounded, color: theme.colorScheme.primary),
          Text(
            rangeLabel?.trim().isNotEmpty == true
                ? rangeLabel!
                : 'Cargando periodo...',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StateMessageCard extends StatelessWidget {
  const _StateMessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => onAction!(),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showMobileFiltersSheet(
  BuildContext context, {
  required ServiceOrderCommissionPeriod selectedPeriod,
  required Future<void> Function(ServiceOrderCommissionPeriod period)
  onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filtros de comisiones',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Selecciona la quincena que quieres consultar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              for (final period in ServiceOrderCommissionPeriod.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    selectedPeriod == period
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                  ),
                  title: Text(period.label),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await onSelected(period);
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _showSummaryCardDialog(
  BuildContext context, {
  required String title,
  required String value,
  required String subtitle,
  required IconData icon,
}) {
  final theme = Theme.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 34, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}
