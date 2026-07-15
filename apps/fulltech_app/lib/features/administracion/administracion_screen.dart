import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';

class AdministracionScreen extends StatelessWidget {
  const AdministracionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
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
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 76, 16, 24),
                    children: [
                      _AdminMenuCard(
                        icon: Icons.punch_clock_outlined,
                        title: 'Registro de ponches',
                        onTap: () => context.push(Routes.administracionPonches),
                      ),
                      const SizedBox(height: 10),
                      _AdminMenuCard(
                        icon: Icons.receipt_long_outlined,
                        title: 'Registro de ventas',
                        onTap: () => context.push(Routes.administracionVentas),
                      ),
                      const SizedBox(height: 10),
                      _AdminMenuCard(
                        icon: Icons.stars_rounded,
                        title: 'Comisiones',
                        onTap: () =>
                            context.push(Routes.administracionComisiones),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 16,
                child: _BackGhostButton(
                  onTap: () =>
                      AppNavigator.goBack(context, fallbackRoute: Routes.home),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackGhostButton extends StatelessWidget {
  const _BackGhostButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface.withValues(alpha: 0.42),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _AdminMenuCard extends StatelessWidget {
  const _AdminMenuCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 18, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: scheme.onSurfaceVariant,
                size: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
