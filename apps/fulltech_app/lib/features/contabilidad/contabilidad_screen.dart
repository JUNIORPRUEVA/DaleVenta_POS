import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/fulltech_page_header.dart';

class ContabilidadScreen extends ConsumerWidget {
  const ContabilidadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = hasUserPermission(user, AppPermission.viewAccounting);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    if (!canUseModule) {
      return Scaffold(
        backgroundColor: isDesktop
            ? const Color(0xFFF5F7FA)
            : AppColors.background,
        appBar: isDesktop
            ? const FullTechPageHeader(title: 'Contabilidad')
            : const CustomAppBar(
                title: 'Contabilidad',
                showLogo: false,
                showDepartmentLabel: false,
              ),
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este módulo está disponible solo para usuarios autorizados.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDesktop
          ? const Color(0xFFF5F7FA)
          : AppColors.background,
      appBar: isDesktop
          ? const FullTechPageHeader(title: 'Contabilidad')
          : const CustomAppBar(
              title: 'Contabilidad',
              showLogo: false,
              showDepartmentLabel: false,
            ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: const _AccountingExecutivePage(),
    );
  }
}

class _AccountingExecutivePage extends StatelessWidget {
  const _AccountingExecutivePage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isDesktop = width >= 900;
        if (!isDesktop) {
          return const _AccountingMobileSummary();
        }
        final horizontalPadding = width >= 1100 ? 32.0 : 16.0;
        final contentWidth = width >= 1280 ? 1180.0 : 980.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.account_balance_outlined,
                            color: AppColors.primary,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Centro contable',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Controla depósitos, comprobantes fiscales, pagos pendientes y nómina desde pantallas separadas.',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              context.go(Routes.contabilidadDepositos),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 280,
                        child: _AccountingWorkflowPanel(
                          items: const [
                            _AccountingWorkflowItem(
                              label: 'Preparar depósitos',
                              route: Routes.contabilidadDepositos,
                            ),
                            _AccountingWorkflowItem(
                              label: 'Registrar factura fiscal',
                              route: Routes.contabilidadFacturaFiscal,
                            ),
                            _AccountingWorkflowItem(
                              label: 'Programar pagos',
                              route: Routes.contabilidadPagosPendientes,
                            ),
                            _AccountingWorkflowItem(
                              label: 'Procesar nómina',
                              route: Routes.nomina,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: width >= 1180 ? 2 : 1,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: width >= 1180 ? 2.28 : 3.2,
                          children: const [
                            _AccountingDesktopTile(
                              title: 'Depósitos bancarios',
                              subtitle:
                                  'Órdenes, comprobantes y seguimiento bancario.',
                              icon: Icons.account_balance_outlined,
                              route: Routes.contabilidadDepositos,
                              accent: Color(0xFF0891B2),
                            ),
                            _AccountingDesktopTile(
                              title: 'Factura fiscal',
                              subtitle:
                                  'Comprobantes, compras fiscales y documentos.',
                              icon: Icons.receipt_long_outlined,
                              route: Routes.contabilidadFacturaFiscal,
                              accent: Color(0xFF7C3AED),
                            ),
                            _AccountingDesktopTile(
                              title: 'Pagos pendientes',
                              subtitle:
                                  'Cuentas por pagar, abonos y vencimientos.',
                              icon: Icons.account_balance_wallet_outlined,
                              route: Routes.contabilidadPagosPendientes,
                              accent: Color(0xFFEA580C),
                            ),
                            _AccountingDesktopTile(
                              title: 'Nómina',
                              subtitle:
                                  'Pagos del equipo, control laboral y reportes.',
                              icon: Icons.payments_outlined,
                              route: Routes.nomina,
                              accent: Color(0xFF16A34A),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountingWorkflowItem {
  const _AccountingWorkflowItem({required this.label, required this.route});

  final String label;
  final String route;
}

class _AccountingWorkflowPanel extends StatelessWidget {
  const _AccountingWorkflowPanel({required this.items});

  final List<_AccountingWorkflowItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Flujo de trabajo',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Accesos ordenados para operación diaria.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < items.length; index++)
            _AccountingWorkflowStep(
              number: index + 1,
              item: items[index],
              last: index == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _AccountingWorkflowStep extends StatelessWidget {
  const _AccountingWorkflowStep({
    required this.number,
    required this.item,
    required this.last,
  });

  final int number;
  final _AccountingWorkflowItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.go(item.route),
      child: Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 12),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$number',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountingMobileSummary extends StatelessWidget {
  const _AccountingMobileSummary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [scheme.primary, scheme.tertiary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.24),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.account_balance_outlined,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Contabilidad',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Desde el menú lateral puedes acceder a Depósitos, Factura fiscal, Pagos y Nómina.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountingDesktopTile extends StatelessWidget {
  const _AccountingDesktopTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go(route),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: accent, size: 23),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, color: accent, size: 20),
                ],
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
