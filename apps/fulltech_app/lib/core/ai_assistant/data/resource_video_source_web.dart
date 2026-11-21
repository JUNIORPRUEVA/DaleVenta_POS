import 'dart:js_interop';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;
import 'resource_video_source.dart';

Future<ResourceVideoSource> resourceVideoSource(
  Uint8List bytes,
  String mimeType,
) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  return ResourceVideoSource(
    VideoPlayerController.networkUrl(Uri.parse(url)),
    () async {
      web.URL.revokeObjectURL(url);
    },
  );
}
