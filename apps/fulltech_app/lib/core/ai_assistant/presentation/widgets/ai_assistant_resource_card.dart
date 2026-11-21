import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/media_file_actions.dart';
import '../../data/resource_video_source.dart';
import '../../domain/models/ai_assistant_resource.dart';
import '../../domain/services/ai_assistant_service.dart';

class AiAssistantResourceCard extends ConsumerStatefulWidget {
  const AiAssistantResourceCard({super.key, required this.resource});
  final AiAssistantResource resource;
  @override
  ConsumerState<AiAssistantResourceCard> createState() => _ResourceCardState();
}

class _ResourceCardState extends ConsumerState<AiAssistantResourceCard> {
  Future<Uint8List>? _image;
  Uint8List? _videoBytes;
  bool _loading = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.resource.isImage) _image = _bytes();
  }

  Future<Uint8List> _bytes() =>
      ref.read(aiAssistantServiceProvider).resourceBytes(widget.resource);

  Future<void> _showImage(Uint8List bytes) => showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (context) => Dialog(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                tooltip: 'Cerrar imagen',
                icon: const Icon(Icons.close),
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  semanticLabel: widget.resource.title,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await _bytes();
      if (!mounted) return;
      if (widget.resource.isVideo) {
        setState(() => _videoBytes = bytes);
      } else {
        final extension = widget.resource.mimeType == 'application/pdf'
            ? 'pdf'
            : 'txt';
        await saveMediaBytes(
          bytes: bytes,
          fileName: widget.resource.fileName,
          allowedExtensions: [extension],
          mimeType: widget.resource.mimeType,
        );
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'FullPOS IA recursos',
        ),
      );
      if (mounted) {
        setState(
          () => _error = 'No se pudo abrir el recurso. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resource = widget.resource;
    if (resource.isVideo && _videoBytes != null) {
      return _ResourceVideoDialog(
        bytes: _videoBytes!,
        resource: resource,
        inline: true,
        onClose: () => setState(() => _videoBytes = null),
      );
    }
    if (resource.isImage) {
      return FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton.icon(
              onPressed: () => setState(() => _image = _bytes()),
              icon: const MobileActionIcon(Icons.refresh),
              label: const Text('Reintentar imagen'),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                container: true,
                label: 'Abrir imagen: ${resource.title}',
                button: true,
                excludeSemantics: true,
                onTap: () => _showImage(snapshot.data!),
                child: InkWell(
                  onTap: () => _showImage(snapshot.data!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                      snapshot.data!,
                      height: 140,
                      fit: BoxFit.contain,
                      semanticLabel: resource.title,
                      errorBuilder: (_, _, _) =>
                          const Text('No se pudo mostrar la imagen.'),
                    ),
                  ),
                ),
              ),
              Text(
                resource.title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _loading ? null : _open,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  resource.isVideo
                      ? Icons.play_circle_outline
                      : Icons.download_outlined,
                ),
          label: Text(
            resource.isVideo
                ? 'Ver video: ${resource.title}'
                : 'Descargar: ${resource.title}',
          ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
      ],
    );
  }
}

class _ResourceVideoDialog extends StatefulWidget {
  const _ResourceVideoDialog({
    required this.bytes,
    required this.resource,
    this.inline = false,
    this.onClose,
  });
  final Uint8List bytes;
  final AiAssistantResource resource;
  final bool inline;
  final VoidCallback? onClose;
  @override
  State<_ResourceVideoDialog> createState() => _ResourceVideoDialogState();
}

class _ResourceVideoDialogState extends State<_ResourceVideoDialog> {
  ResourceVideoSource? _source;
  String? _error;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final source = await resourceVideoSource(
        widget.bytes,
        widget.resource.mimeType,
      );
      if (!mounted) {
        await source.controller.dispose();
        await source.release();
        return;
      }
      _source = source;
      await source.controller.initialize();
      if (mounted) setState(() {});
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'FullPOS IA video',
        ),
      );
      if (mounted) setState(() => _error = 'No se pudo reproducir el video.');
    }
  }

  @override
  void dispose() {
    final source = _source;
    if (source != null) _release(source);
    super.dispose();
  }

  Future<void> _release(ResourceVideoSource source) async {
    try {
      await source.controller.dispose();
      await source.release();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'FullPOS IA video',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _source?.controller;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.resource.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (widget.inline)
                  IconButton(
                    tooltip: 'Ampliar video',
                    icon: const Icon(Icons.open_in_full, size: 18),
                    onPressed: () async {
                      await controller?.pause();
                      if (!context.mounted) return;
                      await showDialog<void>(
                        context: context,
                        useRootNavigator: false,
                        builder: (_) => _ResourceVideoDialog(
                          bytes: widget.bytes,
                          resource: widget.resource,
                        ),
                      );
                    },
                  ),
                IconButton(
                  onPressed: widget.onClose ?? () => Navigator.pop(context),
                  tooltip: 'Cerrar video',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!))
            else if (controller == null || !controller.value.isInitialized)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (_, value, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                      VideoProgressIndicator(controller, allowScrubbing: true),
                      IconButton(
                        onPressed: () => value.isPlaying
                            ? controller.pause()
                            : controller.play(),
                        tooltip: value.isPlaying
                            ? 'Pausar video'
                            : 'Reproducir video',
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (widget.inline) {
      return Container(
        height: 220,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(6),
        ),
        child: content,
      );
    }
    return Dialog(child: content);
  }
}
