import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Contrato de grabación de notas de voz.
///
/// Existe para poder probar el compositor (permiso, cronómetro, cancelar y
/// envío) sin micrófono ni canales de plataforma.
abstract interface class VoiceNoteRecorderContract {
  /// Tope de duración de una nota de voz.
  Duration get maxDuration;

  Future<bool> hasPermission();

  /// Empieza a grabar en un archivo nuevo y devuelve su ruta.
  Future<String> startNew(DateTime at);

  Future<String?> stop();

  Future<void> cancel();

  Future<void> dispose();
}

/// Grabación real con el micrófono del dispositivo.
///
/// - En Windows no hace falta permiso (`hasPermission` devuelve siempre `true`).
/// - Android e iOS lo piden; ambos ya lo declaran: `RECORD_AUDIO` en el
///   manifiesto y `NSMicrophoneUsageDescription` en `Info.plist`.
/// - El archivo se graba en la carpeta temporal y se borra en cuanto se envía.
class VoiceNoteRecorder implements VoiceNoteRecorderContract {
  VoiceNoteRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  /// Tope de duración. `POST /ai/attachments` acepta hasta 15 MB; con AAC-LC
  /// mono a 64 kbps, tres minutos son ~1,4 MB, así que sobra margen y la
  /// transcripción del otro lado sigue siendo rápida.
  @override
  Duration get maxDuration => const Duration(minutes: 3);

  /// AAC-LC mono: formato que el motor de transcripción entiende y que ocupa
  /// poco, sin necesidad de convertir nada en el cliente.
  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
  );

  static const String fileExtension = 'm4a';
  static const String mimeType = 'audio/mp4';

  @override
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> startNew(DateTime at) async {
    final directory = await getTemporaryDirectory();
    final path = p.join(directory.path, fileNameFor(at));
    await _recorder.start(config, path: path);
    return path;
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // Cancelar nunca puede romper el compositor.
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {
      // Liberar el micrófono tampoco puede lanzar al cerrar el panel.
    }
  }

  /// `nota-de-voz-20261111-124530.m4a`
  static String fileNameFor(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}';
    return 'nota-de-voz-$stamp.$fileExtension';
  }
}
