import 'package:flutter_test/flutter_test.dart';
import '../../../lib/core/usage/foreground_activity_meter.dart';

void main() {
  test('counts foreground elapsed time and excludes background', () {
    final m = ForegroundActivityMeter()
      ..reset(0)
      ..foreground(true, 0);
    expect(m.sample(30000).milliseconds, 30000);
    m.foreground(false, 40000);
    expect(m.sample(60000), (active: false, milliseconds: 10000));
    expect(m.sample(90000).milliseconds, 0);
  });
  test('stops after five minutes idle and resumes only after interaction', () {
    final m = ForegroundActivityMeter()
      ..reset(0)
      ..foreground(true, 0);
    for (var i = 1; i <= 10; i++) {
      expect(m.sample(i * 30000).milliseconds, 30000);
    }
    expect(m.sample(330000), (active: false, milliseconds: 0));
    m.interact(340000);
    expect(m.sample(350000), (active: true, milliseconds: 10000));
  });
  test('caps disconnected intervals and resets on change of company', () {
    final m = ForegroundActivityMeter()
      ..reset(0)
      ..foreground(true, 0);
    expect(m.sample(120000).milliseconds, 30000);
    m.reset(130000);
    expect(m.sample(150000), (active: false, milliseconds: 0));
  });
}
