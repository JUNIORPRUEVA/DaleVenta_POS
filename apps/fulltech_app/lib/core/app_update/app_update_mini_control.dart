import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_controller.dart';
import 'app_update_models.dart';

class AppUpdateMiniControl extends ConsumerWidget {
  const AppUpdateMiniControl({
    super.key,
    this.compact = false,
    this.inTitle = false,
  });

  final bool compact;
  final bool inTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    final phase = state.phase;
    final dismissed =
        state.manifest?.isDismissedBy(state.persisted.dismissedBuild) ?? false;
    final canPrepare =
        phase == AppUpdatePhase.available ||
        phase == AppUpdatePhase.installFailed;
    final isPreparing =
        phase == AppUpdatePhase.downloading ||
        phase == AppUpdatePhase.verifying ||
        phase == AppUpdatePhase.verifyingSha ||
        phase == AppUpdatePhase.verifyingSignature;
    final waiting = phase == AppUpdatePhase.waitingSafeState;
    final installing = phase == AppUpdatePhase.installRequested;
    final ready = phase == AppUpdatePhase.readyToInstall;
    final visible =
        !dismissed &&
        (canPrepare || isPreparing || ready || waiting || installing);
    if (!visible) return const SizedBox.shrink();

    final controller = ref.read(appUpdateProvider.notifier);
    final label = waiting
        ? 'Terminando operación actual...'
        : installing
        ? 'Preparando...'
        : isPreparing
        ? 'Preparando actualización...'
        : 'Actualizar';
    final actionEnabled = ready || canPrepare;
    final canDismiss =
        state.manifest?.buildNumber != null && !waiting && !installing;

    final iconSize = inTitle ? 15.0 : 17.0;
    final closeSize = inTitle ? 14.0 : 16.0;
    final horizontalPadding = inTitle ? 7.0 : 10.0;
    final fontSize = inTitle ? 11.0 : 12.0;
    final closeTapSize = inTitle ? 26.0 : 30.0;

    return Padding(
      padding: EdgeInsets.only(
        left: inTitle ? 8 : 0,
        right: inTitle ? 0 : (compact ? 6 : 8),
      ),
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
              message: ready
                  ? 'Instalar actualización'
                  : canPrepare
                  ? 'Preparar actualización'
                  : 'Preparando actualización',
              child: TextButton.icon(
                onPressed: actionEnabled
                    ? () {
                        if (ready) {
                          controller.requestInstallPreparedUpdate();
                        } else {
                          controller.prepareCurrentUpdateNow();
                        }
                      }
                    : null,
                icon: waiting || installing || isPreparing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.system_update_alt_rounded, size: iconSize),
                label: Text(
                  (compact || inTitle) && ready ? 'Actualizar' : label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1957E6),
                  disabledForegroundColor: const Color(0xFF64748B),
                  visualDensity: VisualDensity.compact,
                  minimumSize: Size(0, inTitle ? 28 : 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  textStyle: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: fontSize,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            if (canDismiss)
              Tooltip(
                message: 'Ocultar actualización',
                child: IconButton(
                  onPressed: controller.dismissCurrentBuild,
                  icon: Icon(Icons.close_rounded, size: closeSize),
                  color: const Color(0xFF64748B),
                  constraints: BoxConstraints.tightFor(
                    width: closeTapSize,
                    height: closeTapSize,
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
