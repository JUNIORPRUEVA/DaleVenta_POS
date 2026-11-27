import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const template = readFileSync(new URL('../../apps/fulltech_app/web/flutter_bootstrap.js', import.meta.url), 'utf8');
const source = template.replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '')
  .replace('{{flutter_service_worker_version}}', 'null')
  .replace("import(new URL('pdfjs/4.10.38/init.mjs', document.baseURI).href)", '__loadPdf()');

for (const failure of ['none', 'pdf', 'download', 'engine', 'runApp']) {
  test(`bootstrap handles ${failure} without an unreported startup failure`, async () => {
    const steps = [], timers = new Map();
    let recovery = 0;
    const sandbox = {
      __loadPdf: async () => { if (failure === 'pdf') throw Error('pdf'); },
      setTimeout: (fn, ms) => { timers.set(ms, fn); return ms; },
      clearTimeout: id => timers.delete(id), console: { warn() {} },
      window: { fullposFailWebStartup: () => recovery++, fullposSetWebStartupStage() {} },
      _flutter: { loader: { load: async options => {
        steps.push('load');
        if (failure === 'download') throw Error('download');
        await options.onEntrypointLoaded({ initializeEngine: async () => {
          steps.push('engine');
          if (failure === 'engine') throw Error('engine');
          return { runApp: async () => {
            steps.push('runApp');
            if (failure === 'runApp') throw Error('runApp');
          } };
        } });
      } } },
    };
    await vm.runInNewContext(source, sandbox);
    assert.equal(recovery, ['none', 'pdf'].includes(failure) ? 0 : 1);
    assert.equal(timers.size, 0);
    assert.deepEqual(steps, failure === 'download' ? ['load'] : failure === 'engine' ? ['load', 'engine'] : ['load', 'engine', 'runApp']);
  });
}

test('a stalled optional PDF module stops delaying Flutter after eight seconds', async () => {
  let timeout, loaded = false;
  const operation = vm.runInNewContext(source, {
    __loadPdf: () => new Promise(() => {}),
    setTimeout: (fn, ms) => { assert.equal(ms, 8000); timeout = fn; return 1; },
    clearTimeout() {}, console: { warn() {} }, window: { fullposFailWebStartup() {} },
    _flutter: { loader: { load: async () => { loaded = true; } } },
  });
  assert.equal(loaded, false);
  timeout();
  await operation;
  assert.equal(loaded, true);
});
