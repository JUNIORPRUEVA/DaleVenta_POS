import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/license/license_repository.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/plans_repository.dart';
import '../plans_shell.dart';
import '../widgets/plan_card.dart';
import '../widgets/plan_ui.dart';
import '../widgets/plans_action_mixin.dart';

/// Pantalla 2: catalogo. El cliente elige plan y se genera la orden.
///
/// Con `?superiores=1` solo muestra los planes **mas caros** que el actual: es
/// el camino del upgrade y evita ofrecerle al cliente algo que ya tiene.
class PlansCatalogScreen extends ConsumerStatefulWidget {
  const PlansCatalogScreen({super.key});

  @override
  ConsumerState<PlansCatalogScreen> createState() => _PlansCatalogScreenState();
}

class _PlansCatalogScreenState extends ConsumerState<PlansCatalogScreen>
    with PlansActionMixin {
  /// Ticket ya abierto en esta sesion (se pinta la confirmacion).
  PlanUpgradeRequest? _request;

  void _choose(PlanOffer plan) {
    // Toda compra o cambio de plan pasa por la **misma** pantalla de pago:
    // ahi se eligen los meses y se muestra lo que hay que transferir hoy.
    context.push('${Routes.planesPago}?plan=${plan.code}');
  }

  Future<void> _requestUpgrade() async {
    final requester = ref.read(planUpgradeRequesterProvider);
    final created = await run(() => requester());
    if (created == null || !mounted) return;
    setState(() => _request = created);
    snack(
      'Ya fue creado un ticket de soporte (${created.reference}). '
      'Un administrador te va a estar contactando para aumentar tu plan cuanto antes.',
    );
    ref.invalidate(planUpgradeOpenProvider);
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(plansCatalogProvider);
    final license = ref.watch(licenseStatusProvider).valueOrNull;
    // Si ya hay un ticket abierto, se muestra la confirmacion desde el inicio.
    final openRequest = ref.watch(planUpgradeOpenProvider).valueOrNull;
    final request = _request ?? openRequest;
    final catalog = plansAsync.valueOrNull ?? const <PlanOffer>[];
    final onlyUpgrades =
        GoRouterState.of(context).uri.queryParameters['superiores'] == '1';
    final current = _currentOf(license, catalog);
    final visible = onlyUpgrades && current != null
        ? catalog
              .where((plan) => plan.monthlyPrice > current.monthlyPrice)
              .toList(growable: false)
        : catalog;
    // Solo cuando hay catalogo y de verdad no queda nada por encima.
    final atTopPlan =
        onlyUpgrades &&
        current != null &&
        catalog.isNotEmpty &&
        visible.isEmpty;

    return PlansShell(
      section: PlansSection.catalogo,
      maxContentWidth: 1440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CatalogHeading(
            title: atTopPlan
                ? 'Ya estás en el último plan'
                : (onlyUpgrades ? 'Sube de plan' : 'Elige tu plan'),
            subtitle: atTopPlan
                ? null
                : onlyUpgrades && current != null
                ? 'Planes superiores a ${current.shortName}.'
                : 'Cambia cuando quieras. Tus datos no se tocan.',
          ),
          // En el camino de mejora solo se ofrecen los planes superiores: no
          // hay atajo para ver el catalogo completo.
          const SizedBox(height: 16),
          if (plansAsync.isLoading && catalog.isEmpty)
            const LoadingBlock(height: 300)
          else if (plansAsync.hasError)
            ErrorBlock(
              message: errorText(plansAsync.error ?? ''),
              onRetry: () => ref.invalidate(plansCatalogProvider),
            )
          else if (visible.isEmpty && onlyUpgrades)
            _TopPlanPanel(
              currentPlanName: current?.name ?? 'tu plan',
              request: request,
              busy: busy,
              onRequest: _requestUpgrade,
            )
          else
            PlansGrid(
              plans: visible,
              currentPlanCode: license?.planCode,
              busy: busy,
              onChoose: _choose,
            ),
        ],
      ),
    );
  }
}

/// Ultimo plan del catalogo: en vez de ofrecer planes que no existen, abre un
/// ticket de soporte. El ticket no cambia la licencia; la aprueba un
/// administrador desde el CRM.
class _TopPlanPanel extends StatelessWidget {
  const _TopPlanPanel({
    required this.currentPlanName,
    required this.request,
    required this.busy,
    required this.onRequest,
  });

  final String currentPlanName;
  final PlanUpgradeRequest? request;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final sent = request != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8ECF1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlansEyebrow('Ya estas en el ultimo plan'),
          const SizedBox(height: 8),
          Text(
            sent
                ? 'Tu solicitud quedó registrada con la referencia ${request!.reference}.'
                : 'No hay un plan superior a $currentPlanName.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          if (!sent) ...[
            const SizedBox(height: 4),
            const Text(
              'Escríbenos y ampliamos tu capacidad.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: 16),
          if (sent)
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Color(0xFF0F9D6E),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Un administrador te va a estar contactando para aumentar tu plan cuanto antes.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F9D6E),
                    ),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: 300,
              height: 42,
              child: TextButton(
                onPressed: busy ? null : onRequest,
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.surfaceMuted,
                  disabledForegroundColor: AppColors.textMuted,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text(
                  'Solicitar mejora de plan a soporte',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Encabezado del catalogo: titulo y, como mucho, una linea de contexto.
class _CatalogHeading extends StatelessWidget {
  const _CatalogHeading({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 12.8,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

PlanOffer? _currentOf(LicenseStatusModel? license, List<PlanOffer> catalog) {
  final code = license?.planCode?.trim().toLowerCase();
  if (code == null || code.isEmpty) return null;
  for (final plan in catalog) {
    if (plan.code.toLowerCase() == code) return plan;
  }
  return null;
}
