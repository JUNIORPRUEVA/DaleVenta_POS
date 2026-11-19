import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/license/license_repository.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/plans_repository.dart';
import '../plans_shell.dart';
import '../widgets/plan_ui.dart';

/// Pantalla 1: **el plan actual**, con acciones segun el estado.
///
/// - Activa o en prueba: plan, estado, vencimiento, uso y tres acciones
///   (cambiar a plan superior, transferencias, historial).
/// - Vencida o suspendida: pantalla de regularizacion con la transferencia como
///   accion principal y el upgrade como opcion pequena.
class LicenseOverviewScreen extends ConsumerWidget {
  const LicenseOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseAsync = ref.watch(licenseStatusProvider);
    final plansAsync = ref.watch(plansCatalogProvider);
    final ordersAsync = ref.watch(licenseOrdersProvider);

    final license = licenseAsync.valueOrNull;
    final catalog = plansAsync.valueOrNull ?? const <PlanOffer>[];
    final planName = currentPlanName(license, catalog);
    final currentPlan = _planFor(license, catalog);
    final openOrder = openOrderOf(ordersAsync.valueOrNull ?? const []);

    Widget body;
    if (licenseAsync.isLoading && license == null) {
      body = const LoadingBlock(height: 220);
    } else if (license == null) {
      body = ErrorBlock(
        message: 'No se pudo cargar tu licencia.',
        onRetry: () => ref.invalidate(licenseStatusProvider),
      );
    } else if (!license.isUsable) {
      body = _SuspendedState(
        license: license,
        planName: planName,
        hasOpenOrder: openOrder != null,
      );
    } else {
      body = _ActiveState(
        license: license,
        planName: planName,
        plan: currentPlan,
      );
    }

    return PlansShell(
      section: PlansSection.resumen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [body],
      ),
    );
  }
}

PlanOffer? _planFor(LicenseStatusModel? license, List<PlanOffer> catalog) {
  final code = license?.planCode?.trim().toLowerCase();
  if (code == null || code.isEmpty) return null;
  for (final plan in catalog) {
    if (plan.code.toLowerCase() == code) return plan;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Estado normal: activa o en prueba
// ---------------------------------------------------------------------------

class _ActiveState extends StatelessWidget {
  const _ActiveState({
    required this.license,
    required this.planName,
    required this.plan,
  });

  final LicenseStatusModel license;
  final String? planName;
  final PlanOffer? plan;

  @override
  Widget build(BuildContext context) {
    final tone = licenseTone(license);
    // En la prueba **no hay plan contratado**: no se presenta un «plan actual»
    // ni el nombre de la demo como si fuera un plan.
    if (license.status.toUpperCase() == 'TRIAL') {
      return _TrialState(license: license);
    }
    final compact = MediaQuery.sizeOf(context).width < 760;
    final price = plan == null
        ? null
        : money(plan!.monthlyPrice, plan!.currency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlansPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PlansEyebrow('Plan actual'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    planName ?? 'Sin plan asignado',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  PlansChip(
                    label: tone.label,
                    background: tone.background,
                    border: tone.border,
                    color: tone.color,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (price != null) '$price al mes',
                  if (license.periodEndsAt != null)
                    'vence el ${shortDate(license.periodEndsAt)}',
                  if (license.daysRemaining != null)
                    '${license.daysRemaining} ${license.daysRemaining == 1 ? 'dia' : 'dias'} restantes',
                ].join(' · '),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SquareButton(
                      label: 'Cambiar a plan superior',
                      icon: Icons.trending_up_rounded,
                      onPressed: () => context.push(
                        '${Routes.planesCatalogo}?superiores=1',
                      ),
                    ),
                    const SizedBox(height: 10),
                    SquareButton(
                      label: 'Transferencia',
                      variant: SquareVariant.outline,
                      icon: Icons.account_balance_outlined,
                      onPressed: () => context.push(Routes.planesPago),
                    ),
                  ],
                )
              else
                // Dos acciones cuadradas, misma altura y reparto igual.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SquareButton(
                          label: 'Cambiar a plan superior',
                          icon: Icons.trending_up_rounded,
                          onPressed: () => context.push(
                            '${Routes.planesCatalogo}?superiores=1',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SquareButton(
                          label: 'Transferencia',
                          variant: SquareVariant.outline,
                          icon: Icons.account_balance_outlined,
                          onPressed: () => context.push(Routes.planesPago),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _UsagePanel(license: license),
      ],
    );
  }
}

/// Estado de la **prueba**: el cliente aun no tiene un plan contratado.
///
/// No se le presenta un «plan actual» ni se llama «plan» a la demo: lo que
/// necesita saber es que esta probando, cuantos dias le quedan y que puede
/// elegir un plan cuando quiera. Sin avisos encima del punto de venta.
class _TrialState extends StatelessWidget {
  const _TrialState({required this.license});

  final LicenseStatusModel license;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final days = license.daysRemaining;
    final String when;
    if (days == null) {
      when = 'Estás probando FullPOS.';
    } else if (days <= 0) {
      when = 'La prueba termina hoy.';
    } else if (days == 1) {
      when = 'Te queda 1 día de prueba.';
    } else {
      when = 'Te quedan $days días de prueba.';
    }

    final action = SquareButton(
      label: 'Elegir plan',
      icon: Icons.layers_outlined,
      onPressed: () => context.push(Routes.planesCatalogo),
    );

    final informacion = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlansEyebrow('Demo'),
        const SizedBox(height: 6),
        const Text(
          'Aún no tienes un plan activo',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          when,
          style: const TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlansPanel(
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    informacion,
                    const SizedBox(height: 16),
                    action,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: informacion),
                    const SizedBox(width: 24),
                    SizedBox(width: 240, child: action),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _UsagePanel(license: license),
      ],
    );
  }
}

class _UsagePanel extends StatelessWidget {
  const _UsagePanel({required this.license});

  final LicenseStatusModel license;

  @override
  Widget build(BuildContext context) {
    return PlansPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlansEyebrow('Uso de tu licencia'),
          const SizedBox(height: 12),
          _UsageBar(
            label: 'Usuarios',
            used: license.users,
            limit: license.maxUsers,
          ),
          _UsageBar(
            label: 'Productos',
            used: license.products,
            limit: license.maxProducts,
          ),
          _UsageBar(label: 'Almacenes', limit: license.maxWarehouses),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.label, required this.limit, this.used = 0});

  final String label;
  final int limit;
  final int used;

  @override
  Widget build(BuildContext context) {
    final ratio = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final high = used > 0 && ratio >= 0.8;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                used == 0 ? 'Hasta $limit' : '$used de $limit',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: high ? AppColors.warning : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (used > 0) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.surfaceSubtle,
              valueColor: AlwaysStoppedAnimation<Color>(
                high ? AppColors.warning : AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Estado vencido o suspendido
// ---------------------------------------------------------------------------

class _SuspendedState extends StatelessWidget {
  const _SuspendedState({
    required this.license,
    required this.planName,
    required this.hasOpenOrder,
  });

  final LicenseStatusModel license;
  final String? planName;
  final bool hasOpenOrder;

  bool get _blocked => license.status.toUpperCase() == 'BLOCKED';

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppColors.errorSoft,
            border: Border.all(color: AppColors.errorBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PlansEyebrow('Estado de tu plan'),
              const SizedBox(height: 6),
              Text(
                'Tu plan esta suspendido por falta de pago',
                style: const TextStyle(
                  fontSize: 22,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                planName == null
                    ? 'Transfiere y sube el comprobante del pago: en cuanto soporte '
                        'verifique el pago, podras volver a vender.'
                    : 'Plan $planName. ${_blocked ? 'La empresa quedo bloqueada; regulariza el pago para reactivarla.' : 'La licencia vencio y las ventas estan detenidas.'} Transfiere y sube el comprobante para reactivarla.',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SquareButton(
                      label: 'Transferir y subir comprobante',
                      icon: Icons.upload_file_rounded,
                      onPressed: () => context.push(Routes.planesPago),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: 320,
                  child: SquareButton(
                    label: 'Transferir y subir comprobante',
                    icon: Icons.upload_file_rounded,
                    onPressed: () => context.push(Routes.planesPago),
                  ),
                ),
              const SizedBox(height: 12),
              // Opcion pequena: cambiar a un plan superior y pagar ese.
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 250,
                  child: SquareButton(
                    label: 'Cambiar a un plan superior',
                    variant: SquareVariant.ghost,
                    icon: Icons.trending_up_rounded,
                    onPressed: () =>
                        context.push('${Routes.planesCatalogo}?superiores=1'),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PlansEyebrow('Mientras tanto'),
              const SizedBox(height: 8),
              Text(
                hasOpenOrder
                    ? 'Ya tienes una orden abierta: solo falta la transferencia y el comprobante.'
                    : 'Solo Planes y Soporte estan disponibles. Genera la orden en Transferencias '
                        'para obtener la referencia que debes escribir en el concepto.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
