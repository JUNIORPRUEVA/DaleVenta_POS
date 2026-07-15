import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../modules/whatsapp/application/whatsapp_controller.dart';
import '../../modules/whatsapp/whatsapp_instance_model.dart';
import 'configuracion_usuario_detalle_screen.dart';

class ConfiguracionUsuariosScreen extends ConsumerStatefulWidget {
  const ConfiguracionUsuariosScreen({super.key});

  @override
  ConsumerState<ConfiguracionUsuariosScreen> createState() =>
      _ConfiguracionUsuariosScreenState();
}

class _ConfiguracionUsuariosScreenState
    extends ConsumerState<ConfiguracionUsuariosScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(whatsappControllerProvider.notifier).loadAdminUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = user?.appRole == AppRole.admin;
    final state = ref.watch(whatsappControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Configuración por usuario')),
        body: const Center(child: Text('Solo administradores pueden acceder.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configuración por usuario',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!state.adminUsersLoading)
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Actualizar',
              onPressed: () => ref
                  .read(whatsappControllerProvider.notifier)
                  .loadAdminUsers(),
            ),
        ],
      ),
      body: state.adminUsersLoading
          ? const Center(child: CircularProgressIndicator())
          : state.error != null && state.adminUsers.isEmpty
          ? _ErrorView(
              message: state.error!,
              onRetry: () => ref
                  .read(whatsappControllerProvider.notifier)
                  .loadAdminUsers(),
            )
          : state.adminUsers.isEmpty
          ? _EmptyView(theme: theme)
          : RefreshIndicator(
              onRefresh: () => ref
                  .read(whatsappControllerProvider.notifier)
                  .loadAdminUsers(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  // Summary row
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Text(
                          '${state.adminUsers.length} usuarios',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        _WhatsappSummaryBadges(
                          users: state.adminUsers,
                          theme: theme,
                          scheme: scheme,
                        ),
                      ],
                    ),
                  ),
                  // Users list container
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: state.adminUsers
                          .asMap()
                          .entries
                          .map((entry) {
                            final i = entry.key;
                            final u = entry.value;
                            final isLast = i == state.adminUsers.length - 1;
                            return _UserRow(
                              user: u,
                              isFirst: i == 0,
                              isLast: isLast,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ConfiguracionUsuarioDetalleScreen(
                                        user: u,
                                      ),
                                ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── SUMMARY BADGES ────────────────────────────────────────────────────────

class _WhatsappSummaryBadges extends StatelessWidget {
  const _WhatsappSummaryBadges({
    required this.users,
    required this.theme,
    required this.scheme,
  });

  final List<WhatsappAdminUserEntry> users;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final connected = users
        .where((u) => u.whatsapp?.isConnected == true)
        .length;
    final pending = users
        .where((u) => u.whatsapp != null && u.whatsapp!.isConnected == false)
        .length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: const Color(0xFF16A34A)),
        const SizedBox(width: 4),
        Text(
          '$connected',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        _Dot(color: const Color(0xFFF59E0B)),
        const SizedBox(width: 4),
        Text(
          '$pending',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

// ─── USER ROW ────────────────────────────────────────────────────────────────

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final WhatsappAdminUserEntry user;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wa = user.whatsapp;
    final isConnected = wa?.isConnected ?? false;
    final hasInstance = wa != null;

    final dotColor = isConnected
        ? const Color(0xFF16A34A)
        : hasInstance
        ? const Color(0xFFF59E0B)
        : scheme.outlineVariant;

    final topRadius = isFirst ? const Radius.circular(16) : Radius.zero;
    final bottomRadius = isLast ? const Radius.circular(16) : Radius.zero;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.only(
        topLeft: topRadius,
        topRight: topRadius,
        bottomLeft: bottomRadius,
        bottomRight: bottomRadius,
      ),
      child: Container(
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.22),
                  ),
                ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                user.nombreCompleto.isNotEmpty
                    ? user.nombreCompleto[0].toUpperCase()
                    : '?',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Name
            Expanded(
              child: Text(
                user.nombreCompleto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Role badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                _friendlyRole(user.role),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // WhatsApp status dot
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 15,
              color: scheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyRole(String raw) {
    switch (raw.toUpperCase()) {
      case 'ADMIN':
        return 'Admin';
      case 'TECNICO':
        return 'Técnico';
      case 'ASISTENTE':
        return 'Asistente';
      case 'VENDEDOR':
        return 'Vendedor';
      case 'MARKETING':
        return 'Marketing';
      default:
        return raw;
    }
  }
}

// ─── EMPTY / ERROR STATES ────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.theme});
  final ThemeData theme;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No hay usuarios disponibles.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.error,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
