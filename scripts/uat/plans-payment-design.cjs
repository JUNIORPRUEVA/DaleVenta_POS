const assert = require('node:assert/strict'), fs = require('node:fs/promises'), path = require('node:path');
const { spawn } = require('node:child_process'), WebSocket = require('ws');
const root = path.resolve(__dirname, '../..'), out = path.join(root, '.uat/plans-payment/design-evidence');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
class Cdp {
  constructor(url) {
    this.id = 0; this.pending = new Map(); this.ws = new WebSocket(url);
    this.ws.on('message', raw => { const m = JSON.parse(raw), p = this.pending.get(m.id); if (!p) return; this.pending.delete(m.id); m.error ? p.reject(Error(m.error.message)) : p.resolve(m.result); });
  }
  ready() { return new Promise((resolve, reject) => { this.ws.once('open', resolve); this.ws.once('error', reject); }); }
  send(method, params = {}) { const id = ++this.id; return new Promise((resolve, reject) => { this.pending.set(id, { resolve, reject }); this.ws.send(JSON.stringify({ id, method, params })); }); }
  async js(expression) { const r = await this.send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw Error(r.exceptionDetails.text); return r.result.value; }
}
async function main() {
  await fs.mkdir(out, { recursive: true });
  const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', ['--headless=new', '--disable-gpu', '--disable-background-networking', '--no-first-run', '--remote-debugging-port=9234', `--user-data-dir=${path.join(out, 'chrome')}`, 'about:blank'], { windowsHide: true, stdio: 'ignore' });
  let cdp;
  try {
    let version;
    for (let n = 0; n < 50; n++) { try { version = await (await fetch('http://127.0.0.1:9234/json/version')).json(); break; } catch (_) { await sleep(100); } }
    assert.ok(version);
    const tab = await (await fetch('http://127.0.0.1:9234/json/new?about:blank', { method: 'PUT' })).json();
    cdp = new Cdp(tab.webSocketDebuggerUrl); await cdp.ready();
    await cdp.send('Page.enable'); await cdp.send('Runtime.enable'); await cdp.send('Network.enable');
    const requests = [], exceptions = [], texts = [];
    cdp.ws.on('message', raw => { const m = JSON.parse(raw); if (m.method === 'Network.requestWillBeSent') requests.push(m.params.request.url); if (m.method === 'Runtime.exceptionThrown') exceptions.push(m.params.exceptionDetails.text); });
    const cases = [['catalogo', '/planes/catalogo'], ['pago', '/planes/pago?paso=pagar'], ['historial', '/planes/historial']];
    for (const [width, height] of [[1920, 1080], [1280, 900], [390, 844]]) {
      await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 600 });
      for (const [name, route] of cases) {
        await cdp.send('Page.navigate', { url: `http://127.0.0.1:4495/#${route}` });
        let ready = false;
        for (let n = 0; n < 100; n++) { ready = await cdp.js("document.querySelector('flutter-view')!==null"); if (ready) break; await sleep(100); }
        assert.ok(ready, route); await sleep(900);
        await cdp.js("document.querySelector('flt-semantics-placeholder')?.click()"); await sleep(150);
        const text = await cdp.js('document.body.innerText');
        assert.ok(text.includes(name === 'catalogo' ? 'Elige tu plan' : name === 'pago' ? 'Subir comprobante' : 'Tus ordenes'), text);
        texts.push({width, name, text});
        const shot = await cdp.send('Page.captureScreenshot', { format: 'png' });
        await fs.writeFile(path.join(out, `${width}-${name}.png`), Buffer.from(shot.data, 'base64'));
        assert.equal(await cdp.js('document.documentElement.scrollWidth>window.innerWidth'), false, route);
      }
    }
    assert.deepEqual(exceptions, []);
    // Flutter fallback font files contain no application/customer data.
    const unexpected = requests.filter(url => /^https?:/.test(url) && !url.startsWith('http://127.0.0.1:4495/') && !url.startsWith('https://fonts.gstatic.com/'));
    assert.deepEqual(unexpected, []);
    await fs.writeFile(path.join(out, 'result.json'), JSON.stringify({ result: 'PASS', screenshots: 9, viewports: [1920, 1280, 390], apiRequests: 0, exceptions: [] }, null, 2));
    await fs.writeFile(path.join(out, 'semantics.json'), JSON.stringify(texts, null, 2));
    console.log('PASS: 9 screenshots, no API requests, no JavaScript exceptions or horizontal overflow.');
  } finally { if (cdp) { await cdp.send('Browser.close').catch(() => {}); cdp.ws.close(); } chrome.kill(); }
}
main().catch(error => { console.error(error.stack); process.exitCode = 1; });
