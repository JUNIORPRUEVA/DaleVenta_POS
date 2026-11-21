import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'resource_video_source_io.dart'
    if (dart.library.js_interop) 'resource_video_source_web.dart'
    as platform;

class ResourceVideoSource {
  const ResourceVideoSource(this.controller, this.release);
  final VideoPlayerController controller;
  final Future<void> Function() release;
}

Future<ResourceVideoSource> resourceVideoSource(
  Uint8List bytes,
  String mimeType,
) => platform.resourceVideoSource(bytes, mimeType);
