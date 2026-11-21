import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';
import assert from 'node:assert/strict';

function startup({ waiting = true } = {}) {
  const html = readFileSync(new URL('../../apps/fulltech_app/web/index.html', import.meta.url), 'utf8').replace(/\r\n/g,'\n');
  const start = html.indexOf('    (function () {\n      var storageKeyPrefix');
  const end = html.indexOf('    })();', start) + '    })();'.length;
  assert.ok(start >= 0 && end > start);
  const events = new Map(), workerEvents = new Map(), timers = [];
  let activations = 0, cacheClears = 0, reloads = 0;
  const worker = { state: 'installing', addEventListener: (n, cb) => workerEvents.set(n, cb),
    postMessage: () => { activations++; } };
  const registration = { waiting: waiting ? worker : null, installing: waiting ? null : worker,
    addEventListener() {} };
  const element = () => ({classList: {add(){},remove(){}},addEventListener(){},style:{},setAttribute(){}});
  const sandbox = {
    document: {getElementById: () => element(),addEventListener(){}},
    window: {
      location:{pathname:'/home',hash:'',search:'?handoff=single-use-fixture',reload(){reloads++;}},
      localStorage:{getItem:()=>null,setItem(){},removeItem(){}},
      caches:{keys:async()=>{cacheClears++;return[];}},
      matchMedia:()=>({matches:false,addEventListener(){}}),
      navigator:{userAgent:'test',serviceWorker:{controller:{},ready:Promise.resolve(registration),addEventListener(){}}},
      addEventListener:(n,cb)=>events.set(n,cb),setTimeout:cb=>{timers.push(cb);},
    },
  };
  vm.runInNewContext(html.slice(start,end),sandbox);
  return {events,workerEvents,worker,registration,timers,
    counts:()=>({activations,cacheClears,reloads})};
}

for (const waiting of [true,false]) {
  test(`an ${waiting?'already waiting':'installing'} update cannot interrupt the single-use handoff`, async () => {
    const app = startup({waiting});
    await new Promise(resolve=>setImmediate(resolve));
    if (!waiting) {
      app.worker.state='installed';app.registration.waiting=app.worker;
      app.workerEvents.get('statechange')();
    }
    await new Promise(resolve=>setImmediate(resolve));
    assert.deepEqual(app.counts(),{activations:0,cacheClears:0,reloads:0});
    app.events.get('flutter-first-frame')();
    await new Promise(resolve=>setImmediate(resolve));
    assert.equal(app.counts().activations,1);
    app.events.get('flutter-first-frame')();
    assert.equal(app.counts().activations,1);
  });
}
