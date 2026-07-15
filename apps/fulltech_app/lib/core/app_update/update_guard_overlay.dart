import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/safe_url_launcher.dart';
import 'app_update_controller.dart';
import 'app_update_models.dart';

class UpdateGuardOverlay extends ConsumerWidget {
  const UpdateGuardOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appUpdateProvider);
    if (!state.blocksUsage) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final installed = state.installedRelease;
    final updateInfo = state.updateInfo;
    final downloadUrl = updateInfo?.downloadUrl;
    final canOpenDownload =
        downloadUrl != null && downloadUrl.trim().isNotEmpty;
    final isWindows = installed?.platform == ReleasePlatform.windows;
    final isDownloading = state.phase == AppUpdatePhase.downloadingUpdate;
    final isInstalling = state.phase == AppUpdatePhase.installingUpdate;
    final progress = state.downloadProgress;
    final platformName = installed?.platform.displayName ?? 'esta plataforma';
    final installedLabel = installed == null
        ? null
        : '${installed.currentVersion}+${installed.currentBuild}';
    final latestLabel = updateInfo == null
        ? null
        : '${updateInfo.latestVersion ?? 'Nueva versión'}${updateInfo.latestBuild == null ? '' : '+${updateInfo.latestBuild}'}';
    final title = isWindows
        ? (isDownloading
              ? 'Descargando actualización de Windows'
              : isInstalling
              ? 'Instalando actualización de Windows'
              : 'Actualización requerida en Windows')
        : 'Actualización obligatoria';
    final description = isWindows
        ? (isDownloading
              ? 'FullTech está descargando el instalador más reciente de Windows.'
              : isInstalling
              ? 'FullTech inició la instalación automática. Espera unos segundos mientras se cierra la app.'
              : 'Debes actualizar FullTech en Windows para continuar usando la app.')
        : 'Debes actualizar FullTech en $platformName para continuar usando la app.';
    final primaryLabel = isWindows
        ? (isDownloading || isInstalling
              ? 'Actualizando...'
              : 'Reintentar instalación')
        : 'Descargar APK';
    final secondaryLabel = isWindows ? 'Revalidar release' : 'Reintentar';

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: scheme.surface,
                elevation: 18,
                borderRadius: BorderRadius.circular(28),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: scheme.errorContainer,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.system_update_alt_rounded,
                              color: scheme.onErrorContainer,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  description,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _InfoRow(
                        label: 'Versión instalada',
                        value: installedLabel ?? 'Desconocida',
                      ),
                      _InfoRow(
                        label: 'Versión requerida',
                        value: latestLabel ?? 'Disponible',
                      ),
                      if (isWindows && (isDownloading || isInstalling)) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 10,
                            value: isInstalling ? 1 : progress,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isInstalling
                              ? 'Instalador descargado. La instalación silenciosa fue iniciada.'
                              : progress == null
                              ? 'Preparando descarga...'
                              : 'Descarga ${(progress * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if ((updateInfo?.releaseNotes ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Notas de la versión',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            updateInfo!.releaseNotes!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        isWindows
                            ? 'Si el instalador no logra abrirse o necesitas reintentar, usa el botón de instalación automática. Cuando el nuevo build quede instalado, FullTech dejará de bloquear el acceso.'
                            : canOpenDownload
                            ? 'Cuando termine la instalación, vuelve a abrir FullTech y la app validará la nueva versión automáticamente.'
                            : 'No se recibió un enlace de descarga válido. Reintenta la validación o corrige el release en el panel admin.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if ((state.message ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest.withValues(
                              alpha: 0.65,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            state.message!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref
                                    .read(appUpdateProvider.notifier)
                                    .checkNow(force: true);
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(secondaryLabel),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: isWindows
                                  ? (isDownloading || isInstalling
                                        ? null
                                        : () {
                                            ref
                                                .read(
                                                  appUpdateProvider.notifier,
                                                )
                                                .retryBlockedUpdate();
                                          })
                                  : (canOpenDownload
                                        ? () {
                                            safeOpenUrl(
                                              context,
                                              Uri.parse(downloadUrl),
                                              copiedMessage:
                                                  'Enlace de actualización copiado',
                                            );
                                          }
                                        : null),
                              icon: Icon(
                                isWindows
                                    ? Icons.system_update_alt_rounded
                                    : Icons.download_rounded,
                              ),
                              label: Text(primaryLabel),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
