/// Only timestamps and elapsed time: never key values, screen content or documents.
class ForegroundActivityMeter {
  static const idleMilliseconds = 300000;
  int _accountedAt = 0;
  int? _lastInteraction;
  int _elapsed = 0;
  bool _foreground = false;

  void reset(int now) {
    _accountedAt = now;
    _lastInteraction = null;
    _elapsed = 0;
    _foreground = false;
  }

  void _advance(int now) {
    if (now < _accountedAt) return;
    final interaction = _lastInteraction;
    if (_foreground && interaction != null) {
      final end = now < interaction + idleMilliseconds
          ? now
          : interaction + idleMilliseconds;
      if (end > _accountedAt) _elapsed += end - _accountedAt;
    }
    _accountedAt = now;
  }

  void interact(int now) {
    _advance(now);
    _lastInteraction = now;
  }

  void foreground(bool value, int now) {
    _advance(now);
    _foreground = value;
    if (value) _lastInteraction = now;
  }

  ({bool active, int milliseconds}) sample(int now) {
    _advance(now);
    final active =
        _foreground &&
        _lastInteraction != null &&
        now - _lastInteraction! < idleMilliseconds;
    final measured = _elapsed.clamp(0, 30000);
    _elapsed = 0;
    return (active: active, milliseconds: measured);
  }
}
