import 'package:flutter/services.dart';

class AssistantFeedbackSound {
  Future<void> play({bool reply = false}) async {
    try { await SystemSound.play(SystemSoundType.click); }
    catch (_) { /* Sound is optional on platforms without system feedback. */ }
  }
  void dispose() {}
}
