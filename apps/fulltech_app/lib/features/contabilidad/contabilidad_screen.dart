import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/role_permissions.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';

class ContabilidadScreen extends ConsumerWidget {
  const ContabilidadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final canUseModule = canAccessContabilidadByRole(user?.role);

    if (!canUseModule) {
      return Scaffold(
        backgroundColor: MediaQuery.sizeOf(context).width < 900
            ? AppColors.background
            : null,
        appBar: const CustomAppBar(
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
      backgroundColor: MediaQuery.sizeOf(context).width < 900
          ? AppColors.background
          : const Color(0xFFF5F7FA),
      appBar: const CustomAppBar(
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
    final modules = [
      const _AccountingModuleData(
        title: 'Depósitos bancarios',
        description: 'Registro, voucher y carta PDF de depósitos.',
        icon: Icons.account_balance_outlined,
        accent: Color(0xFF1D4ED8),
        route: Routes.contabilidadDepositos,
      ),
      const _AccountingModuleData(
        title: 'Pagos pendientes',
        description: 'Vencimientos, compromisos y balances por pagar.',
        icon: Icons.account_balance_wallet_outlined,
        accent: Color(0xFFEA580C),
        route: Routes.contabilidadPagosPendientes,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final horizontalPadding = width >= 1100 ? 32.0 : 16.0;
        final contentWidth = width >= 1280 ? 980.0 : 860.0;

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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_AccountingModulesWrap(modules: modules)],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountingModulesWrap extends StatelessWidget {
  const _AccountingModulesWrap({required this.modules});

  final List<_AccountingModuleData> modules;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: modules
          .map(
            (module) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AccountingModuleCard(data: module),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _AccountingModuleCard extends StatefulWidget {
  const _AccountingModuleCard({required this.data});

  final _AccountingModuleData data;

  @override
  State<_AccountingModuleCard> createState() => _AccountingModuleCardState();
}

class _AccountingModuleCardState extends State<_AccountingModuleCard> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hovered == value) return;
      setState(() => _hovered = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -1.0 : 0.0, 0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.go(data.route),
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _hovered
                      ? data.accent.withValues(alpha: 0.34)
                      : const Color(0xFFD9E0E8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _hovered ? 0.08 : 0.04,
                    ),
                    blurRadius: _hovered ? 14 : 10,
                    offset: Offset(0, _hovered ? 6 : 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: data.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(data.icon, color: data.accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: data.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          TextSpan(
                            text: '  •  ${data.description}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF64748B),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Abrir',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: data.accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: data.accent,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountingModuleData {
  const _AccountingModuleData({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.route,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final String route;
}
