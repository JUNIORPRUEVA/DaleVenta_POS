import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';

test('the first Flutter frame reveals its splash without waiting for authentication', () => {
  const html = readFileSync(new URL('../../apps/fulltech_app/web/index.html', import.meta.url), 'utf8');
  const start = html.indexOf('    window.fullposCompleteWebStartup = function ()');
  const end = html.indexOf('    (function () {', start);
  assert.ok(start >= 0 && end > start);
  const events = new Map(), timers = [], bodyClasses = [], coverClasses = [];
  let removed = false;
  const cover = { classList: { add: name => coverClasses.push(name) }, remove: () => { removed = true; } };
  const sandbox = {
    document: { body: { classList: { add: name => bodyClasses.push(name) } },
      getElementById: id => id === 'app-loader' && !removed ? cover : null },
    window: { addEventListener: (name, callback) => events.set(name, callback), setTimeout: callback => timers.push(callback) },
  };
  vm.runInNewContext(html.slice(start, end), sandbox);
  events.get('flutter-first-frame')();
  assert.deepEqual(bodyClasses, ['has-flutter']);
  assert.deepEqual(coverClasses, ['is-hidden']);
  assert.equal(removed, false);
  timers.forEach(callback => callback());
  assert.equal(removed, true);
  assert.doesNotThrow(() => sandbox.window.fullposCompleteWebStartup());
});
