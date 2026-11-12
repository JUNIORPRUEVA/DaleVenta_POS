import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_access/app_access_links.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/safe_url_launcher.dart';

/// Panel lateral de «Aplicaciones y descargas».
///
/// Muestra los cuatro canales oficiales de FullPOS Cloud (Windows, Android,
/// iPhone y Web/PWA) con su acción principal, copia de enlace y compartir.
class AppsDownloadsPanel extends StatelessWidget {
  const AppsDownloadsPanel({super.key});

  static const double _maxPanelWidth = 900;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = screenWidth < 760
        ? screenWidth
        : (screenWidth * 0.76).clamp(600.0, _maxPanelWidth);

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: AppColors.background,
        child: Container(
          width: panelWidth,
          height: double.infinity,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.border)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 24,
                offset: Offset(-8, 0),
              ),
            ],
          ),
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                _PanelHeader(onClose: () => Navigator.of(context).maybePop()),
                const Expanded(
                  child: _AppsDownloadsList(padding: EdgeInsets.all(14)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Contenido reutilizable de «Aplicaciones y descargas» para la ruta `/apps`.
class AppsDownloadsContent extends StatelessWidget {
  const AppsDownloadsContent({
    super.key,
    this.padding = const EdgeInsets.all(16),
  });

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return _AppsDownloadsList(padding: padding);
  }
}

/// Lista compacta de las cuatro plataformas oficiales, sin scroll propio.
class AppsDownloadCards extends StatelessWidget {
  const AppsDownloadCards({super.key});

  @override
  Widget build(BuildContext context) {
    final channels = AppAccessLinks.allChannels();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < channels.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          AppsDownloadCard(channel: channels[i]),
        ],
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.secondarySoft,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: const Color(0xFFDDEAFF)),
            ),
            child: const Icon(
              Icons.devices_other_rounded,
              size: 17,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Aplicaciones y descargas',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'Instala FullPOS Cloud en todos tus dispositivos.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _AppsDownloadsList extends StatelessWidget {
  const _AppsDownloadsList({required this.padding});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final channels = AppAccessLinks.allChannels();

    return ListView.separated(
      padding: padding,
      itemCount: channels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => AppsDownloadCard(channel: channels[index]),
    );
  }
}

/// Tarjeta compacta de una plataforma oficial de FullPOS Cloud.
class AppsDownloadCard extends StatelessWidget {
  const AppsDownloadCard({super.key, required this.channel});

  final AppAccessChannel channel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 520;
          final info = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondarySoft,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFDDEAFF)),
                ),
                child: Icon(
                  channel.icon,
                  size: 18,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            channel.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            channel.status,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      channel.description,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final actions = _CardActions(channel: channel);

          if (wide) {
            return Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 10),
                actions,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              info,
              const SizedBox(height: 9),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _CardActions extends StatelessWidget {
  const _CardActions({required this.channel});

  final AppAccessChannel channel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: () => safeOpenUrl(
            context,
            channel.uri,
            copiedMessage: 'No se pudo abrir. Enlace de ${channel.title} copiado',
          ),
          icon: Icon(channel.actionIcon, size: 15),
          label: Text(channel.actionLabel),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.secondary,
            side: const BorderSide(color: Color(0xFF9DB9F8)),
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(width: 2),
        IconButton(
          tooltip: 'Copiar enlace',
          onPressed: () => _copyLink(context, channel),
          icon: const Icon(Icons.link_rounded, size: 17),
          color: AppColors.textSecondary,
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          tooltip: 'Compartir enlace',
          onPressed: () => _shareLink(context, channel),
          icon: const Icon(Icons.share_outlined, size: 17),
          color: AppColors.textSecondary,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

Future<void> _copyLink(BuildContext context, AppAccessChannel channel) async {
  try {
    await Clipboard.setData(ClipboardData(text: channel.uri.toString()));
  } catch (_) {
    // Sin acceso al portapapeles: se informa igualmente al usuario.
  }
  if (!context.mounted) return;
  _showMessage(context, 'Enlace de ${channel.title} copiado');
}

Future<void> _shareLink(BuildContext context, AppAccessChannel channel) async {
  Rect? origin;
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    origin = box.localToGlobal(Offset.zero) & box.size;
  }

  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        text: channel.shareText,
        subject: 'FullPOS Cloud · ${channel.title}',
        sharePositionOrigin: origin,
      ),
    );
    if (result.status == ShareResultStatus.unavailable) {
      if (context.mounted) await _copyLink(context, channel);
    }
  } catch (_) {
    if (context.mounted) await _copyLink(context, channel);
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
}
