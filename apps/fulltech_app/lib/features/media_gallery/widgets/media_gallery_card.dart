import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../../core/cache/fulltech_cache_manager.dart';
import '../../../core/utils/video_preview_controller.dart';
import '../media_gallery_models.dart';

Future<void> showMediaGalleryViewer(
  BuildContext context,
  List<MediaGalleryItem> items,
  int initialIndex,
  Future<void> Function(MediaGalleryItem item)? onDownload,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog.fullscreen(
        backgroundColor: const Color(0xFF020617),
        child: _FullscreenMediaGallery(
          items: items,
          initialIndex: initialIndex,
          onDownload: onDownload,
        ),
      );
    },
  );
}

class _FullscreenMediaGallery extends StatefulWidget {
  const _FullscreenMediaGallery({
    required this.items,
    required this.initialIndex,
    this.onDownload,
  });

  final List<MediaGalleryItem> items;
  final int initialIndex;
  final Future<void> Function(MediaGalleryItem item)? onDownload;

  @override
  State<_FullscreenMediaGallery> createState() =>
      _FullscreenMediaGalleryState();
}

class _FullscreenMediaGalleryState extends State<_FullscreenMediaGallery> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.items[_currentIndex];

    return Stack(
      children: [
        Positioned.fill(
          child: PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return item.isImage
                  ? _FullScreenImageViewer(item: item)
                  : _FullScreenVideoViewer(item: item);
            },
          ),
        ),
        Positioned(
          top: 18,
          left: 18,
          child: IconButton.filled(
            tooltip: 'Regresar',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.55),
            ),
            onPressed: () {
              final navigator = Navigator.of(context, rootNavigator: true);
              if (navigator.canPop()) {
                navigator.pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        if (widget.onDownload != null)
          Positioned(
            top: 18,
            right: 18,
            child: IconButton.filled(
              tooltip: 'Descargar',
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.55),
              ),
              onPressed: () => widget.onDownload!(currentItem),
              icon: const Icon(Icons.download_outlined),
            ),
          ),
        Positioned(
          top: 18,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Text(
                    '${_currentIndex + 1} / ${widget.items.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MediaGalleryCard extends StatelessWidget {
  const MediaGalleryCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onDownload,
    this.onDelete,
    this.onMarkPublicidad,
    this.isAdmin = false,
  });

  final MediaGalleryItem item;
  final VoidCallback onTap;
  final Future<void> Function()? onDownload;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onMarkPublicidad;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = item.isInstallationCompleted
        ? const Color(0xFF0F766E)
        : const Color(0xFFB45309);
    final dateLabel = DateFormat(
      'dd MMM',
      'es_DO',
    ).format(item.createdAt.toLocal());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: theme.colorScheme.surface,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      item.isImage
                          ? _ImageThumbnail(url: item.url)
                          : _VideoThumbnail(url: item.url),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.05),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.34),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _OverlayBadge(
                          label: item.isVideo ? 'VIDEO' : 'IMAGEN',
                          icon: item.isVideo
                              ? Icons.play_circle_outline_rounded
                              : Icons.image_outlined,
                        ),
                      ),
                      if (onDownload != null)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: IconButton.filledTonal(
                            tooltip: 'Descargar archivo',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.38,
                              ),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: onDownload,
                            icon: const Icon(Icons.download_outlined, size: 18),
                          ),
                        ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.displayComment,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  shadows: const [
                                    Shadow(
                                      color: Color(0xB3000000),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _MiniInfoPill(
                              text: dateLabel,
                              accent: Colors.white,
                              background: Colors.black.withValues(alpha: 0.38),
                            ),
                          ],
                        ),
                      ),
                      if (item.isVideo)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.48),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 34,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _MiniInfoPill(
                          text: item.installationLabel,
                          accent: statusColor,
                          background: statusColor.withValues(alpha: 0.12),
                        ),
                        _MiniInfoPill(
                          text: item.uploadedByLabel,
                          accent: theme.colorScheme.onPrimaryContainer,
                          background: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.48),
                        ),
                        _MiniInfoPill(
                          text: item.orderStatusLabel,
                          accent: theme.colorScheme.onSurfaceVariant,
                          background: theme.colorScheme.surfaceContainerHighest,
                        ),
                        if (item.forPublicidad)
                          const _MiniInfoPill(
                            text: 'Publicidad',
                            accent: Color(0xFF9333EA),
                            background: Color(0xFFF3E8FF),
                          ),
                      ],
                    ),
                    if (isAdmin) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (!item.forPublicidad && onMarkPublicidad != null)
                            Expanded(
                              child: _AdminActionButton(
                                icon: Icons.campaign_outlined,
                                label: 'Para publicidad',
                                color: const Color(0xFF9333EA),
                                onPressed: onMarkPublicidad!,
                              ),
                            ),
                          if (!item.forPublicidad &&
                              onMarkPublicidad != null &&
                              onDelete != null)
                            const SizedBox(width: 6),
                          if (onDelete != null)
                            Expanded(
                              child: _AdminActionButton(
                                icon: Icons.delete_outline_rounded,
                                label: 'Eliminar',
                                color: const Color(0xFFDC2626),
                                onPressed: onDelete!,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: FulltechImageCacheManager.instance,
      fit: BoxFit.cover,
      placeholder: (context, _) =>
          const _ThumbnailPlaceholder(icon: Icons.image_outlined),
      errorWidget: (context, _, __) =>
          const _ThumbnailPlaceholder(icon: Icons.broken_image_outlined),
    );
  }
}

class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.url});

  final String url;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final controller = createVideoPreviewController(path: widget.url);
    if (controller == null) {
      if (mounted) {
        setState(() => _failed = true);
      }
      return;
    }

    try {
      await controller.initialize();
      await controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return _failed
          ? const _ThumbnailPlaceholder(icon: Icons.videocam_off_outlined)
          : const _ThumbnailPlaceholder(icon: Icons.videocam_outlined);
    }

    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return ColoredBox(
      color: const Color(0xFF020617),
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: 220 * aspectRatio,
          height: 220,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
      ),
      child: Center(child: Icon(icon, size: 34, color: Colors.white70)),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({required this.item});

  final MediaGalleryItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: item.url,
                cacheManager: FulltechImageCacheManager.instance,
                fit: BoxFit.contain,
                placeholder: (context, _) => const CircularProgressIndicator(),
                errorWidget: (context, _, __) => const _ViewerErrorState(),
              ),
            ),
          ),
        ),
        _ViewerFooter(item: item),
      ],
    );
  }
}

class _FullScreenVideoViewer extends StatefulWidget {
  const _FullScreenVideoViewer({required this.item});

  final MediaGalleryItem item;

  @override
  State<_FullScreenVideoViewer> createState() => _FullScreenVideoViewerState();
}

class _FullScreenVideoViewerState extends State<_FullScreenVideoViewer> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final controller = createVideoPreviewController(path: widget.item.url);
    if (controller == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }

    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed || _controller == null) {
      return const _ViewerErrorState();
    }

    final controller = _controller!;
    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(controller),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.14),
                            Colors.black.withValues(alpha: 0.28),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: IconButton.filledTonal(
                      onPressed: _togglePlay,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _ViewerFooter(item: widget.item),
      ],
    );
  }
}

class _ViewerFooter extends StatelessWidget {
  const _ViewerFooter({required this.item});

  final MediaGalleryItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.displayComment,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ViewerMeta(label: item.installationLabel),
              _ViewerMeta(label: item.uploadedByLabel),
              _ViewerMeta(label: item.orderStatusLabel),
              _ViewerMeta(
                label: DateFormat(
                  'dd MMM yyyy, h:mm a',
                  'es_DO',
                ).format(item.createdAt.toLocal()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewerMeta extends StatelessWidget {
  const _ViewerMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ViewerErrorState extends StatelessWidget {
  const _ViewerErrorState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: Colors.white70, size: 36),
          SizedBox(height: 12),
          Text(
            'No se pudo abrir este archivo',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _OverlayBadge extends StatelessWidget {
  const _OverlayBadge({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniInfoPill extends StatelessWidget {
  const _MiniInfoPill({
    required this.text,
    required this.accent,
    required this.background,
  });

  final String text;
  final Color accent;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          text,
          style: TextStyle(
            color: accent,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AdminActionButton extends StatefulWidget {
  const _AdminActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onPressed;

  @override
  State<_AdminActionButton> createState() => _AdminActionButtonState();
}

class _AdminActionButtonState extends State<_AdminActionButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: widget.color,
          side: BorderSide(color: widget.color.withValues(alpha: 0.38)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: _loading
            ? null
            : () async {
                setState(() => _loading = true);
                try {
                  await widget.onPressed();
                } finally {
                  if (mounted) setState(() => _loading = false);
                }
              },
        icon: _loading
            ? SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: widget.color,
                ),
              )
            : Icon(widget.icon, size: 14),
        label: Text(widget.label),
      ),
    );
  }
}
