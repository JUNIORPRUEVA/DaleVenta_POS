import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'resource_video_source.dart';

Future<ResourceVideoSource> resourceVideoSource(
  Uint8List bytes,
  String mimeType,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'fullpos-ai-resource-',
  );
  final file = File(
    '${directory.path}${Platform.pathSeparator}video.${mimeType == 'video/webm' ? 'webm' : 'mp4'}',
  );
  try {
    await file.writeAsBytes(bytes, flush: true);
  } catch (_) {
    if (await file.exists()) await file.delete();
    await directory.delete();
    rethrow;
  }
  return ResourceVideoSource(VideoPlayerController.file(file), () async {
    if (await file.exists()) await file.delete();
    if (await directory.exists()) await directory.delete();
  });
}
