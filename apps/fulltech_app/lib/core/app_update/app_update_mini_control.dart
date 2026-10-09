import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_controller.dart';
import 'app_update_models.dart';

class AppUpdateMiniControl extends ConsumerWidget {
  const AppUpdateMiniControl({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final visible =
        state.hasVisibleMainPrompt ||
        state.phase == AppUpdatePhase.installRequested ||
        state.phase == AppUpdatePhase.waitingSafeState;
    if (!visible) return const SizedBox.shrink();

    final waiting = state.phase == AppUpdatePhase.waitingSafeState;
    final installing = state.phase == AppUpdatePhase.installRequested;
    final enabled = state.phase == AppUpdatePhase.readyToInstall;
    final controller = ref.read(appUpdateProvider.notifier);
    final label = waiting
        ? 'Terminando operación actual...'
        : installing
        ? 'Preparando...'
        : 'Actualizar';

    return Padding(
      padding: EdgeInsets.only(right: compact ? 6 : 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCFE0FF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Instalar actualización',
              child: TextButton.icon(
                onPressed: enabled
                    ? () => controller.requestInstallPreparedUpdate()
                    : null,
                icon: waiting || installing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded, size: 17),
                label: Text(
                  compact && enabled ? 'Actualizar' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1957E6),
                  disabledForegroundColor: const Color(0xFF64748B),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            if (enabled)
              Tooltip(
                message: 'Ocultar actualización',
                child: IconButton(
                  onPressed: controller.dismissCurrentBuild,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: const Color(0xFF64748B),
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
