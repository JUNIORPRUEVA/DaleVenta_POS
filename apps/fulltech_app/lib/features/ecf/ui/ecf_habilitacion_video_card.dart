import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/safe_url_launcher.dart';

/// Espacio profesional para el vídeo de preparación previa.
///
/// El vídeo es CONFIGURACIÓN, no un activo inventado: se define con
/// `--dart-define=ECF_HABILITATION_VIDEO_URL=https://…`. Mientras no exista una
/// URL, la tarjeta muestra la guía escrita y el enlace al portal oficial; nunca
/// un reproductor vacío que aparente contenido que no hay.
class EcfHabilitacionVideoCard extends StatelessWidget {
  const EcfHabilitacionVideoCard({
    super.key,
    this.videoUrl = '',
    this.maxVideoWidth = 520,
  });

  /// URL servida por el API (`GET /ecf/dgii/preparation`). Si llega vacía se usa
  /// el valor de compilación, y si tampoco hay, se muestra el marcador.
  final String videoUrl;

  /// La bienvenida puede pedir un vídeo más protagonista sin duplicar el widget.
  final double maxVideoWidth;

  static const _envUrl = String.fromEnvironment(
    'ECF_HABILITATION_VIDEO_URL',
    defaultValue: '',
  );

  /// Portal oficial del contribuyente (DGII).
  static const dgiiPortalUrl = 'https://dgii.gov.do';

  String get _effectiveUrl =>
      videoUrl.trim().isNotEmpty ? videoUrl.trim() : _envUrl;

  bool get hasVideo => _effectiveUrl.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // El espacio 16:9 existe SIEMPRE: es donde irá el tutorial definitivo.
        // Sin URL no se simula reproducción: se muestra un marcador que declara
        // que el vídeo todavía no está disponible. Se acota el ancho para que
        // no domine la pantalla en Windows ni en web.
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxVideoWidth),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: hasVideo
                    ? _VideoSurface(
                        key: const ValueKey('ecf_habilitacion_video_surface'),
                        onPlay: () => safeOpenUrl(
                          context,
                          Uri.parse(_effectiveUrl),
                          copiedMessage: 'Enlace del vídeo copiado',
                        ),
                      )
                    : const _VideoPlaceholder(
                        key: ValueKey('ecf_habilitacion_video_placeholder'),
                      ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasVideo ? 'Prepara tu empresa en la DGII' : 'Antes de empezar',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasVideo
                    ? 'Un vídeo corto con los pasos que debes completar en '
                          'la DGII antes de iniciar la postulación.'
                    : 'El video de preparación estará disponible aquí. '
                          'Puedes comenzar sin esperar o consultar el portal de la DGII.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
              if (hasVideo) ...[
                const SizedBox(height: 8),
                const _Step(
                  text:
                      'Solicita ser emisor electrónico (formulario FI-GDF-016).',
                ),
                const _Step(
                  text:
                      'Obtén el acceso al Portal de Certificación y un certificado digital vigente del representante legal.',
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: () => safeOpenUrl(
                      context,
                      Uri.parse(dgiiPortalUrl),
                      copiedMessage: 'Enlace de la DGII copiado',
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text(
                      'Abrir portal de la DGII',
                      style: TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VideoSurface extends StatelessWidget {
  const _VideoSurface({super.key, required this.onPlay});
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0F172A),
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onPlay,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: Color(0xFF1957E6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ver el vídeo de preparación',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Marcador del espacio reservado cuando el vídeo todavía no está configurado.
///
/// No hay botón de reproducción: un control que no reproduce nada sería una
/// promesa falsa. Solo se identifica dónde irá el tutorial.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.movie_outlined,
                size: 30,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                'Aquí irá el vídeo de preparación',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Todavía no está disponible',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_outline,
              size: 14,
              color: Color(0xFF1957E6),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
