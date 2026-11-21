import 'dart:js_interop';
import 'package:web/web.dart' as web;

class AssistantFeedbackSound {
  web.AudioContext? _context;
  Future<void> play({bool reply = false}) async {
    try {
      final context = _context ??= web.AudioContext();
      await context.resume().toDart;
      final now = context.currentTime;
      final tone = context.createOscillator();
      final gain = context.createGain();
      tone.frequency.setValueAtTime(reply ? 740 : 520, now);
      gain.gain.setValueAtTime(.0001, now);
      gain.gain.exponentialRampToValueAtTime(.035, now + .015);
      gain.gain.exponentialRampToValueAtTime(.0001, now + .16);
      tone.connect(gain); gain.connect(context.destination);
      tone.start(now); tone.stop(now + .18);
    } catch (_) {
      // Browsers may deny audio; the visible typing indicator remains available.
    }
  }
  void dispose() { _context?.close(); _context = null; }
}
