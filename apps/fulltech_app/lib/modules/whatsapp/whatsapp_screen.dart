import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/routing/route_access.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/whatsapp_controller.dart';
import 'application/whatsapp_visibility_provider.dart';
import 'whatsapp_instance_model.dart';
import 'whatsapp_panel.dart';

class WhatsappScreen extends ConsumerStatefulWidget {
  const WhatsappScreen({super.key});

  @override
  ConsumerState<WhatsappScreen> createState() => _WhatsappScreenState();
}

class _WhatsappScreenState extends ConsumerState<WhatsappScreen> {
  /// Prefixes a raw fleet/phone number with "1" (country code) if needed.
  static String? _buildPhone(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final digits = raw.trim().replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('1') && digits.length >= 11) return digits;
    return '1$digits';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(whatsappControllerProvider.notifier).loadInstance();
      final user = ref.read(authStateProvider).user;
      if (user?.appRole == AppRole.admin) {
        ref.read(whatsappControllerProvider.notifier).loadAdminUsers();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final state = ref.watch(whatsappControllerProvider);
    final whatsappVisibility = ref.watch(whatsappNavigationVisibilityProvider);
    final isAdmin = user?.appRole == AppRole.admin;
    final theme = Theme.of(context);

    if (!isAdmin) {
      final shouldShowWhatsapp = whatsappVisibility.maybeWhen(
        data: (value) => value,
        orElse: () => true,
      );

      if (!shouldShowWhatsapp && user != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go(RouteAccess.defaultHomeForRole(user.appRole));
        });

        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'WhatsApp',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await ref.read(whatsappControllerProvider.notifier).loadInstance();
            if (isAdmin) {
              await ref
                  .read(whatsappControllerProvider.notifier)
                  .loadAdminUsers();
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // My WhatsApp section
              _MySectionHeader(theme: theme),
              const SizedBox(height: 12),
              WhatsappPanel(
                defaultInstanceName: user?.nombreCompleto,
                defaultPhoneNumber: _buildPhone(user?.numeroFlota),
              ),

              // Admin users section
              if (isAdmin) ...[
                const SizedBox(height: 28),
                _AdminSectionHeader(
                  theme: theme,
                  count: state.adminUsers.length,
                ),
                const SizedBox(height: 12),
                if (state.adminUsersLoading)
                  const _LoadingCard()
                else if (state.adminUsers.isEmpty)
                  _EmptyAdminCard(theme: theme)
                else
                  _AdminUsersCard(users: state.adminUsers),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€ WIDGETS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _MySectionHeader extends StatelessWidget {
  const _MySectionHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.chat_rounded,
            color: Color(0xFF25D366),
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Mi conexiÃ³n WhatsApp',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _AdminSectionHeader extends StatelessWidget {
  const _AdminSectionHeader({required this.theme, required this.count});

  final ThemeData theme;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.60),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.groups_outlined,
            color: theme.colorScheme.primary,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Estado WhatsApp del equipo',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$count',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.40,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.40),
        ),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyAdminCard extends StatelessWidget {
  const _EmptyAdminCard({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.40,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.40),
        ),
      ),
      child: Center(
        child: Text(
          'No hay usuarios para mostrar.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AdminUsersCard extends StatelessWidget {
  const _AdminUsersCard({required this.users});

  final List<WhatsappAdminUserEntry> users;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: users
            .asMap()
            .entries
            .map((entry) {
              final i = entry.key;
              final user = entry.value;
              final isLast = i == users.length - 1;
              return _AdminUserRow(user: user, isLast: isLast);
            })
            .toList(growable: false),
      ),
    );
  }
}

class _AdminUserRow extends StatelessWidget {
  const _AdminUserRow({required this.user, required this.isLast});

  final WhatsappAdminUserEntry user;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wa = user.whatsapp;
    final isConnected = wa?.isConnected ?? false;
    final hasInstance = wa != null;

    final statusColor = isConnected
        ? const Color(0xFF16A34A)
        : hasInstance
        ? const Color(0xFFF59E0B)
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    final statusIcon = isConnected
        ? Icons.check_circle_rounded
        : hasInstance
        ? Icons.schedule_rounded
        : Icons.radio_button_unchecked_rounded;

    final statusLabel = isConnected
        ? 'Conectado'
        : hasInstance
        ? 'Pendiente'
        : 'Sin instancia';

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.30),
                ),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              user.nombreCompleto.isNotEmpty
                  ? user.nombreCompleto[0].toUpperCase()
                  : '?',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.nombreCompleto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 14),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
