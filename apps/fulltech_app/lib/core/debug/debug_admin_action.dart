import 'package:flutter/material.dart';

import '../models/user_model.dart';

bool canUseDebugAdminAction(UserModel? user, {bool enabled = true}) {
  // Destructive fixture cleanup belongs to isolated test tooling, never the POS.
  return false;
}

class DebugAdminActionButton extends StatelessWidget {
  const DebugAdminActionButton({
    super.key,
    required this.user,
    required this.tooltip,
    required this.onPressed,
    this.enabled = true,
    this.busy = false,
    this.icon = Icons.delete_sweep_rounded,
  });

  final UserModel? user;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool busy;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (!canUseDebugAdminAction(user, enabled: enabled)) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Icon(icon),
    );
  }
}

Future<bool> confirmDebugAdminPurge(
  BuildContext context, {
  required String moduleLabel,
  required String impactLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text('Limpiar $moduleLabel'),
        content: Text(
          'Esta acción solo está disponible para administradores. '
          'Se eliminará $impactLabel y no se puede deshacer. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Eliminar todo'),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}
