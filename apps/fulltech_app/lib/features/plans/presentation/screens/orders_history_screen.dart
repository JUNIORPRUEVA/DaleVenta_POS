import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/plans_repository.dart';
import '../plans_shell.dart';
import '../widgets/plan_ui.dart';

/// Pantalla 4: historial de ordenes y comprobantes.
class OrdersHistoryScreen extends ConsumerWidget {
  const OrdersHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(licenseOrdersProvider);
    final orders = ordersAsync.valueOrNull ?? const <LicenseOrder>[];

    return PlansShell(
      section: PlansSection.historial,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeading(
            eyebrow: 'Historial',
            title: 'Tus ordenes',
            subtitle:
                'Consulta tus transferencias y comprobantes. Un pago en revisión todavía no está confirmado.',
          ),
          const SizedBox(height: 16),
          if (ordersAsync.isLoading && orders.isEmpty)
            const LoadingBlock(height: 200)
          else if (ordersAsync.hasError)
            ErrorBlock(
              message: 'No se pudo comprobar el historial. Intenta nuevamente.',
              onRetry: () => ref.invalidate(licenseOrdersProvider),
            )
          else if (orders.isEmpty)
            PlansPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PlansEyebrow('Sin ordenes'),
                  const SizedBox(height: 8),
                  const Text(
                    'Todavia no has comprado ni renovado un plan.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 200,
                    child: SquareButton(
                      label: 'Ver planes',
                      onPressed: () => context.push(Routes.planesCatalogo),
                    ),
                  ),
                ],
              ),
            )
          else
            PlansPanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < orders.length; i++) ...[
                    if (i > 0) Container(height: 1, color: AppColors.border),
                    _OrderRow(order: orders[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final LicenseOrder order;

  @override
  Widget build(BuildContext context) {
    final tone = orderTone(order.status);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.planName ?? order.planCode.toUpperCase()} · ${money(order.amount, order.currency)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    order.reference,
                    if (order.createdAt != null) shortDate(order.createdAt),
                    if (order.periodEnd != null)
                      'vence ${shortDate(order.periodEnd)}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (order.hasEvidence)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(
                Icons.attach_file_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ),
          PlansChip(
            label: order.statusLabel,
            background: tone.background,
            border: tone.border,
            color: tone.color,
          ),
        ],
      ),
    );
  }
}
