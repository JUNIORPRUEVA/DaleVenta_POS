import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';

test('the first Flutter frame reveals its splash without waiting for authentication', () => {
  const html = readFileSync(new URL('../../apps/fulltech_app/web/index.html', import.meta.url), 'utf8');
  const start = html.indexOf('    var fullposStartupCompleted = false;');
  const end = html.indexOf('    (function () {', start);
  assert.ok(start >= 0 && end > start);
  const events = new Map(), timers = [], bodyClasses = [], coverClasses = [];
  let removed = false;
  const cover = { classList: { add: name => coverClasses.push(name) }, remove: () => { removed = true; } };
  const sandbox = {
    document: { body: { classList: { add: name => bodyClasses.push(name) } },
      getElementById: id => id === 'app-loader' && !removed ? cover : null },
    window: { addEventListener: (name, callback) => events.set(name, callback),
      setTimeout: (callback, ms) => { if (ms === 220) timers.push(callback); return ms; },
      clearTimeout: () => {} },
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

test('stalled startup shows recovery after 45s without reloading a one-use ticket', () => {
  const html = readFileSync(new URL('../../apps/fulltech_app/web/index.html', import.meta.url), 'utf8');
  const start = html.indexOf('    var fullposStartupCompleted = false;');
  const end = html.indexOf('    (function () {', start);
  const timers = new Map(), recovery = { hidden: true }, copy = { textContent: 'Iniciando…' };
  const loader = { querySelector: () => copy, classList: { add() {} }, remove() {} };
  const sandbox = {
    document: { getElementById: id => id === 'app-loader' ? loader : recovery,
      body: { classList: { add() {} } } },
    window: { setTimeout: (callback, ms) => { timers.set(ms, callback); return ms; },
      clearTimeout: id => timers.delete(id), addEventListener() {} },
  };
  vm.runInNewContext(html.slice(start, end), sandbox);
  assert.equal(recovery.hidden, true);
  assert.ok(timers.has(45000));
  timers.get(45000)();
  assert.equal(recovery.hidden, false);
  assert.equal(copy.textContent, 'No se pudo abrir la aplicación');
  assert.equal(timers.size, 0);
  assert.match(html, /href="\/login\?access=retry"/);
  assert.match(html, /src="flutter_bootstrap.js" async onerror="window.fullposFailWebStartup\(\)"/);
  // A late first frame still succeeds, and subsequent errors cannot reopen the cover.
  recovery.hidden = true;
  sandbox.window.fullposCompleteWebStartup();
  sandbox.window.fullposFailWebStartup();
  assert.equal(recovery.hidden, true);
});
