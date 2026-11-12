import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/apps_downloads_panel.dart';
import '../../features/onboarding/application/activation_controller.dart';
import '../../features/onboarding/presentation/widgets/activation_steps.dart';
import '../app_access/app_access_links.dart';
import '../app_access/session_notices.dart';
import '../auth/auth_provider.dart';
import '../auth/app_permissions.dart';
import '../routing/routes.dart';
import '../theme/app_colors.dart';

/// Shared by the real POS header and the navigation shell. No canvas overlay.
class WebSessionActions extends ConsumerWidget {
  const WebSessionActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(webSessionActionsEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    if (!auth.isAuthenticated ||
        user == null ||
        !hasUserPermission(user, AppPermission.manageSettings)) {
      return const SizedBox.shrink();
    }
    final hidden = ref.watch(sessionNoticesProvider);
    final activation = ref.watch(activationControllerProvider).valueOrNull;
    final pending = activation == null ? 0 : activationPendingSteps(activation);
    final labelled = MediaQuery.sizeOf(context).width >= 1200;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending > 0 && !hidden.contains('activation'))
          _NoticeAction(
            label: 'Activa tu FullPOS',
            tooltip:
                'Activa tu FullPOS · $pending pasos pendientes. '
                'También en Configuración → Termina de preparar FullPOS.',
            icon: Icons.rocket_launch_outlined,
            labelled: labelled,
            onOpen: () {
              ref.read(activationPanelOpenProvider.notifier).state = true;
              unawaited(
                ref.read(activationControllerProvider.notifier).reopen(),
              );
            },
            onClose: () =>
                ref.read(sessionNoticesProvider.notifier).dismiss('activation'),
          ),
        if (!hidden.contains('apps'))
          _NoticeAction(
            label: 'Apps',
            tooltip:
                'FullPOS en tus dispositivos. También en Configuración → Apps de la empresa.',
            icon: Icons.devices_other_rounded,
            labelled: labelled,
            onOpen: () => _showApps(context, ref),
            onClose: () =>
                ref.read(sessionNoticesProvider.notifier).dismiss('apps'),
          ),
      ],
    );
  }

  void _showApps(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        alignment: Alignment.center,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: AppColors.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        'FullPOS en tus dispositivos',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar anuncio de aplicaciones',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        ref
                            .read(sessionNoticesProvider.notifier)
                            .dismiss('apps');
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Tu negocio y tu misma cuenta, donde trabajes.'),
                const SizedBox(height: 16),
                for (final channel in AppAccessLinks.allChannels())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppsDownloadCard(channel: channel, concise: true),
                  ),
                const Divider(),
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    context.go(Routes.apps);
                  },
                  child: const Text(
                    'También puedes encontrar estas aplicaciones en Configuración → Apps de la empresa.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeAction extends StatelessWidget {
  const _NoticeAction({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.labelled,
    required this.onOpen,
    required this.onClose,
  });
  final String label;
  final String tooltip;
  final IconData icon;
  final bool labelled;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: tooltip,
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: AppColors.primary),
                    if (labelled) ...[
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ocultar $label durante esta sesión',
            onPressed: onClose,
            constraints: const BoxConstraints.tightFor(width: 24, height: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              minimumSize: const Size(24, 34),
              maximumSize: const Size(24, 34),
            ),
            icon: const Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    ),
  );
}
